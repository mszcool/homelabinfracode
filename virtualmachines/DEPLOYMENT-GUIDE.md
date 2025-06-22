# VM Lab Deployment Guide

This guide walks you through deploying your VM lab infrastructure using Terraform with either Incus or Hyper-V.

## Prerequisites

### For Incus Deployment (Linux)
- Linux system with Incus installed
- Terraform installed (version 1.0+)
- Sufficient storage space (>500GB recommended)
- Network connectivity

### For Hyper-V Deployment (Windows)
- Windows 10/11 Pro or Windows Server with Hyper-V enabled
- Administrator privileges
- Terraform installed (version 1.0+)
- Sufficient storage space (>500GB recommended)
- PowerShell execution policy set appropriately

## Quick Start

### Incus Deployment

1. **Check Prerequisites**
   ```bash
   # Verify Incus is working
   incus info
   
   # Verify Terraform is installed
   terraform version
   ```

2. **Initialize and Deploy**
   ```bash
   cd virtualmachines/terraform
   ./manage-incus.sh init
   ./manage-incus.sh plan
   ./manage-incus.sh apply
   ```

3. **Check Status**
   ```bash
   ./manage-incus.sh status
   ```

### Hyper-V Deployment

1. **Check Prerequisites** (Run as Administrator)
   ```powershell
   # Verify Hyper-V is enabled
   Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
   
   # Verify Terraform is installed
   terraform version
   ```

2. **Initialize and Deploy**
   ```powershell
   cd virtualmachines\infralab-terraform
   .\Manage-HyperV.ps1 -Action init
   .\Manage-HyperV.ps1 -Action plan
   .\Manage-HyperV.ps1 -Action apply
   ```

3. **Check Status**
   ```powershell
   .\Manage-HyperV.ps1 -Action status
   ```

## Detailed Configuration

### Customizing VM Specifications

Edit the `vm_configurations` variable in the respective `providers.tf` file:

```hcl
variable "vm_configurations" {
  default = {
    "routeros" = {
      name          = "RouterOS"
      cpu_cores     = 4          # Increase from 2 to 4
      memory_mb     = 1024       # Increase from 512 to 1024
      disks = [{
        name     = "main"
        size_gb  = 128           # Increase from 64 to 128
      }]
      network_adapters = ["lab-wan", "lab-lan"]
    }
    # ... other VMs
  }
}
```

### Network Configuration

#### Incus Networks
- **lab-wan**: Bridged network with NAT for internet access
- **lab-lan**: Internal network (192.168.100.0/24) for VM communication

#### Hyper-V Networks
- **lab-wan**: External virtual switch connected to physical network
- **lab-lan**: Internal virtual switch for VM-only communication

### Storage Configuration

#### Incus
- Uses default storage pool
- Dynamic disk allocation
- Storage path: `/var/lib/incus/storage-pools/default/`

#### Hyper-V
- Uses `C:\VMs\` directory by default (configurable)
- Dynamic VHDX files
- Separate directory per VM

## Post-Deployment Steps

### 1. Access VMs

#### Incus
```bash
# List running instances
incus list

# Connect to a VM console
incus console RouterOS

# Execute commands in VM
incus exec RouterOS -- /bin/bash
```

#### Hyper-V
```powershell
# List VMs
Get-VM

# Connect to VM
vmconnect localhost RouterOS

# Start/Stop VMs
Start-VM RouterOS
Stop-VM RouterOS
```

### 2. Network Configuration

#### RouterOS Setup
1. Connect to RouterOS via console
2. Configure WAN interface (connected to lab-wan)
3. Configure LAN interface (connected to lab-lan)
4. Set up DHCP server for lab-lan network
5. Configure firewall rules

#### Other VMs
1. Configure network interfaces to use DHCP or static IPs
2. Set RouterOS VM as default gateway (192.168.100.1 recommended)
3. Configure DNS servers

### 3. Install Operating Systems

The VMs are created with hardware only. You'll need to:

1. **RouterOS**: Boot from RouterOS ISO/image
2. **Other VMs**: Install your preferred Linux distribution

## Monitoring and Management

### Resource Usage
```bash
# Incus resource usage
incus info --resources

# Hyper-V resource usage
Get-Counter "\Hyper-V Hypervisor\Virtual Processors"
```

### Backup and Snapshots

#### Incus
```bash
# Create snapshot
incus snapshot RouterOS backup-$(date +%Y%m%d)

# List snapshots
incus info RouterOS

# Restore snapshot
incus restore RouterOS backup-20250607
```

#### Hyper-V
```powershell
# Create checkpoint
Checkpoint-VM -Name RouterOS -SnapshotName "Backup-$(Get-Date -Format 'yyyyMMdd')"

# List checkpoints
Get-VMSnapshot -VMName RouterOS

# Restore checkpoint
Restore-VMSnapshot -Name "Backup-20250607" -VMName RouterOS
```

## Troubleshooting

### Common Issues

1. **Insufficient Resources**
   - Reduce VM specifications
   - Check available RAM and storage

2. **Network Connectivity Issues**
   - Verify physical network adapter for Hyper-V external switch
   - Check Incus network configuration

3. **Permission Issues**
   - Run as Administrator on Windows
   - Check user group membership for Incus

### Logs and Diagnostics

#### Incus
```bash
# View Incus logs
journalctl -u incus

# VM-specific logs
incus info RouterOS --show-log
```

#### Hyper-V
```powershell
# Event logs
Get-WinEvent -LogName "Microsoft-Windows-Hyper-V-*"

# VM events
Get-VMIntegrationService -VMName RouterOS
```

## Cleanup

### Complete Removal

#### Incus
```bash
./manage-incus.sh destroy
./manage-incus.sh clean
```

#### Hyper-V
```powershell
.\Manage-HyperV.ps1 -Action destroy
.\Manage-HyperV.ps1 -Action clean
```

### Selective Removal
```bash
# Remove specific VM (Incus)
terraform destroy -target=incus_instance.routeros

# Remove specific VM (Hyper-V)
terraform destroy -target=hyperv_machine_instance.routeros
```

## Security Considerations

1. **Network Isolation**: lab-lan is isolated from external networks
2. **Access Control**: Configure appropriate user access to VMs
3. **Firewall Rules**: Implement proper firewall rules on RouterOS
4. **Updates**: Keep host systems and VMs updated
5. **Monitoring**: Monitor resource usage and VM activity

## Performance Optimization

1. **CPU Allocation**: Don't over-commit CPU cores
2. **Memory Management**: Monitor memory usage and adjust as needed
3. **Storage**: Use SSDs for better I/O performance
4. **Network**: Consider separate physical NICs for better network performance

This completes your VM lab setup. The infrastructure provides a solid foundation for networking experiments, testing, and development work.
