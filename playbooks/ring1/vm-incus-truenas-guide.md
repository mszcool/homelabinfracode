# TrueNAS Scale VM on Incus - Deployment Guide

This playbook creates a TrueNAS Scale virtual machine on an Incus-based virtualization host with full PCIe/SATA controller passthrough support.

## Features

- **Parameterized Configuration**: Customize CPU, memory, storage, and network settings
- **PCIe Passthrough**: Direct access to SATA controllers for storage pools
- **Automated Installation**: Downloads TrueNAS ISO and configures VM
- **Management Tools**: Includes VM management script for easy administration
- **Flexible Network**: Configurable network bridge selection

## Prerequisites

1. **Incus Host Setup**: Ensure your Incus host is properly configured
2. **IOMMU Support**: Enable IOMMU in BIOS/UEFI and kernel for PCIe passthrough
3. **Storage Pool**: Have an Incus storage pool available (default: 'default')
4. **Network Bridge**: Configure network bridge (default: 'incusbr0')

## Files Structure

The TrueNAS VM deployment consists of several files:

### Main Files:
- **`playbooks/ring0/vm-incus-truenas.yaml`** - Main Ansible playbook
- **`configs/truenas-vm-config.yaml.example`** - Configuration examples

### Template Files:
- **`playbooks/ring0/templates/vm-incus-truenas-template.yaml.j2`** - Incus VM YAML template
- **`playbooks/ring0/templates/vm-incus-truenas-manage.sh.j2`** - VM management script template

### Documentation:
- **`playbooks/ring0/vm-incus-truenas-guide.md`** - This guide

## Configuration Parameters

### Required Parameters
- `vm_name`: Name of the TrueNAS VM (default: 'truenas-scale')
- `cpu_cores`: Number of CPU cores (default: 4)
- `memory_gb`: Memory in GB (default: 16)
- `system_disk_gb`: System disk size in GB (default: 128)
- `network_bridge`: Incus network bridge (default: 'incusbr0')

### PCIe Passthrough Parameters
- `enable_pcie_passthrough`: Enable PCIe passthrough (default: true)
- `pcie_controller`: PCIe controller ID (e.g., '0000:00:17.0')

### Optional Parameters
- `iso_url`: TrueNAS Scale ISO download URL
- `iso_path`: Local path for ISO file
- `incus_storage_pool`: Storage pool name
- `security_nesting`: Enable nesting (default: false)
- `security_privileged`: Enable privileged mode (default: false)
- `cleanup_iso`: Remove ISO after installation (default: false)

## Finding Your SATA Controller

To find your SATA controller for PCIe passthrough on each target host:

### First Host (10.10.0.20 - mszpvetest1)
```bash
# Connect to first Incus host
ssh mszcool@10.10.0.20

# List all PCI devices
lspci

# Find SATA controllers specifically
lspci | grep -i sata

# Get detailed information
lspci -v | grep -A 10 -i sata
```

### Second Host (10.10.0.30 - mszpvetest2)
```bash
# Connect to second Incus host
ssh mszcool@10.10.0.30

# List all PCI devices
lspci

# Find SATA controllers specifically
lspci | grep -i sata

# Get detailed information
lspci -v | grep -A 10 -i sata
```

Example output:
```
00:17.0 SATA controller: Intel Corporation Device 43d2 (rev 11)
```

Use `0000:00:17.0` as your `pcie_controller` value.

**Important**: Each host has different PCIe controllers, so you must check each specific host where TrueNAS will be deployed. The controller address may be the same or different between hosts depending on the hardware configuration.

## Host Targeting

**Important**: The TrueNAS Scale VM deployment strategy depends on your use case:

### Single TrueNAS Instance
Deploy to the first host in the Incus inventory for centralized storage management.

### Multiple TrueNAS Instances
Deploy each instance to a different Incus host for:
1. **High Availability**: Storage services remain available if one host fails
2. **Resource Distribution**: Spread CPU, memory, and I/O load across hosts
3. **Independent Storage Controllers**: Each host provides its own PCIe/SATA controllers
4. **Backup/Replication**: Primary and secondary TrueNAS instances can replicate data

### Your Incus Inventory

Based on your current inventory (`configs/host-incus-cluster.yaml`):
- **First Host**: `10.10.0.20` (mszpvetest1) - **Primary TrueNAS**
- **Second Host**: `10.10.0.30` (mszpvetest2) - **Secondary TrueNAS**

### Host Selection Methods

```bash
# Target first host (primary TrueNAS)
--limit incus[0]        # or --limit 10.10.0.20 or --limit mszpvetest1

# Target second host (secondary TrueNAS)
--limit incus[1]        # or --limit 10.10.0.30 or --limit mszpvetest2

# Target specific host by IP
--limit 10.10.0.20      # First host
--limit 10.10.0.30      # Second host
```

## Usage Examples

### Basic TrueNAS VM

```bash
# Create configuration file
cp configs/truenas-vm-config.yaml.example configs/truenas-vm-config.yaml

# Edit configuration
nano configs/truenas-vm-config.yaml

# Run the playbook (deploys to first Incus host)
ansible-playbook -i configs/truenas-vm-config.yaml playbooks/ring0/vm-incus-truenas.yaml --limit incus[0]
```

### High-Performance Configuration

```bash
# Deploy to first Incus host (10.10.0.20 in the example inventory)
ansible-playbook -i configs/host-incus-cluster.yaml playbooks/ring0/vm-incus-truenas.yaml \
  --limit incus[0] \
  -e vm_name=truenas-hp \
  -e cpu_cores=8 \
  -e memory_gb=32 \
  -e system_disk_gb=256 \
  -e pcie_controller=0000:00:17.0
```

### Development/Testing Configuration

```bash
# Deploy to first Incus host only
ansible-playbook -i configs/host-incus-cluster.yaml playbooks/ring0/vm-incus-truenas.yaml \
  --limit incus[0] \
  -e vm_name=truenas-dev \
  -e cpu_cores=2 \
  -e memory_gb=8 \
  -e system_disk_gb=64 \
  -e enable_pcie_passthrough=false
```

### Multiple TrueNAS Instances (Distributed)

```bash
# Primary TrueNAS on first host (10.10.0.20)
ansible-playbook -i configs/host-incus-cluster.yaml playbooks/ring0/vm-incus-truenas.yaml \
  --limit incus[0] \
  -e vm_name=truenas-primary \
  -e cpu_cores=6 \
  -e memory_gb=24 \
  -e pcie_controller=0000:00:17.0

# Secondary TrueNAS on second host (10.10.0.30)
ansible-playbook -i configs/host-incus-cluster.yaml playbooks/ring0/vm-incus-truenas.yaml \
  --limit incus[1] \
  -e vm_name=truenas-secondary \
  -e cpu_cores=4 \
  -e memory_gb=16 \
  -e pcie_controller=0000:00:17.0
```

### High Availability Setup

```bash
# Production TrueNAS on first host
ansible-playbook -i configs/host-incus-cluster.yaml playbooks/ring0/vm-incus-truenas.yaml \
  --limit 10.10.0.20 \
  -e vm_name=truenas-production \
  -e cpu_cores=8 \
  -e memory_gb=32 \
  -e system_disk_gb=256 \
  -e pcie_controller=0000:00:17.0

# Backup TrueNAS on second host
ansible-playbook -i configs/host-incus-cluster.yaml playbooks/ring0/vm-incus-truenas.yaml \
  --limit 10.10.0.30 \
  -e vm_name=truenas-backup \
  -e cpu_cores=4 \
  -e memory_gb=16 \
  -e system_disk_gb=128 \
  -e pcie_controller=0000:00:17.0
```

### Targeting Specific Host

```bash
# Deploy to a specific host by IP
ansible-playbook -i configs/host-incus-cluster.yaml playbooks/ring0/vm-incus-truenas.yaml \
  --limit 10.10.0.20 \
  -e vm_name=truenas-scale \
  -e cpu_cores=4 \
  -e memory_gb=16 \
  -e pcie_controller=0000:00:17.0
```

## Post-Installation

### 1. TrueNAS Installation

1. Connect to VM console:
   ```bash
   incus console truenas-scale
   ```

2. Follow TrueNAS Scale installation wizard
3. Install to the virtual system disk (128GB)
4. Configure initial network settings

### 2. Remove Installation ISO

After successful installation:
```bash
incus config device remove truenas-scale install-media
```

### 3. Access TrueNAS Web Interface

1. Find VM IP address:
   ```bash
   incus info truenas-scale | grep -E "eth0.*inet"
   ```

2. Access web interface at: `http://[VM_IP]`

## VM Management

The playbook creates a management script at `/usr/local/bin/manage-[vm_name].sh`:

```bash
# Show help
/usr/local/bin/manage-truenas-scale.sh help

# Start/stop VM
/usr/local/bin/manage-truenas-scale.sh start
/usr/local/bin/manage-truenas-scale.sh stop

# Check status and IP
/usr/local/bin/manage-truenas-scale.sh status
/usr/local/bin/manage-truenas-scale.sh ip

# Access console
/usr/local/bin/manage-truenas-scale.sh console

# Create backup
/usr/local/bin/manage-truenas-scale.sh backup
```

## Troubleshooting

### Host Targeting Issues

1. **Wrong Host Selected**:
   ```bash
   # Verify which host is targeted
   ansible-inventory -i configs/host-incus-cluster.yaml --list
   
   # Check first host in incus group
   ansible-inventory -i configs/host-incus-cluster.yaml --host incus[0]
   
   # Check second host in incus group
   ansible-inventory -i configs/host-incus-cluster.yaml --host incus[1]
   ```

2. **Host Not Accessible**:
   ```bash
   # Test connectivity to first Incus host
   ansible -i configs/host-incus-cluster.yaml incus[0] -m ping
   
   # Test connectivity to second Incus host
   ansible -i configs/host-incus-cluster.yaml incus[1] -m ping
   
   # Test specific hosts
   ansible -i configs/host-incus-cluster.yaml 10.10.0.20 -m ping
   ansible -i configs/host-incus-cluster.yaml 10.10.0.30 -m ping
   ```

3. **Multiple Host Deployment**:
   ```bash
   # Deploy to both hosts in sequence
   ansible-playbook -i configs/host-incus-cluster.yaml playbooks/ring0/vm-incus-truenas.yaml \
     --limit incus[0] -e vm_name=truenas-primary
   
   ansible-playbook -i configs/host-incus-cluster.yaml playbooks/ring0/vm-incus-truenas.yaml \
     --limit incus[1] -e vm_name=truenas-secondary
   ```

### PCIe Passthrough Issues

1. **IOMMU Not Enabled**:
   ```bash
   # Check IOMMU support
   dmesg | grep -i iommu
   
   # Enable in GRUB (Intel)
   echo 'GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on"' >> /etc/default/grub
   
   # Enable in GRUB (AMD)
   echo 'GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=on"' >> /etc/default/grub
   
   # Update GRUB and reboot
   update-grub
   reboot
   ```

2. **Controller Already in Use**:
   ```bash
   # Check which driver is using the controller
   lspci -k -s 00:17.0
   
   # Unbind from current driver
   echo "0000:00:17.0" > /sys/bus/pci/drivers/ahci/unbind
   ```

### VM Won't Start

1. **Check VM logs**:
   ```bash
   incus info truenas-scale --show-log
   ```

2. **Verify configuration**:
   ```bash
   incus config show truenas-scale
   ```

3. **Check storage pool**:
   ```bash
   incus storage list
   ```

### Network Issues

1. **Check network bridge**:
   ```bash
   incus network list
   ```

2. **Verify VM network config**:
   ```bash
   incus config device show truenas-scale
   ```

## Security Considerations

- **Privileged Mode**: Only enable if required for specific hardware access
- **Nesting**: Only enable if running containers inside the VM
- **Network Isolation**: Consider using separate network bridges for different purposes
- **Access Control**: Implement proper firewall rules for TrueNAS access

## Storage Best Practices

### Single TrueNAS Instance
1. **System Disk**: Use the virtual system disk only for TrueNAS OS
2. **Data Storage**: Use passed-through SATA controller for data pools
3. **Backups**: Regular VM backups for disaster recovery
4. **Monitoring**: Monitor storage pool health and performance

### Multiple TrueNAS Instances (Distributed)
1. **Primary/Secondary Setup**: 
   - Primary on first host (10.10.0.20) for main storage
   - Secondary on second host (10.10.0.30) for backups/replication
2. **Resource Allocation**:
   - Primary: Higher CPU/Memory (8 cores, 32GB)
   - Secondary: Standard resources (4 cores, 16GB)
3. **Network Configuration**:
   - Both instances on same network bridge for replication
   - Consider separate management networks
4. **Replication Strategy**:
   - Configure TrueNAS replication between instances
   - Set up periodic snapshots and transfers
5. **Failover Planning**:
   - Document procedures for switching between instances
   - Test failover scenarios regularly

### High Availability Benefits
- **Fault Tolerance**: Service continues if one host fails
- **Load Distribution**: Spread I/O across multiple hosts
- **Maintenance Windows**: Update one host while other remains active
- **Geographic Distribution**: Potential for site-to-site replication

## Integration with Existing Infrastructure

This playbook integrates with your existing Incus cluster configuration:

- Uses existing `root_user` and authentication settings
- Leverages configured storage pools
- Utilizes established network bridges
- Follows existing naming conventions

## Advanced Configuration

### Custom QEMU Arguments

For advanced QEMU configuration, modify the VM template or playbook to include:
```yaml
# In vm-incus-truenas-template.yaml.j2
config:
  raw.qemu: "-cpu host,kvm=on"
```

### Multiple Network Interfaces

Add multiple network interfaces by modifying the template:
```yaml
# In vm-incus-truenas-template.yaml.j2
devices:
  eth1:
    type: nic
    network: management-bridge
    name: eth1
```

### USB Passthrough

For USB device passthrough, add to the template:
```yaml
# In vm-incus-truenas-template.yaml.j2
devices:
  usb-device:
    type: usb
    vendorid: "1234"
    productid: "5678"
```

## Monitoring and Maintenance

1. **VM Health Monitoring**:
   ```bash
   # Check VM resource usage
   incus info truenas-scale
   
   # Monitor VM performance
   incus monitor truenas-scale
   ```

2. **Regular Backups**:
   ```bash
   # Create scheduled backups
   /usr/local/bin/manage-truenas-scale.sh backup
   ```

3. **Updates**:
   - Keep TrueNAS Scale updated through its web interface
   - Monitor Incus host for updates
   - Update VM configuration as needed

## License

This playbook is part of the homelab infrastructure code and follows the same licensing terms as the parent project.
