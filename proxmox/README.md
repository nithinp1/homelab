# Proxmox VE Configuration

Proxmox VE 9.1.6 hypervisor running on MSI GF65 Thin 10UE with advanced GPU passthrough.

## Quick Reference

- **Host:** MSI GF65 Thin 10UE
- **Proxmox Version:** 9.1.6
- **IOMMU:** Enabled
- **VMs Count:** 3

## VMs

### Testing Windows VM (GPU Passthrough)

- **Specs:** vCPU: 10 , RAM: 12GB, GPU is enabled
- **Status:** Stopped
- **GPU:** NVIDIA RTX 3060 Max-Q Laptop GPU
- **Purpose:** Software testing with Parsec streaming

### Personal Windows VM (GPU Passthrough)

- **Specs:** vCPU: 10 , RAM: 12GB, GPU is enabled
- **Status:** Stopped
- **GPU:** NVIDIA RTX 3060 Max-Q Laptop GPU
- **Purpose:** Video editing with Parsec streaming

### Ubuntu Dev VM

- **Specs:** vCPU: 10 , RAM: 12GB, GPU is enabled
- **Status:** Stopped
- **GPU:** NVIDIA RTX 3060 Max-Q Laptop GPU
- **Purpose:** Ollama server, n8n uses this to as fallback if main AI API fails
## GPU Passthrough Setup

See: [GPU Passthrough README](./gpu-passthrough/README.md)
