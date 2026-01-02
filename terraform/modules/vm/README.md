# VM Module for Incus

This module manages the creation and configuration of virtual machines on Incus.

## Features

- VM instance creation with configurable resources
- Base image specification (e.g., `images:ubuntu/24.04`)
- ISO handling (upload and attachment)
- Data disk creation and attachment
- Network device configuration
- PCIe controller passthrough support
- Automatic state management

## Important Notes

### Pre-existing Resources

The following resources must already exist in the Incus infrastructure:

- **Projects**: The `incus_project` variable must reference an existing project
- **Profiles**: The `incus_profile` variable must reference an existing profile
- **Storage Pools**: The `storage_pool` variable must reference an existing storage pool
- **Networks**: Network bridges referenced in device configuration must exist

These are typically created via preseed files during initial host provisioning.

### ISO Handling

ISOs are handled in two ways:

1. **Local ISO Path**: If `iso_source_local` is provided, the ISO is:
   - Copied to the target Incus host's `/tmp` directory
   - Imported into a storage volume named `{vm_name}-install-iso`
   - Mounted as a read-only device in the VM
   - **Note:** Leave `image` empty when using ISO

2. **Pre-existing ISO**: If `iso_path` points to an existing file on the target host, it's used directly
   - **Note:** Leave `image` empty when using ISO

### Important: Image vs ISO

You must specify **either** `image` **or** ISO parameters, but **not both**:

- **For standard OS VMs** (Ubuntu, Debian, Alpine, etc.):
  - Set `image` to the image server URL (e.g., `"images:ubuntu/24.04"`)
  - Leave `iso_source_local` and `iso_path` empty

- **For ISO-based VMs** (TrueNAS, custom installers, etc.):
  - Leave `image` empty (`""`)
  - Set either `iso_source_local` or `iso_path`

Terraform will validate and prevent misconfiguration.

### Data Disk Management

Data disks are created as separate storage volumes and attached to the VM:

- Each disk is created in the specified storage pool
- Disks are formatted as block devices for the VM
- Useful for TrueNAS and other storage-intensive workloads

### PCIe Passthrough

When `enable_pcie_passthrough` is true:

- The PCIe controller is passed through to the VM
- This allows direct access to RAID controllers, network cards, etc.
- Data disks are disabled when PCIe passthrough is enabled
- Requires hardware support and appropriate kernel configuration

## Usage

```hcl
module "truenas" {
  source = "./modules/vm"

  instance_name            = "truenas-primary"
  incus_project            = "prodlayer0"
  incus_profile            = "production"
  storage_pool             = "incus-instances"
  cpu_cores                = 4
  memory_gb                = 16
  system_disk_gb           = 128
  network_bridge           = "phys-br"
  mac_address              = "00:16:3e:11:00:01"
  iso_source_local         = "/home/mszcool/iso/truenas-25.04.2.5.iso"
  iso_path                 = "/srv/iso/truenas-25.04.2.5.iso"
  enable_pcie_passthrough  = true
  pcie_controller          = "0000:07:00.1"
  target_remote            = "aoostar"
}
```

## Outputs

- `instance_id`: The unique identifier of the created instance
- `instance_ipv4_address`: The IPv4 address of the instance (when available)
- `instance_status`: The current status of the instance
