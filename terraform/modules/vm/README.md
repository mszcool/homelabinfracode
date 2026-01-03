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

### Cloud-Init and User Configuration

This module supports automated user creation and SSH key configuration for image-based VMs:

### Cloud-Init and User Configuration

This module supports automated user creation and SSH key configuration for image-based VMs:

**Requirements:**
- Must use `/cloud` variant images (e.g., `images:ubuntu/24.04/cloud`) that have cloud-init pre-installed
- `root_password` must be pre-hashed in yescrypt format (`$y$...`), not plaintext
- Ubuntu 24.04 uses yescrypt by default (see `/etc/pam.d/common-password`)
- Only works with image-based VMs (not ISO-based)

**Features:**
- Custom privileged user creation (configurable username via `root_username`)
- SSH public key setup for passwordless access
- Password-based authentication using cloud-init's `chpasswd` module (handles yescrypt hashes)
- Full sudo access for the created user

**Important:** Cloud-init detects the password hash format and applies it correctly. Yescrypt hashes (starting with `$y$`) are supported and recommended for Ubuntu 24.04.

**Generating the Hashed Password:**

Before running Terraform, generate a yescrypt hashed password using one of these methods:

**Option 1: Using `mkpasswd` with yescrypt (Ubuntu/Debian) - Recommended**
```bash
mkpasswd -m yescrypt
# This will prompt you to enter your password twice
# Copy the resulting hash (starts with $y$)
```

**Option 2: Using Python `passlib`**
```bash
python3 << 'EOF'
from passlib.hash import yescrypt
import getpass
pwd = getpass.getpass("Enter password: ")
print(yescrypt.hash(pwd))
EOF
```

**Note on SHA-512:** Ubuntu 24.04 uses yescrypt by default (see `/etc/pam.d/common-password`). SHA-512 hashes ($6$) won't work for authentication even though they're valid crypt hashes. Always use yescrypt ($y$) for this image.

**Usage with Terraform:**

⚠️ **Important:** Make sure `root_password = ""` (empty) in your `.tfvars` file so the environment variable takes precedence.

```bash
# Generate the yescrypt hash first
HASH=$(mkpasswd -m yescrypt)
# Enter your password when prompted, copy the resulting hash (should start with $y$)

# Export as environment variable
export TF_VAR_root_password="$HASH"

# Run Terraform
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
terraform apply --var-file="../configs.private/ring0/ring0.tfvars"
```

**Example Configuration:**
```hcl
module "samba4" {
  source = "./modules/vm"

  instance_name      = "samba4-addc"
  image              = "images:ubuntu/24.04/cloud"  # Must use /cloud variant
  root_username      = "sysadmin"
  ssh_public_key     = file("~/.ssh/id_ed25519.pub")
  root_password      = var.sysadmin_password_hashed  # Must be pre-hashed

  # ... other configuration
}
```

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
