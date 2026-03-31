# Terraform Incus Refactor — Design Summary

> **Context**: For the master architecture overview, see [Architecture](../02-architecture.md). This document provides the detailed Terraform-specific design summary.
>
> **Path conventions**: Tfvars are at `configs/envtest/` (test) or `configs.private/envprod/` (production). Docs location: `docs/terraform/` (this directory). See [Architecture](../02-architecture.md) for the full model.

## Overview

This is a complete refactoring of your Incus infrastructure management from Ansible playbooks to Terraform, maintaining modularity for future expansion and respecting pre-existing infrastructure constraints.

## What Was Refactored

### Original Ansible Files
- **host-incus-cluster.yaml** → Contains TrueNAS VM definitions and inventory
- **vm-incus-truenas.yaml** → Creates VMs, storage volumes, and manages ISOs
- **vm-incus-truenas-find-disk-pci.yaml** → Hardware discovery playbook
- **incus.preseed.msz_dualnvme1TB_aoostar.yaml** → Initial Incus provisioning config

### New Terraform Structure
```
terraform/
├── versions.tf                    # Provider version constraints
├── providers.tf                   # Incus provider configuration
├── variables.tf                   # Global input variables (incus_project, vms, docker_containers)
├── locals.tf                      # Local computed values
├── main.tf                        # Root module instantiation + workspace validation check
├── outputs.tf                     # Infrastructure outputs
├── modules/
│   ├── vm/                        # VM module (reusable)
│   │   ├── versions.tf
│   │   ├── variables.tf
│   │   ├── main.tf                # Core VM resources
│   │   ├── outputs.tf
│   │   ├── locals.tf
│   │   └── README.md
│   └── docker_container/          # Docker/OCI container module
│       ├── versions.tf
│       ├── variables.tf
│       ├── main.tf                # Container + volume resources
│       └── outputs.tf
configs/envtest/
├── ring0.tfvars                   # Ring0 infrastructure (test)
├── ring1.tfvars                   # Ring1 workloads (future)
└── ring2.tfvars                   # Ring2 utilities (future)
docs/terraform/
├── TERRAFORM-README.md            # Architecture and usage
├── QUICKSTART.md                  # 10-minute quick start
├── MIGRATION_GUIDE.md             # Step-by-step migration
└── DESIGN_SUMMARY.md              # This document
```

## Key Design Principles

### 1. **Non-Interference with Pre-existing Resources**

The following are managed externally and NOT touched by Terraform:
- Networks (`phys-br`, `iso-nat`)
- Storage pools (`incus-images`, `incus-instances`)
- Projects (`default`, `prodlayer0`, `prodlayer1`)
- Profiles (`default`, `defaultlan`, `production`)

These are created via preseed files and managed separately.

**Terraform manages:**
- Storage volumes (ISO, data disks) - Custom created volumes only
- VM instances
- Instance devices (disks, NICs, PCI)

### 2. **Modularity for Growth**

The design supports future expansion:
- **VM Module** (complete)
- **Docker/OCI Container Module** (complete) — For OCI application containers (e.g., Mosquitto MQTT broker)
- **Network Module** (future)
- **Profile Module** (future)

Each module is self-contained with clear inputs/outputs.

### 3. **Three-Layer Architecture**

```
Ring 0 (Infrastructure)     ← Terraform workspace: ring0, incus_project: prodlayer0
Ring 1 (Applications)       ← Terraform workspace: ring1, incus_project: prodlayer1
Ring 2 (User Services)      ← Terraform workspace: ring2, incus_project: default
```

### 4. **Workspace-Based State Isolation**

Each ring uses a separate Terraform workspace to keep state files isolated. This maps directly to the ring model's identity isolation principle — the ring1 identity should not be able to access or modify ring0 (prodlayer0) resources. A `check` block in `main.tf` warns if Terraform is run in the "default" workspace.

```bash
terraform workspace select ring0
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
```

## How It Works

### Configuration Flow

```
terraform workspace select ring0
    ↓
configs/envtest/ring0.tfvars (or configs.private/envprod/ring0.tfvars)
    ↓
    ├── check "workspace_not_default" (warns if in default workspace)
    ├── Defines VMs → maps to modules/vm/ module
    └── Defines Docker containers → maps to modules/docker_container/ module
            ↓
            ├── Validates inputs
            ├── Creates storage volumes
            ├── Creates instance (VM or container)
            ├── Attaches devices
            └── Imports ISOs (local-exec provisioner, VMs only)
```

### Practical Example: Deploy Test Ubuntu VM

```hcl
# 1. Define in configs/envtest/ring0.tfvars (public sample)
vms = {
  "test-ubuntu-dual" = {
    target_remote           = "incusdualdisk"
    incus_project           = "default"
    incus_profile           = "default"
    storage_pool            = "incus-instances"
    cpu_cores               = 2
    memory_gb               = 4
    system_disk_gb          = 30
    network_bridge          = "br0"
    mac_address             = ""
    image                   = "images:ubuntu/24.04"
    iso_source_local        = ""
    iso_path                = ""
    enable_pcie_passthrough = false
    enable_boot_autostart   = false
    data_disks              = []
  }
}

# 2. Deploy
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"

# 3. Results
# - incus_storage_volume.iso created
# - incus_instance.vm created
# - ISO imported via local-exec
# - terraform.tfstate tracks everything
```

## File-by-File Description

### Root Level

| File | Purpose |
|------|---------|
| **versions.tf** | Terraform version 1.5.0+, Incus provider 1.0+ |
| **providers.tf** | Configures Incus provider, explains auth options |
| **variables.tf** | Global variables: vms, containers, tags |
| **locals.tf** | Local values: name normalization |
| **main.tf** | Module instantiation for VMs |
| **outputs.tf** | Exports VM details: IPs, status, volumes |

### Module: `modules/vm/`

| File | Purpose |
|------|---------|
| **main.tf** | Core resources: incus_storage_volume, incus_instance, null_resource |
| **variables.tf** | VM inputs: instance_name, cpu_cores, memory_gb, iso_handling, etc. |
| **outputs.tf** | VM outputs: instance_id, IP addresses, disk names |
| **locals.tf** | Internal logic: ISO config validation, disk configuration |
| **README.md** | Module documentation and examples |

### Configuration: `configs/envtest/`

| File | Purpose |
|------|---------|
| **ring0.tfvars** | Test Ubuntu VMs and infrastructure examples |
| **ring1.tfvars** | Application VMs (future): databases, services |
| **ring2.tfvars** | Utility containers (future): DNS, backups |

### Documentation: `docs/terraform/`

| File | Purpose |
|------|---------||
| **TERRAFORM-README.md** | Architecture overview, provider setup, usage |
| **QUICKSTART.md** | 10-minute hands-on guide |
| **MIGRATION_GUIDE.md** | Detailed steps to migrate from Ansible |
| **DESIGN_SUMMARY.md** | This document |

## Core Features

### 1. ISO Handling

Two approaches:

**Image-Based (Recommended for Testing):**
```hcl
image = "images:ubuntu/24.04"
# → Uses pre-built image from repository
# → No ISO required - faster deployment
# → Recommended for testing and examples
```

**Local ISO Upload (Production):**
```hcl
iso_source_local = "/home/mszcool/iso/TrueNAS-SCALE-25.04.2.5.iso"
# → Creates volume "truenas-primary-install-iso"
# → Copies local ISO to host
# → Imports into storage volume
# → Attaches as read-only device
```

**Pre-existing ISO:**
```hcl
iso_path = "/srv/iso/truenas-25.04.2.5.iso"
# → Assumes ISO already exists on target host
# → Mounts directly without copying
```

### 2. Data Disk Management

```hcl
data_disks = [
  {
    name = "disk1"
    size = 100  # GB
    pool = "incus-instances"
  }
]
# → Creates separate storage volumes
# → Attaches as block devices to VM
# → Useful for storage workloads
```

### 3. PCIe Passthrough (Production Only)

```hcl
enable_pcie_passthrough = false  # Disabled for test examples
# → Not needed for test/example VMs
# 
# For production use:
# enable_pcie_passthrough = true
# pcie_controller = "0000:07:00.1"  # Discover via Ansible
# → Passes PCIe controller to VM
# → Enables direct hardware access
```

### 4. Network Configuration

```hcl
network_bridge = "br0"
mac_address    = ""  # Auto-generate if empty
# → Attaches to existing bridge
# → Sets static MAC if provided
# → Requires bridge to exist (pre-created)
```

## Resource Dependencies

```
Incus Infrastructure (Pre-existing)
├── Networks: phys-br, iso-nat
├── Storage Pools: incus-images, incus-instances
├── Projects: default, prodlayer0, prodlayer1
└── Profiles: default, defaultlan, production

Terraform-Managed Resources
├── incus_storage_volume (ISO)
├── incus_storage_volume (data disks)
├── incus_instance (VM)
└── null_resource (ISO import provisioner)

Outputs
├── Instance ID, IP addresses
├── Volume names
└── Instance status
```

## State Management

### Local State (Development)

```bash
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
# Creates: terraform.tfstate, terraform.tfstate.backup
# Only on your machine
```

### Remote State (Production - Optional)

```hcl
terraform {
  backend "s3" {
    bucket         = "homelab-terraform"
    key            = "incus/terraform.tfstate"
    dynamodb_table = "terraform-locks"
  }
}
```

Benefits:
- Team access
- Automatic backups
- Concurrent access prevention (locking)
- Version history

## Common Operations

### Plan Changes (Safe Preview)

```bash
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
# Shows exactly what will change
# No actual changes made
```

### Apply Changes

```bash
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
# Executes planned changes
# Updates terraform.tfstate
```

### Destroy Resources

```bash
terraform destroy -var-file="../configs.private/envprod/ring0.tfvars"
# Removes all managed resources
# Careful: Data loss possible
```

### Scale a VM

```hcl
# Edit configs.private/envprod/ring0.tfvars (or configs/envtest/ring0.tfvars for test)
"truenas-primary" = {
  cpu_cores = 8  # Changed from 4
  # ...
}

# Apply
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
# VM automatically updated
```

## Migration Path

### Option 1: Parallel Deployment (Recommended)

```
Week 1: Terraform setup and testing
  ├── Initialize Terraform
  ├── Plan Ring0 deployment
  └── Test with new VMs

Week 2: Gradual migration
  ├── Keep Ansible playbooks running
  ├── New VMs via Terraform
  └── Document differences

Week 3: Cutover
  ├── Archive Ansible playbooks
  ├── Use Terraform as primary
  └── Ansible for VM config only
```

### Option 2: Import Existing

```bash
# For VMs already created by Ansible
terraform import 'module.vm.incus_instance.vm' \
  'prodlayer0/truenas-primary,image=images:ubuntu/24.04'

# Terraform now manages existing VM
terraform plan  # Should show no changes
```

## Validation and Safety

### Validate Configuration

```bash
terraform validate
# Checks syntax and logic
```

### Format Code

```bash
terraform fmt -recursive
# Standardizes formatting
```

### Dry Run

```bash
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
# Shows changes without applying
```

### Drift Detection

```bash
terraform plan -refresh-only
# Detects changes made outside Terraform
```

## Support for Future Expansion

### Container Module (Placeholder)

```hcl
# Future: Uncomment in main.tf
module "container" {
  for_each = var.containers
  source   = "./modules/container"
}

# Define containers in tfvars
containers = {
  "utility-dns" = {
    target_remote = "aoostar"
    image         = "images:ubuntu/24.04"
  }
}
```

### Additional Modules (Planned)

- **Network Module**: Manage Incus networks
- **Profile Module**: Manage Incus profiles
- **Snapshot Module**: VM snapshots and backups
- **Image Module**: Custom images

## Advantages Over Ansible

| Aspect | Benefit |
|--------|---------|
| **State Tracking** | Always know what's deployed |
| **Change Preview** | Plan before applying |
| **Rollback** | `terraform destroy` or `git revert` |
| **Drift Detection** | `terraform plan` shows differences |
| **Team Collaboration** | Remote state + locking |
| **Modularity** | Reusable components |
| **Version Control** | Full audit trail |
| **Automation** | Easy CI/CD integration |

## Potential Challenges and Solutions

| Challenge | Solution |
|-----------|----------|
| **Hardware discovery** | Keep Ansible playbook for initial scan |
| **Complex VM configs** | Use profiles and data_disks configuration |
| **External changes** | `terraform refresh` + `terraform plan` |
| **Secrets management** | Use tfvars.auto (not in git) or env vars |
| **State corruption** | Use remote backend with versioning |

## Documentation Structure

1. **TERRAFORM-README.md** - Start here for overview and architecture
2. **QUICKSTART.md** - Hands-on 10-minute guide
3. **MIGRATION_GUIDE.md** - Detailed migration steps and examples
4. **DESIGN_SUMMARY.md** - This document
5. **modules/vm/README.md** - VM module documentation

## Next Steps

1. **Review this design** - Understand the architecture
2. **Read QUICKSTART.md** - Hands-on setup
3. **Run terraform init** - Initialize workspace
4. **Run terraform plan** - Preview first deployment
5. **Run terraform apply** - Deploy infrastructure
6. **Verify with `incus list`** - Confirm VMs exist
7. **Read MIGRATION_GUIDE.md** - Plan full migration

## Reference Information

### Provider Documentation
- Incus Terraform Provider: https://registry.terraform.io/providers/lxc/incus/latest/docs
- Incus Documentation: https://linuxcontainers.org/incus/docs/

### Terraform Resources Used
- `incus_instance` - Virtual machines and containers
- `incus_storage_volume` - Storage volumes (ISO, data disks)
- `null_resource` with `local-exec` - ISO file import

### Key Variables
- `vms` - Map of VM configurations
- `containers` - Map of container configurations (future)
- `tags` - Common tags for resources

---

**Status:** Complete Design Ready for Implementation

This refactor provides a solid foundation for managing your Incus infrastructure with Terraform while maintaining compatibility with existing Ansible workflows and respecting pre-existing infrastructure constraints.
