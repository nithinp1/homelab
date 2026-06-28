# Homelab Infrastructure

Production-grade self-hosted lab on two laptops. Focus: **Proxmox hypervisor with advanced GPU passthrough + containerized applications**.

---

## Quick Specs

| Component | Hardware | Status |
|-----------|----------|--------|
| **Hypervisor** | MSI GF65 Thin 10UE | ✅ Running (Proxmox VE 9.1.6) |
| **Application Server** | Dell Vostro 1550 | ✅ Running (Ubuntu 24.04 LTS) |
| **VMs on Proxmox** | 3 instances | ✅ Testing Windows, Personal Windows, Linux Ubuntu |
| **Network** | IPv4 only | ✅ LAN-based, no IPv6 yet |
| **Containers** | Docker on Dell Vostro | ✅ n8n, Nextcloud (partial) |
| **Power Model** | Laptop-based | ⏸️ On-demand (not 24/7 due to thermal/power) |

---

## Hardware

### MSI GF65 Thin 10UE (Proxmox Host)

**Specs:**
- CPU: Intel Core i7-10750H (6 cores, 12 threads, Comet Lake)
- GPU: NVIDIA GeForce RTX 3060 Mobile (6GB GDDR6, 75W TGP, muxless Optimus)
- RAM: 16GB DDR4
- Storage: Western Digital 1TB SN730 NVMe SSD (WDC PC SN730 SDBPNTY-1T00-1032)
- OS: Proxmox VE 9.1.6
- Board: MS-16W1 (fully muxless Optimus, no hardware MUX)

**Role:** Hypervisor for all VMs. GPU exclusively assigned to one VM at a time.

**Known Constraint:** Due to VFIO GPU passthrough design, **only one VM can use the RTX 3060 simultaneously**. Attempting to run multiple GPUs = PCI resource conflict.

### Dell Vostro 1550 (Docker/Application Server)

**Specs:**
- CPU: Intel i3-2310M (4 cores @ 2.1 GHz)
- RAM: 6GB DDR3
- Storage: Crucial BX500 500GB SSD (CT500BX500SSD1)
- OS: Ubuntu 24.04.4 LTS x86_64
- Network: Primary role is Docker container host + WoL sender

**Role:** Persistent application server. Hosts n8n, Nextcloud (experimental), and other Docker containers. Sends Wake-on-LAN to Proxmox host on demand.

---

## Proxmox VE Infrastructure

**File:** [`proxmox/`](./proxmox/)

### Virtual Machines

| VM Name | OS | vCPU | RAM | GPU | Purpose | Status |
|---------|----|----|-----|-----|---------|--------|
| Testing Windows Env | Windows 11 | 12 | 12GB | RTX 3060 | Apps with low reputation, testing | ✅ Running |
| Personal Windows Env | Windows 11 | 12 | 12GB | RTX 3060 | Video editing, Parsec streaming | ✅ Running |
| Linux Ubuntu Env | Ubuntu 22.04 | 12 | 12GB | None | Development, Ollama LLM server | ✅ Running |
| OpenClaw | Ubuntu 22.04 (LXC) | 4 | 2GB | None | OpenClaw automation sandbox | OOB |

**GPU Scheduling Note:**  
Only **one VM** can access the RTX 3060 at a time. The GPU is bound to VFIO and passed through via PCIe. Attempting to assign it to multiple VMs results in `PCI device already in use` error.

### GPU Passthrough (RTX 3060 Mobile on Muxless Optimus)

**File:** [`proxmox/gpu-passthrough/README.md`](./proxmox/gpu-passthrough/README.md) — **Detailed technical documentation**

**Key Achievement:** Solved muxless Optimus GPU passthrough on a laptop (non-standard, kernel-level debugging required).

**Core components:**
1. **IOMMU isolation:** RTX 3060 in dedicated IOMMU Group 2 (confirmed clean)
2. **VFIO binding:** Both GPU devices (01:00.0 VGA + 01:00.1 Audio) bound to vfio-pci
3. **Kernel tuning:** `initcall_blacklist=sysfb_init` (prevents host framebuffer claiming GPU)
4. **SSDT Battery injection:** Virtual ACPI battery to fix NVIDIA driver ACPI polling (Code 43 fix)
5. **vBIOS ROM:** Exact subsystem match (1462:12F2) via method 1 (Linux host extraction)
6. **VM config:** q35 machine, OVMF UEFI, `cpu: host,hidden=1` (not `kvm=off`)
7. **Remote display:** Parsec (creates virtual display in VM) + VDD (fallback)

**Result:** Stable GPU passthrough. Windows VMs can game at 1080p 60fps or edit 4K video.

**Troubleshooting:** See `proxmox/gpu-passthrough/README.md` — includes full diagnostic table and common issues.

### SSH Remote Access

SSH access to Proxmox host either via **Tailscale VPN** or local (critical before GPU passthrough work).

```bash
tailscale status  # Verify connection
ssh root@100.x.x.x  # Connect via Tailscale IP
```

This was essential for safety during GPU configuration (prevents lockouts if display fails).

---

## Application Stack (Dell Vostro 1550)

### Docker Containers

#### n8n Workflow Automation

**Status:** ✅ Running

**Purpose:** Automate repetitive workflows (video processing, file handling, API calls).

**Current Workflows:**
- Video reformatting (16:9 → 9:16 portrait for social media Reels/Shorts)
- Custom media processing pipelines

**Deployment:** Docker Compose  
**Details:** See [`n8n/README.md`](./n8n/README.md) + [`n8n/docker-compose.yml`](./n8n/docker-compose.yml)

#### Nextcloud File Sync

**Status:** ⚠️ Partial (configs removed, not production)

**What was attempted:** Self-hosted file sync with Caddy reverse proxy + split-horizon DNS.

**Why discontinued:** Caddy reverse proxy setup failed. DNS rewrite rules depend on Caddy working, so AdGuard DNS rewrite is disabled.

**Current state:** Nextcloud Docker setup exists in repo, but lacks complete config/docs. Not currently recommended for production use.

**If you want to restart:** See [`nextcloud/README.md`](./nextcloud/README.md) (partial guide) + refer to official Nextcloud docs.

### Other Services

- **Fail2ban:** Intrusion prevention (jails for SSH, service-level monitoring)
- **UFW:** Host firewall (allow SSH 22, HTTP 80, HTTPS 443, DNS 53)
- **Docker volumes:** Persistent data for n8n workflows + media processing

---

## Networking

**Current State:** IPv4 only (LAN-based)

**File:** [`networking/adguard-dns/`](./networking/adguard-dns/)

### IPv4 Setup

- **Dell Vostro:** 192.168.x.x (on LAN bridge)
- **Proxmox Host:** 192.168.x.x (on LAN bridge)
- **VMs:** Assigned via DHCP on `vmbr0` bridge

### IPv6

**Status:** ❌ Not yet configured

**Planned:** radvd (Router Advertisement Daemon) for stateless IPv6 autoconfiguration on VMs.  
**Blocker:** Low priority relative to GPU passthrough + container stability.

**Note:** IPv6 setup requires:
1. ISP-provided IPv6 prefix or ULA assignment
2. radvd installed + configured on host
3. Proxmox firewall rules to allow ICMPv6 RA packets
4. VM bridges configured to relay advertisements

This can be added later. See `networking/ipv6-radvd/` folder for template (not yet active).

### DNS

**AdGuard DNS:** Set up in Docker (port 53) but rewrite rules **disabled** due to Caddy failure.

**Reason:** Caddy was meant to handle reverse proxy + HTTPS termination + split-horizon DNS. Since Caddy failed, DNS rewrite is not currently active. Services are accessed directly by IP or manual hostname entries.
Reverse proxy complexity (Let's Encrypt cert renewal, split-horizon DNS synchronization) can be a single point of failure. Simpler architecture recommended for home labs.

---

## Security Hardening

**File:** [`security/`](./security/)

### Fail2ban (Intrusion Prevention)

**Active jails:**
- `sshd` — Block IPs after 5 failed SSH login attempts (1-hour ban)
- Service-level monitoring for brute-force attacks

**Config:** [`security/fail2ban/README.md`](./security/fail2ban/README.md)

### UFW Firewall

**Inbound rules:**
- Allow: SSH (22), HTTP (80), HTTPS (443), DNS (53)
- Allow: LAN-to-LAN traffic (192.168.x.0/24)
- Deny: Everything else (default)

**Outbound:** Allow all (default)

### SSH Hardening

- Root login disabled
- Password auth disabled (key-based only)
- X11 forwarding disabled
- Fail2ban monitoring active

### Tailscale VPN

Provides encrypted tunnel to Proxmox host from anywhere (internet connectivity not exposed to firewall).

---

## File Structure

```
homelab/
├── README.md                                    # You are reading this
├── proxmox/
│   ├── README.md                                # Proxmox overview
│   ├── gpu-passthrough/
│   │   └── README.md                            # DETAILED GPU PT guide (Step 1-8)
│   ├── vms/                                     # VM configs (Windows, Ubuntu)
│   └── lxc/                                     # LXC container configs
├── n8n/
│   ├── README.md                                # n8n setup guide
│   ├── docker-compose.yml                       # Full stack
│   └── workflows/                               # Workflow JSON exports
├── nextcloud/
│   ├── README.md                                # Nextcloud (incomplete)
│   └── nextcloud-compose/                       # Docker compose (configs removed)
├── networking/
│   └── adguard-dns/                             # AdGuard DNS
├── security/
│   └── fail2ban/
│       └── README.md                            # Fail2ban config
└── docs/
    └── ARCHITECTURE.md                          # (planned) Deep dive
```

---

## What Actually Works

✅ **Proxmox VE + GPU Passthrough**
- Stable, well-documented, debugged
- Supports 3 VMs (2 Windows with GPU, 1 Linux headless, 1 LXC)
- Remote access via Tailscale
- Parsec/VDD for remote display

✅ **n8n Automation**
- Running in Docker on Dell Vostro
- Video reformatting workflows active
- API integrations working

✅ **Security**
- Fail2ban + UFW active
- SSH hardened (key-only auth)
- Tailscale VPN tunnel for admin access

⚠️ **Nextcloud**
- Docker setup exists, but config/deployment incomplete
- Not recommended for production use (refer to official docs if restarting)

❌ **Caddy Reverse Proxy**
- Setup attempted, failed
- Reason: TLS cert automation + split-horizon DNS complexity
- Recommendation: Simpler architecture or managed HTTPS solution

❌ **IPv6 + radvd**
- Not configured (low priority)
- Template docs exist, can be added later

---

## Key Learnings

### 1. Muxless Optimus GPU Passthrough is Non-Trivial

**Challenge:** NVIDIA RTX 3060 Mobile has no direct display wiring (all outputs through Intel iGPU). Standard GPU passthrough guides don't work.

**Solution:** 
- SSDT battery table injection (fix NVIDIA driver ACPI polling)
- `initcall_blacklist=sysfb_init` (prevent host from claiming GPU)
- Correct vBIOS ROM matching subsystem ID
- `cpu: host,hidden=1` (not `kvm=off`)

**Result:** Stable, documented setup that others can replicate.

See: [`proxmox/gpu-passthrough/README.md`](./proxmox/gpu-passthrough/README.md) for complete guide.

### 2. Reverse Proxy Complexity is a Single Point of Failure

**Initial plan:** Caddy (HTTPS termination) + AdGuard DNS (split-horizon) for seamless LAN/WAN access.

**Reality:** Caddy setup failed (likely cert renewal or config syntax). When the reverse proxy breaks, DNS rewrite breaks, and services become unreachable.

**Lesson:** Simpler is better. Consider:
- Direct IP-based access (if acceptable)
- Hardware-based reverse proxy (separate device)
- Managed HTTPS solutions (CloudFlare Tunnel, Ngrok)

### 3. Home Labs are Power-Constrained

**Constraint:** Laptop hardware (thermal limits, battery, AC adapter capacity).

**Mitigation:** 
- On-demand startup (not 24/7)
- Wake-on-LAN for remote activation
- Active cooling monitoring
- Resource limits on VMs (12 vCPU, 12GB RAM per VM)

---

## Future Improvements

### High Priority
- [X] **Document final GPU passthrough setup** ✅ Done (see proxmox/gpu-passthrough/README.md)
- [X] **Complete n8n workflow examples** (video reformatting, API pipelines)
- [ ] **IPv6 setup** (if ISP provides prefix) — radvd + firewall rules

### Medium Priority
- [ ] **Nextcloud restart** (simpler config, no Caddy) — or use DDNS + direct HTTPS
- [ ] **Monitoring stack** (Prometheus + Grafana for Proxmox metrics)
- [X] **Backup automation** ✅ Done(see backup/scripts)

### Low Priority
- [ ] **Kubernetes on Proxmox** (MicroK8s/K3s) — overkill for home lab
- [ ] **CI/CD pipeline** (GitHub Actions → VM deployment) — nice-to-have
- [ ] **SIEM** (centralized logging + dashboard) — future feature

---

## Troubleshooting Quick Reference

### Proxmox Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Host freezes on VM boot | `initcall_blacklist=sysfb_init` not set | Add to GRUB and reboot |
| GPU not claimed by VFIO | nvidia/nouveau kernel driver loaded | Blacklist in `/etc/modprobe.d/blacklist.conf` |
| Code 43 in Windows | ACPI battery missing | SSDT injection (Step 5 in GPU passthrough guide) |
| PCI device already in use | GPU assigned to multiple VMs | Can only assign to one VM at a time |
| Tailscale drops | Network hiccup during GPU handoff | Normal — reconnects within 60s |

### Dell Vostro Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| n8n container exits | Memory exhaustion (6GB RAM limit) | Reduce concurrent workflows or upgrade RAM |
| Docker port conflicts | Service bound to same port | `docker ps` and kill conflicting container |
| Fail2ban false positives | Legitimate IPs flagged | Whitelist in `/etc/fail2ban/jail.local` |

### Network Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| LAN clients can't reach VMs | Firewall blocking traffic | Check UFW rules on Dell Vostro + Proxmox firewall |
| DNS not resolving | AdGuard DNS disabled | Check if port 53 is listening (`netstat -tlnp \| grep :53`) |
| Caddy cert renewal fails | Let's Encrypt validation blocked | Caddy is discontinued — use manual cert management or alternative |

### For Detailed GPU Passthrough Troubleshooting

See [`proxmox/gpu-passthrough/README.md`](./proxmox/gpu-passthrough/README.md) — includes full diagnostic table (Code 43, Code 31, ROM issues, Optimus-specific problems, etc.)

---

## References

- [Proxmox GPU Passthrough (Official)](https://pve.proxmox.com/wiki/Pcie_passthrough)
- [SSDT Battery Injection (Optimus)](https://gist.github.com/Misairu-G/616f7b2756c488148b7309addc940b28)
- [Proxmox Forum — PVE 9 GPU Passthrough](https://forum.proxmox.com/threads/2025-proxmox-pcie-gpu-passthrough-with-nvidia.169543/)
- [n8n Documentation](https://docs.n8n.io/)
- [Fail2ban Official](https://www.fail2ban.org/wiki/index.php/Main_Page)

---

## Contact

- **GitHub:** [nithinp1/homelab](https://github.com/nithinp1/homelab)
- **LinkedIn:** [linkedin.com/in/nithin-praveen](https://www.linkedin.com/in/nithin-praveen/)

---

**Last Updated:** 28-06-2026  
**Lab Status:** ✅ Operational (on-demand, power-constrained)  
**Primary Focus:** Proxmox hypervisor + GPU passthrough  
**Secondary:** Container automation (n8n)# Home Lab
