# VM Lab Infrastructure - Complete Setup Summary

## 🎯 Project Overview

This Terraform-based automation creates a complete virtual machine lab infrastructure with:

- **4 Virtual Machines** with centralized configuration
- **2 Network Switches** (WAN and LAN)
- **Dual Provider Support** (Incus and Hyper-V)
- **Automated Management Scripts**

## 📋 VM Specifications

| VM Name | CPU | RAM | Disk(s) | Networks |
|---------|-----|-----|---------|----------|
| RouterOS | 2 cores | 512 MB | 64 GB | lab-wan, lab-lan |
| Incus-SingleDisk | 2 cores | 2 GB | 128 GB | lab-lan |
| Incus-DualDisk | 2 cores | 2 GB | 2x 128 GB | lab-lan |
| Test-Client | 2 cores | 2 GB | 128 GB | lab-lan |

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Physical Host                             │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────┐                                             │
│ │  lab-wan    │◄─── Internet Connection                     │
│ │  (External) │                                             │
│ └─────┬───────┘                                             │
│       │                                                     │
│ ┌─────▼───────┐    ┌─────────────────────────────────────┐  │
│ │   RouterOS  │    │            lab-lan                  │  │
│ │             │◄───┤         (Internal)                  │  │
│ └─────────────┘    │                                     │  │
│                    │  ┌─────────────┐ ┌─────────────┐    │  │
│                    │  │Incus-Single │ │Incus-Dual   │    │  │
│                    │  │Disk         │ │Disk         │    │  │
│                    │  └─────────────┘ └─────────────┘    │  │
│                    │                                     │  │
│                    │  ┌─────────────┐                    │  │
│                    │  │Test-Client  │                    │  │
│                    │  │             │                    │  │
│                    │  └─────────────┘                    │  │
│                    └─────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 📁 Directory Structure

```
virtualmachines/terraform/
├── 📖 README.md                  # Main documentation
├── 📖 DEPLOYMENT-GUIDE.md        # Detailed deployment guide
├── 📖 INSTALL-TERRAFORM.md       # Terraform installation guide
├── 📖 SUMMARY.md                 # This file
├── 🔧 manage-incus.sh            # Incus management script
├── 🔧 Manage-HyperV.ps1          # Hyper-V management script (PowerShell)
├── 🔧 manage-hyperv.bat          # Legacy Hyper-V script (deprecated)
├── 🔍 validate-config.sh         # Configuration validator
├── 📁 shared/
│   └── variables.tf              # Centralized VM definitions
├── 📁 incus/                     # Incus provider configuration
│   ├── providers.tf              # Provider and variables
│   ├── variables.tf              # Incus-specific variables
│   ├── networks.tf               # Network configuration
│   ├── virtual-machines.tf       # VM definitions
│   ├── outputs.tf                # Output values
│   └── terraform.tfvars.example  # Example configuration
└── 📁 hyperv/                    # Hyper-V provider configuration
    ├── providers.tf              # Provider and variables
    ├── variables.tf              # Hyper-V-specific variables
    ├── networks.tf               # Switch configuration
    ├── virtual-machines.tf       # VM definitions
    ├── outputs.tf                # Output values
    └── terraform.tfvars.example  # Example configuration
```

## 🚀 Quick Start

### 1. Install Prerequisites
```bash
# Install Terraform (see INSTALL-TERRAFORM.md for details)
sudo apt update && sudo apt install terraform

# For Incus (Linux)
sudo snap install incus --classic

# For Hyper-V (Windows)
# Enable Hyper-V feature in Windows
```

### 2. Validate Configuration
```bash
cd virtualmachines/terraform
./validate-config.sh
```

### 3. Deploy Infrastructure

#### Option A: Incus (Linux)
```bash
./manage-incus.sh init
./manage-incus.sh plan
./manage-incus.sh apply
```

#### Option B: Hyper-V (Windows)
```powershell
.\Manage-HyperV.ps1 -Action init
.\Manage-HyperV.ps1 -Action plan
.\Manage-HyperV.ps1 -Action apply
```

## 🔧 Management Commands

### Incus Management
```bash
./manage-incus.sh init      # Initialize Terraform
./manage-incus.sh plan      # Show planned changes
./manage-incus.sh apply     # Apply changes
./manage-incus.sh destroy   # Destroy all resources
./manage-incus.sh status    # Show current state
./manage-incus.sh clean     # Clean Terraform cache
```

### Hyper-V Management
```powershell
.\Manage-HyperV.ps1 -Action init      # Initialize Terraform
.\Manage-HyperV.ps1 -Action plan      # Show planned changes
.\Manage-HyperV.ps1 -Action apply     # Apply changes
.\Manage-HyperV.ps1 -Action destroy   # Destroy all resources
.\Manage-HyperV.ps1 -Action status    # Show current state
.\Manage-HyperV.ps1 -Action clean     # Clean Terraform cache
```

## 🎛️ Customization

### Modifying VM Specifications
Edit the `vm_configurations` variable in `providers.tf`:

```hcl
"routeros" = {
  name          = "RouterOS"
  cpu_cores     = 4          # Increase from 2
  memory_mb     = 1024       # Increase from 512
  disks = [{
    name     = "main"
    size_gb  = 128           # Increase from 64
  }]
  network_adapters = ["lab-wan", "lab-lan"]
}
```

### Network Configuration
- **lab-wan**: External network with internet access
- **lab-lan**: Internal network (192.168.100.0/24)

### Storage Paths
- **Incus**: Uses default storage pool
- **Hyper-V**: Uses `C:\VMs\` (configurable via `vm_base_path`)

## 🛠️ Troubleshooting

### Common Issues
1. **Terraform not found**: Install Terraform (see INSTALL-TERRAFORM.md)
2. **Permission denied**: Run as Administrator (Windows) or check user groups (Linux)
3. **Provider not found**: Run `terraform init` first
4. **Resource conflicts**: Check existing VMs/networks

### Log Files
- **Incus**: `journalctl -u incus`
- **Hyper-V**: Windows Event Viewer
- **Terraform**: `terraform.log` (set TF_LOG=DEBUG)

## 🔄 Backup and Recovery

### Create Snapshots
```bash
# Incus
incus snapshot RouterOS backup-$(date +%Y%m%d)

# Hyper-V
Checkpoint-VM -Name RouterOS -SnapshotName "backup-$(Get-Date -Format 'yyyyMMdd')"
```

### Disaster Recovery
1. Export Terraform state: `terraform show > infrastructure.txt`
2. Backup VM disks
3. Document network configuration
4. Keep copy of Terraform files

## 📊 Resource Requirements

### Minimum System Requirements
- **CPU**: 8 cores (4 for VMs + 4 for host)
- **RAM**: 8 GB (4.5 GB for VMs + 3.5 GB for host)
- **Storage**: 500 GB free space
- **Network**: Internet connection for lab-wan

### Recommended System Requirements
- **CPU**: 12+ cores
- **RAM**: 16+ GB
- **Storage**: 1 TB+ SSD
- **Network**: Dedicated NICs for lab networks

## 🔐 Security Considerations

1. **Network Isolation**: lab-lan is isolated from external networks
2. **Firewall Rules**: Configure RouterOS firewall appropriately
3. **Access Control**: Use strong passwords and SSH keys
4. **Updates**: Keep host and guest systems updated
5. **Monitoring**: Monitor resource usage and access logs

## 🎯 Use Cases

This infrastructure is perfect for:
- **Network Engineering**: RouterOS configuration and testing
- **System Administration**: Multi-server setups
- **Development**: Isolated development environments
- **Learning**: Hands-on practice with virtualization
- **Testing**: Software deployment and testing

## 📚 Additional Resources

- [Terraform Documentation](https://terraform.io/docs)
- [Incus Documentation](https://incus.readthedocs.io/)
- [Hyper-V Documentation](https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/)
- [RouterOS Documentation](https://wiki.mikrotik.com/wiki/Manual:TOC)

## 🤝 Contributing

To modify or extend this infrastructure:
1. Update the centralized `vm_configurations` in both providers
2. Test changes with `./validate-config.sh`
3. Apply changes incrementally
4. Document any new features or requirements

---

**Status**: ✅ Complete and Ready for Deployment

**Last Updated**: June 7, 2025

**Next Steps**: Choose your provider and start deploying!
