# Terraform — README

> **Context**: For the master architecture overview, see [Architecture](../02-architecture.md). For the Terraform documentation index, see [INDEX.md](./INDEX.md). For Ring 0 setup including Terraform provisioning, see [Ring 0 Setup](../04-ring0-setup.md).
>
> **Path conventions**: Tfvars at `configs/envtest/` (test) or `configs.private/envprod/` (production). Secrets via 1Password provider. See [Architecture](../02-architecture.md).

This directory contains modular Terraform configurations for managing Incus VMs and containers on the homelab infrastructure.

## Architecture Overview

The Terraform configuration is organized into modular components:

```
terraform/
├── versions.tf          # Terraform and provider version constraints
├── providers.tf         # Incus provider configuration
├── variables.tf         # Global variables
├── locals.tf            # Local computed values
├── main.tf              # Root module
├── outputs.tf           # Output definitions
├── modules/
│   ├── vm/              # Virtual machine module
│   └── container/       # Container module (future)
configs/envtest/
├── ring0.tfvars         # Ring0 test environment variables
├── ring1.tfvars         # Ring1 test environment variables
└── ring2.tfvars         # Ring2 test environment variables
configs.private/envprod/
├── ring0.tfvars         # Ring0 production variables (private)
├── ring1.tfvars         # Ring1 production variables (private)
└── ring2.tfvars         # Ring2 production variables (private)
docs/terraform/
└── TERRAFORM-README.md  # This file
```

## Important Design Constraints

### Resources NOT Managed by Terraform

The following resources are pre-provisioned via the Incus preseed configuration and should **NOT** be managed by Terraform:

- **Networks** (e.g., `phys-br`, `iso-nat`)
- **Storage Pools** (e.g., `incus-images`, `incus-instances`)
- **Projects** (e.g., `default`, `prodlayer0`, `prodlayer1`)
- **Profiles** (e.g., `default`, `defaultlan`, `production`)

These are defined in the preseed files (e.g., `incus.preseed.*.yaml`) and are managed as part of the initial host provisioning.

### Resources Managed by Terraform

- **Storage Volumes**: Custom volumes for ISOs, data disks, and other storage needs
- **Instances**: VMs and containers
- **Instance Devices**: Disk attachments, NIC configurations, PCI devices
- **Advanced Features**: ISO volumes, data disk management, PCIe passthrough

## Module Structure

### VM Module (`modules/vm/`)

The VM module encapsulates all logic for creating and managing virtual machines.

**Key Features:**
- Support for custom ISO handling
- Data disk creation and attachment
- Network device configuration
- PCIe controller passthrough
- Multiple host target support

**Variables:**
- `instance_name`: Name of the VM
- `incus_project`: Target Incus project
- `incus_profile`: Profile to apply
- `storage_pool`: Storage pool for root disk
- `cpu_cores`: Number of CPU cores
- `memory_gb`: Memory allocation in GB
- `system_disk_gb`: Root disk size in GB
- `network_bridge`: Network bridge to connect to
- `mac_address`: MAC address (optional)
- `iso_path`: Path to ISO file on target host
- `iso_source_local`: Local path to ISO file
- `enable_pcie_passthrough`: Enable PCIe passthrough
- `pcie_controller`: PCIe controller PCI address
- `data_disks`: List of data disk configurations

**Example Usage:**

```hcl
module "ubuntu_test" {
  source = "./modules/vm"
  
  instance_name      = "test-ubuntu-single"
  incus_project      = "default"
  incus_profile      = "default"
  storage_pool       = "incus-instances"
  cpu_cores          = 2
  memory_gb          = 4
  system_disk_gb     = 30
  network_bridge     = "br0"
  image              = "images:ubuntu/24.04"
  enable_pcie_passthrough = false
}
```

## Provider Configuration

The Incus provider can be configured in multiple ways:

### Option 1: Using Incus Client Configuration (Recommended)

If Incus is installed locally and remotes are pre-configured:

```hcl
terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
  }
}

provider "incus" {
  # Uses pre-configured remotes from ~/.config/incus
}
```

### Option 2: Using Environment Variables

```bash
export INCUS_REMOTE=production
export INCUS_ADDR=https://incus.example.com:8443
export INCUS_PROTOCOL=incus
export INCUS_TOKEN=<trust-token>
```

### Option 3: Defining Remotes in Terraform

```hcl
provider "incus" {
  generate_client_certificates = true
  accept_remote_certificate    = true
  default_remote               = "primary"

  remote {
    name    = "primary"
    address = "https://incus.incussingledisk.yourlab.localtest:8443"
    token   = var.incus_token
  }
}
```

## Usage

### Initialize Terraform

```bash
cd terraform
terraform init
```

### Plan Ring0 Deployment

```bash
# Using configuration from configs.private/envprod/ring0.tfvars
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
```

### Apply Ring0 Deployment

```bash
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
```

### Destroy Resources

```bash
terraform destroy -var-file="../configs.private/envprod/ring0.tfvars"
```

## Variable Files and Organization

Terraform variable files are organized for security and version control:

### Sample Configurations (Public Repository)
Located in `configs/envtest/` (public repo):
```
configs/envtest/
├── ring0.tfvars              # Sample/example values
├── ring1.tfvars              # Sample/example values
└── ring2.tfvars              # Sample/example values
```

**Purpose:** Reference examples showing structure and commented values. Use as templates.

### Actual Configurations (Private Repository)
Located in `configs.private/envprod/` (private repo):
```
configs.private/envprod/
├── ring0.tfvars              # YOUR actual configuration
├── ring1.tfvars              # YOUR actual configuration
└── ring2.tfvars              # YOUR actual configuration
```

**Purpose:** Your actual infrastructure definitions. Contains sensitive data (IPs, MAC addresses, paths). Never commit to public repos.

### Usage

When running Terraform, always reference the private configuration:

```bash
# From terraform/ directory, referencing configs.private/envprod/
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"

# Or for other environments
terraform apply -var-file="../configs.private/envprod/ring1.tfvars"
terraform apply -var-file="../configs.private/envprod/ring2.tfvars"
```

## Migration from Ansible

### Key Differences

| Aspect | Ansible | Terraform |
|--------|---------|-----------|
| **Scope** | Playbooks executed on hosts | Infrastructure state declared |
| **State** | Not tracked | Tracked in terraform.tfstate |
| **Idempotency** | Task-based | Resource-based |
| **Drift Detection** | Manual playbook re-run | `terraform plan` |
| **Reusability** | Roles and plays | Modules and variables |

### Migration Path

1. Keep Ansible playbooks for host provisioning (OS, LVM, network setup)
2. Use Terraform for VM/container management (post-provisioning)
3. Use Ansible for VM configuration (inside running VMs)

## State Management

### Local State

For small deployments:

```bash
terraform apply -var-file="../configs/envtest/ring0.tfvars"
```

State is stored in `terraform.tfstate` (should be gitignored).

### Remote State (S3/HTTP Backend)

For production:

```hcl
terraform {
  backend "s3" {
    bucket         = "homelab-terraform"
    key            = "ring0/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

## Troubleshooting

### Provider Connection Issues

If Terraform cannot connect to Incus:

1. Verify `incus remote list` shows your servers
2. Test connection: `incus list -r <remote>`
3. Check client certificates: `ls ~/.config/incus/certs/`

### State Conflicts

If state gets out of sync:

```bash
# Refresh state
terraform refresh

# Plan to see differences
terraform plan

# Manually sync if needed
terraform apply -refresh-only
```

## Future Enhancements

- [ ] Container module for LXC container management
- [ ] Data sources for existing networks, profiles
- [ ] Backup and snapshot automation
- [ ] Integration with CI/CD pipeline
- [ ] Multi-region support

## References

- [Incus Terraform Provider](https://registry.terraform.io/providers/lxc/incus/latest/docs)
- [Incus Documentation](https://linuxcontainers.org/incus/docs/main/)
- [Terraform Documentation](https://www.terraform.io/docs)
