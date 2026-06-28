# GPU Passthrough on Muxless Optimus — MSI GF65 Thin 10UE
## NVIDIA RTX 3060 Mobile → Proxmox VE 9.1.6

---

## Hardware Profile

| Component | Detail |
|-----------|--------|
| Laptop | MSI GF65 Thin 10UE (Board: MS-16W1) |
| CPU | Intel Core i7-10750H (Comet Lake, 12 cores) |
| GPU | NVIDIA GeForce RTX 3060 Mobile (GA106, 6GB GDDR6) |
| GPU TGP | 75W (confirmed from vBIOS) |
| GPU PCI ID | 10DE:2520 |
| GPU Subsystem | 1462:12F2 (MSI GF65 specific) |
| GPU Audio | 10DE:228E |
| GPU PCIe Slot | 0000:01:00.0 |
| IOMMU Group | Group 2 (isolated, confirmed clean) |
| Display Topology | Muxless Optimus — HDMI physically wired through Intel iGPU |
| Hypervisor | Proxmox VE 9.1.6 (kernel 6.17.13-2-pve, QEMU 10.1.2) |

---

## The Core Challenge

The MSI GF65 Thin 10UE uses a **fully muxless Optimus architecture** confirmed by board schematics (MS-16W1 Rev 10):

```
RTX 3060 → PCIe x8 Gen3 → Intel i7-10750H CPU
                                    ↓
                           Intel DDI ports
                                    ↓
                           HDMI Redrive chip
                                    ↓
                           HDMI 1.4 port (chassis)
```

The RTX 3060 has **zero direct wiring** to any display output. This means:

- HDMI dummy plugs **do not work** — the HDMI port is owned by Intel iGPU
- Standard GPU passthrough guides written for desktop GPUs do not apply directly
- The NVIDIA mobile driver expects an ACPI battery during initialization — VMs have none
- This causes the infamous **Error Code 43** on mobile Optimus GPUs in VMs

lspci reports the GPU as `VGA compatible controller` (class 0300) rather than `3D controller` (class 0302). This does NOT mean it has a direct display connection — the schematics confirm it is fully muxless regardless of the PCI class code.

---

## Root Cause of Error Code 43 (Mobile Specific)

There are two historical types of Code 43:

**Type 1 — Hypervisor Detection (OBSOLETE)**
NVIDIA drivers before version 465.89 blocked GeForce GPUs in VMs entirely. This is fixed in all modern drivers. Spoofing `vendor_id` and `kvm=off` is no longer needed for this reason.

**Type 2 — ACPI Battery Polling (ACTIVE — This is your problem)**
The NVIDIA mobile driver calls ACPI `_BIF` and `_BST` methods during initialization to check battery status. VMs have no battery. The driver receives no response, assumes hardware failure, and triggers Code 43.

**The fix: inject a virtual ACPI battery table (SSDT) into the VM.**

---

## Prerequisites Checklist

Before attempting passthrough, verify all of these:

```
✅ Proxmox VE installed (full disk, not dual boot)
✅ Tailscale installed on Proxmox host (remote access backup)
✅ SSH verified working via Tailscale before touching GPU config
✅ IOMMU enabled in BIOS (VT-d confirmed via dmesg)
✅ GPU in isolated IOMMU group (Group 2, confirmed)
✅ Both GPU devices bound to vfio-pci (01:00.0 and 01:00.1)
✅ initcall_blacklist=sysfb_init in GRUB (prevents host freeze)
✅ Correct vBIOS ROM for subsystem 1462:12F2
✅ SSDT battery table compiled and placed
```

---

## Step 1 — Secure Remote Access First

**Do not skip this step. Losing SSH access during GPU passthrough is a real risk.**

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Bring up with subnet routing (redundancy if small laptop fails)
tailscale up --advertise-routes=192.168.20.0/24 --advertise-exit-node

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
sysctl -p

# Enable Tailscale on boot
systemctl enable tailscaled

# Verify
tailscale status
```

Approve subnet routes at https://login.tailscale.com/admin/machines

**Test SSH via Tailscale IP before proceeding:**
```bash
ssh root@100.x.x.x
```

---

## Step 2 — GRUB Kernel Parameters

```bash
nano /etc/default/grub
```

Set this exact line:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt initcall_blacklist=sysfb_init"
```

**Important notes:**
- `video=efifb:off` is **broken on Proxmox kernel 5.15+** — do not use it
- `nofb nomodeset` can be added but are not required with `initcall_blacklist=sysfb_init`
- `initcall_blacklist=sysfb_init` prevents the host framebuffer from claiming the GPU before VFIO

```bash
update-grub
reboot
```

Verify after reboot:
```bash
cat /proc/cmdline | grep initcall_blacklist
# Should show: initcall_blacklist=sysfb_init
```

---

## Step 3 — VFIO Module Configuration

```bash
# Create modules load file (not /etc/modules which is deprecated)
nano /etc/modules-load.d/vfio.conf
```

Add:
```
vfio
vfio_iommu_type1
vfio_pci
```

```bash
# Blacklist Nvidia from host
nano /etc/modprobe.d/blacklist.conf
```

Add:
```
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
blacklist nvidia_drm

```

```bash
# Bind GPU to VFIO by device ID
nano /etc/modprobe.d/vfio.conf
```

Add:
```
options vfio-pci ids=10de:2520,10de:228e disable_vga=1
```

```bash
update-initramfs -u -k all
reboot
```

Verify after reboot:
```bash
# Both should show: Kernel driver in use: vfio-pci
lspci -k | grep -A3 "01:00"
```
It Should look like this
```bash 
01:00.0 VGA compatible controller: NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile / Max-Q] (rev a1)
        Subsystem: Micro-Star International Co., Ltd. [MSI] Device 12f2
        Kernel driver in use: vfio-pci
        Kernel modules: nvidiafb, nouveau, nova_core
01:00.1 Audio device: NVIDIA Corporation GA106 High Definition Audio Controller (rev a1)
        Subsystem: Micro-Star International Co., Ltd. [MSI] Device 12f2
        Kernel driver in use: vfio-pci
        Kernel modules: snd_hda_intel
```
```bash
# Check VFIO claimed both devices
dmesg | grep -i vfio
# Should show: vfio_pci: add [10de:2520] and vfio_pci: add [10de:228e]

# Verify IOMMU group exists
ls /dev/vfio/
```
Should show: 2  devices  vfio

---

## Step 4 — Extract vBIOS ROM

The muxless architecture prevents QEMU from reading the GPU ROM directly from the PCIe bus at runtime. A correct ROM file must be supplied manually.

**Critical:** The ROM must exactly match your GPU's subsystem ID: **1462:12F2**

### Method A — Extract from Linux host (cleanest)

```bash
# Temporarily unbind from VFIO
echo "0000:01:00.0" > /sys/bus/pci/drivers/vfio-pci/unbind

# Enable ROM read access
echo 1 > /sys/bus/pci/devices/0000:01:00.0/rom

# Extract
cat /sys/bus/pci/devices/0000:01:00.0/rom > /usr/share/kvm/244426.rom

# Disable ROM access
echo 0 > /sys/bus/pci/devices/0000:01:00.0/rom

# Rebind to VFIO
echo "0000:01:00.0" > /sys/bus/pci/drivers/vfio-pci/bind
```

### Method B — TechPowerUp verified ROM
I searched this and could only find a unverified ROM so this might not be working for you, but if you are using Windows before Installing Proxmox. 
You can install techpowerup gpu-z to get the same file 
using [this tutorial](https://nvidia.custhelp.com/app/answers/detail/a_id/4188/~/extracting-the-geforce-video-bios-rom-file)

else if you find verified ROM in techpowerup
Confirmed correct ROM for MSI GF65 Thin 10UE:
- **Filename:** 244426.rom
- **VBIOS Version:** 94.06.13.00.91
- **Subsystem ID:** 1462:12F2 ✅
- **GPU Clock:** 1050 MHz / Boost: 1402 MHz
- **TGP:** 70W target / 75W limit ✅
- **URL:** https://www.techpowerup.com/vgabios/ (search RTX 3060 Mobile MSI 12F2)

Place ROM file:
```bash
cp 244426.rom /usr/share/kvm/244426.rom
chmod 644 /usr/share/kvm/244426.rom
chown root:root /usr/share/kvm/244426.rom

# Verify size (should be ~976KB)
ls -lh /usr/share/kvm/244426.rom
#Example -rw-r--r-- 1 root root 976K Mar 24 22:37 msi_3060_mobile.rom
```

**ROMs to avoid:**
- Any ROM with subsystem 1462:12F1 (different MSI variant)
- Any ROM with subsystem 1462:12EF (130W variant — dangerous power mismatch)
- Stripped ROMs (removing vBIOS header bytes causes VM hang/freeze)

---

## Step 5 — SSDT Battery Table Injection

This is the definitive fix for mobile-specific Error Code 43. It injects a virtual battery into the VM's ACPI namespace so the NVIDIA driver's power polling call receives a valid response.

```bash
echo "U1NEVKEAAAAB9EJPQ0hTAEJYUENTU0RUAQAAAElOVEwYEBkgoA8AFVwuX1NCX1BDSTAGA\
BBMBi5fU0JfUENJMFuCTwVCQVQwCF9ISUQMQdAMCghfVUlEABQJX1NUQQCkCh8UK19CS\
UYApBIjDQELcBcLcBcBC9A5C1gCCywBCjwKPA0ADQANTElPTgANABQSX0JTVACkEgoEAAAL\
cBcL0Dk=" | base64 --decode > /var/lib/libvirt/images/SSDT1.dat
```

### Configure AppArmor to allow QEMU to read the file
```bash
mkdir -p /var/lib/libvirt/images/

# Add permission to AppArmor QEMU template
echo "/var/lib/libvirt/images/SSDT1.dat rk," >> /etc/apparmor.d/libvirt/TEMPLATE.qemu

systemctl restart apparmor
```
Alternatively use this if not working (AI's plan)(not tested ):

### Install compiler
```bash
apt install acpica-tools -y
```

### Create SSDT source
```bash
nano /tmp/ssdt-battery.dsl
```

Add:
```asl
DefinitionBlock ("", "SSDT", 2, "BOCHS", "BXPCSSDТ", 0x00000001)
{
    Scope (\_SB.PCI0)
    {
        Device (BAT0)
        {
            Name (_HID, EisaId ("PNP0C0A"))
            Name (_UID, Zero)
            Name (_STA, 0x1F)
            Method (_BIF, 0, NotSerialized)
            {
                Return (Package ()
                {
                    One,
                    0x1130,
                    0x1130,
                    One,
                    0x2A30,
                    0x6F,
                    0x0A,
                    One,
                    One,
                    "LION",
                    "0",
                    "Real",
                    "MSI"
                })
            }
            Method (_BST, 0, NotSerialized)
            {
                Return (Package ()
                {
                    0x02,
                    0x0400,
                    0x1000,
                    0x2A30
                })
            }
        }
    }
}
```



---

## Step 6 — VM Configuration

### Create VM in Proxmox Web UI

| Setting | Value |
|---------|-------|
| Machine | q35 |
| BIOS | OVMF (UEFI) |
| CPU | host, hidden=1 |
| Memory | 12288 MB (leave ~4GB for host) |
| Disk | VirtIO Block, 256GB |
| Network | VirtIO |
| Display | std (after parsec install `none`) |
| TPM | v2.0 |

### Final VM config `/etc/pve/qemu-server/100.conf`

```
args: -acpitable file=/var/lib/libvirt/images/SSDT1.dat -global PIIX4_PM.disable_s3=1 -global PIIX4_PM.disable_s4=1
balloon: 0
bios: ovmf
boot: order=virtio0;ide0;net0
cores: 12
cpu: host,hidden=1
efidisk0: local-lvm:vm-100-disk-0,efitype=4m,ms-cert=2023w,pre-enrolled-keys=1,size=4M
hostpci0: 0000:01:00,pcie=1,rombar=1,romfile=244426.rom,x-vga=1
ide0: local:iso/virtio-win-0.1.285.iso,media=cdrom,size=771138K
machine: pc-q35-10.1
memory: 12288
name: Testing-vm
net0: virtio=BC:24:11:68:85:6B,bridge=vmbr0,firewall=1
numa: 0
onboot: 0
ostype: win11
scsihw: virtio-scsi-single
sockets: 1
tpmstate0: local-lvm:vm-100-disk-1,size=4M,version=v2.0
vga: std
virtio0: local-lvm:vm-100-disk-2,cache=writeback,discard=on,iothread=1,size=256G
```

**Key config notes:**
- `cpu: host,hidden=1` — hides hypervisor from Nvidia (PVE 9 syntax, NOT `kvm=off` in cpu line)
- `kvm: 0` — do NOT use, breaks `cpu: host` requirement
- `vga: std` — use Console for windows setup, change back to 'none' after parsec with Virtual Display is installed and running
- `hostpci0` uses `0000:01:00` not `0000:01:00.0` — Proxmox 9 handles all functions
- `args` line carries the SSDT injection and ACPI power management flags

---

## Step 7 — Windows Installation
VirtIO should be Uploaded to Proxmox via
Datacenter -> pve -> local (pve) -> ISO images -> Upload -> File: Select image from your client PC or PC which you are using to see proxmox dashboard 
ISO is available [here](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/?C=M;O=D). First one is the latest one.
### During install (disk not visible)
Windows cannot see VirtIO disk by default:
1. Click **Load Driver**
2. Browse to VirtIO ISO → `viostor` → `w11` → `amd64`
3. Disk appears — select and continue

### After Windows boots
1. Run `virtio-win-guest-tools.exe` from VirtIO ISO
2. Download and install NVIDIA Game Ready Driver for RTX 3060 Laptop, Windows 11
3. Reboot

### Display for remote access (no physical display needed)
Since HDMI is wired through Intel iGPU and the VM has no physical display:

1. Install [**Parsec**](https://parsec.app/downloads) inside VM — creates virtual display with RTX 3060 
2. Install [**VDD**](https://github.com/VirtualDrivers/Virtual-Display-Driver/releases) inside VM — if Parsec Virtual display fails Fails

```
Remote access stack:
Client → Parsec (Creates its own direct connection)→ Parsec VD/VDD → RTX 3060
```

---

## Step 8 — Fan Control on Proxmox Host

EC (Embedded Controller) cannot be passed through to a VM — it's firmware, not a PCIe device. It stays with the Proxmox host. This is actually ideal since fan control covers all VMs running on the machine.

```bash
# Install msi-ec (MSI specific EC controller for Linux)
# Check if MS-16W1 (GF65 board name) is supported:
# github.com/BeardOverflow/msi-ec

# Alternative: nbfc-linux (broader MSI support)
# github.com/nbfc-linux/nbfc-linux
```

---

## Troubleshooting Reference

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Host freezes randomly | Host blacklist is not properly configured | Fix the nano /etc/modprobe.d/blacklist.conf exactly as mentioned|
| Host freezes on VM start | sysfb_init claiming GPU | Add `initcall_blacklist=sysfb_init` to GRUB |
| QEMU exit code 1 / OOM | All 16GB assigned to VM | Set memory to 12288, leave ~4GB for host |
| `cpu: host requires KVM` | Used `kvm: 0` config line | Remove `kvm: 0`, use `cpu: host,hidden=1` only |
| ROM file not found | Wrong filename or permissions | `chmod 644` and `chown root:root` the ROM file |
| VFIO group error / no device | sysfb or driver conflict | Verify `initcall_blacklist=sysfb_init` in cmdline |
| Code 43 on RTX 3060 | ACPI battery polling failure | SSDT battery table injection (Step 5) |
| Code 31 on Platform Framework | Optimus driver expects iGPU alongside dGPU | SSDT injection resolves the ACPI mismatch |
| noVNC black screen | `vga: none` set correctly | Expected — use Sunshine/Moonlight instead |
| Wrong ROM subsystem | Using 12EF or 12F1 instead of 12F2 | Use only ROM matching subsystem 1462:12F2 |
| Tailscale drops during GPU handoff | Host network hiccup during VFIO claim | Normal — reconnects within 60 seconds |

---

## Architecture Summary

```
Physical Hardware:
MSI GF65 Thin 10UE (MS-16W1)
├── Intel i7-10750H (iGPU: UHD 630) — IOMMU Group 0
│   └── Owns: Physical display, HDMI port, chassis panel
└── NVIDIA RTX 3060 Mobile — IOMMU Group 2 (isolated)
    └── PCIe x16 Gen3 → CPU → iGPU → HDMI (muxless)

Proxmox VE 9.1.6 (bare metal on full SSD):
├── Host OS (Debian/Linux kernel 6.17)
│   ├── Tailscale (SSH access from anywhere)
│   ├── msi-ec / nbfc-linux (fan curves via EC)
│   └── VFIO claims RTX 3060 exclusively
├── Testing-vm/Personal-vm (Windows 11)
|   ├── RTX 3060 passed through via IOMMU
|   ├── SSDT virtual battery (ACPI fix)
|   ├── IddSampleDriver (virtual display)
|   └── Sunshine → Moonlight streaming
└── Linux-vm (Windows 11)
    ├── RTX 3060 passed through via IOMMU
    ├── SSDT virtual battery (ACPI fix)
    ├── Headless Install
    └── via SSH

Remote Access:
Phone/Laptop → Tailscale → Proxmox Host
```

---

## Key Lessons Learned

1. **Tailscale before GPU passthrough** — always secure remote access first
2. **`initcall_blacklist=sysfb_init`** not `video=efifb:off` — latter is broken on kernel 5.15+
3. **SSDT battery injection is mandatory** for any muxless Optimus laptop GPU passthrough
4. **ROM subsystem must exactly match** — 12F2 not 12F1 or 12EF
5. **`kvm: 0` breaks `cpu: host`** — use `cpu: host,hidden=1` only in PVE 9
6. **Dummy HDMI plugs are useless** — HDMI port is Intel iGPU only per schematics
7. **VGA compatible vs 3D controller** lspci class code does not determine muxless status — schematics do

---

## References

- [Optimus Laptop dGPU Passthrough Guide](https://gist.github.com/Misairu-G/616f7b2756c488148b7309addc940b28)
- [Proxmox Forum — SSDT Battery Fix](https://forum.proxmox.com/threads/gpu-passthrough-code-43-unable-to-resolve.107996/)
- [Proxmox Forum — 2025 PCIe GPU Passthrough with NVIDIA](https://forum.proxmox.com/threads/2025-proxmox-pcie-gpu-passthrough-with-nvidia.169543/)
- [TechPowerUp GPU BIOS Database](https://www.techpowerup.com/vgabios/)
- [MS-16W1 Board Schematics Rev 10](https://www.scribd.com/document/999244960/MS-16W1-MS-16W11-Schematic-Boardview-Reference) (display topology confirmation and why dummy plug might fail)
