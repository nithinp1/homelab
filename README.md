# Home Lab

### MSI GF65 Thin 10UE (Proxmox Host)

**Specs:**
- CPU: Intel Core i7-10750H (6 cores, 12 threads)
- GPU: NVIDIA GeForce RTX 3060 Max-Q Laptop GPU (Muxless Optimus)
- RAM: 16GB
- Storage: Western Digital 1TB SN730 NVMe SSD (WDC PC SN730 SDBPNTY-1T00-1032)
- OS: Proxmox VE 9.1.6

### Dell Vostro 1550 (Server Node)

**Specs:**
- CPU:  Intel i3-2310M (4) @ 2.100GHz
- RAM: 6GB
- Storage: Crucial BX500 500GB SSD (CT500BX500SSD1)
- OS: Ubuntu 24.04.4 LTS x86_64

| Name | Type | OS | Purpose | Status |
|------|------|----|---------|---------| 
| [Testing Windows Env] | VM | Windows 11 |Test apps on internet with low reputaion With GPU passthrough, Parsec streaming | Stopped |
| [Personal Windows Env] | VM | Windows 11 | Video editing with GPU passthrough, Parsec streaming | Stopped |
| [Linux Ubuntu Env] | VM | Ubuntu 22.04 | Development environment and OLLAMA server | Running |
| [OpenClaw] | LXC | Ubuntu 22.04 template | OpenClaw sandbox | Stopped |

Due to GPU passthrough I can Only run Testing or Personal or Linux at a time. If I try to run multiple, the start command will return PCI in use error

**Last Updated:** 28-06-2026
**Lab Status:** ✅ Operational (24/7 capable but only on during use due to power-constrains)
