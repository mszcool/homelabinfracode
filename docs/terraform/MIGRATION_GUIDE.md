# Terraform Incus Refactor — Migration Guide

> **Context**: For the master architecture overview, see [Architecture](../02-architecture.md). For Ring 0 setup workflow, see [Ring 0 Setup](../04-ring0-setup.md). For the full Terraform documentation index, see [INDEX.md](./INDEX.md).
>
> **Path conventions**: Tfvars at `configs/envtest/` (test) or `configs.private/envprod/` (production). Secrets via 1Password. See [Architecture](../02-architecture.md).

This guide helps migrate from the Ansible-based VM management to Terraform.

## Overview

The refactor separates concerns:

| Layer | Tool | Purpose |
|-------|------|---------|
| **Host Provisioning** | Ansible | OS installation, LVM, network setup |
| **Infrastructure Code** | Terraform | VM/container orchestration |
| **VM Configuration** | Ansible | Application setup inside running VMs |

## Key Architectural Changes

### Before (Ansible)

```
Ansible Playbooks
    ├── bootstrap-machines.yaml       (Host OS setup)
    ├── vm-incus-truenas.yaml         (VM creation)
    └── vm-incus-truenas-find-disk-pci.yaml (Hardware discovery)
```

**Challenges:**
- No state tracking for infrastructure
- Manual drift detection (run playbook again)
- No easy rollback mechanism
- Difficult to track what's deployed

### After (Terraform)

```
Terraform
    ├── versions.tf                   (Provider versions)
    ├── providers.tf                  (Incus connection)
    ├── variables.tf                  (Input variables)
    ├── main.tf                       (Root module)
    ├── outputs.tf                    (Outputs)
    ├── modules/
    │   ├── vm/                       (VM module)
    │   │   ├── main.tf
    │   │   ├── variables.tf
    │   │   ├── outputs.tf
    │   │   └── README.md
    │   └── container/                (Future: Container module)
configs/envtest/
    ├── ring0.tfvars                  (Ring0 test infrastructure)
    ├── ring1.tfvars                  (Ring1 test workloads)
    └── ring2.tfvars                  (Ring2 test utilities)
configs.private/envprod/
    ├── ring0.tfvars                  (Ring0 production infrastructure)
    ├── ring1.tfvars                  (Ring1 production workloads)
    └── ring2.tfvars                  (Ring2 production utilities)
```

**Advantages:**
- Infrastructure state tracked in `terraform.tfstate`
- `terraform plan` shows changes before applying
- `terraform destroy` for cleanup
- Version control for infrastructure definitions
- Modular and reusable components

## Migration Path

### Phase 1: Parallel Setup (Weeks 1-2)

1. Set up Terraform files alongside Ansible
2. Validate Terraform configurations
3. Create test VMs with Terraform
4. Document differences and learnings

```bash
# Initialize Terraform
cd terraform
terraform init

# Create workspace for ring0
terraform workspace new ring0
terraform workspace select ring0

# Plan Ring0 deployment (test)
terraform plan -var-file="../configs/envtest/ring0.tfvars"

# Apply in test environment
terraform apply -var-file="../configs/envtest/ring0.tfvars"
```

### Phase 2: Production Migration (Weeks 3-4)

1. Import existing Ansible-created resources into Terraform state
2. Replace Ansible playbooks with Terraform
3. Update CI/CD pipelines

```bash
# Import existing VM (example)
terraform import module.vm.incus_instance.vm \
  "prodlayer0/truenas-primary,image=images:ubuntu/24.04"

# Or manually add to tfstate (advanced)
```

### Phase 3: Cleanup (Week 5)

1. Decommission old Ansible playbooks
2. Archive for reference
3. Update documentation

## Mapping: Ansible → Terraform

### Ansible Variables → Terraform

**host-incus-cluster.yaml** (Ansible inventory):

```yaml
all:
  vars:
    incus:
      # Test servers from public configs
      hosts:
        incussingledisk.yourlab.localtest:
          hostname: incussingledisk
        incusdualdisk.yourlab.localtest:
          hostname: incusdualdisk
```

**Becomes** in `configs/envtest/ring0.tfvars`:

```hcl
vms = {
  "test-ubuntu-single" = {
    target_remote   = "incussingledisk"
    incus_project   = "default"
    cpu_cores       = 2
    memory_gb       = 4
  }
}
```

### Ansible Tasks → Terraform Resources

#### 1. ISO Volume Creation

**Ansible:**
```yaml
- name: Import ISO file into Incus storage volume
  ansible.builtin.shell: |
    incus storage volume import {{ storage_pool }} \
      /tmp/truenas-install.iso truenas-install-iso
```

**Terraform:**
```hcl
resource "incus_storage_volume" "iso" {
  name    = "${var.instance_name}-install-iso"
  pool    = var.storage_pool
  project = var.incus_project
}

resource "null_resource" "iso_import" {
  provisioner "local-exec" {
    command = "incus storage volume import ${var.storage_pool} ${var.iso_source_local} ..."
  }
}
```

#### 2. Data Disk Creation

**Ansible:**
```yaml
- name: Create data disks for TrueNAS VM
  ansible.builtin.command:
    cmd: >
      incus storage volume create {{ storage_pool }} 
      data-disk-{{ item.name }}
  loop: "{{ data_disks_config }}"
```

**Terraform:**
```hcl
resource "incus_storage_volume" "data_disks" {
  for_each = {
    for disk in var.data_disks :
    disk.name => disk
  }
  
  name = "${var.instance_name}-${each.key}"
  pool = each.value.pool
}
```

#### 3. VM Instance Creation

**Ansible:**
```yaml
- name: Create TrueNAS VM from template
  ansible.builtin.shell: |
    incus launch images:ubuntu/24.04 {{ vm_name }} \
      --project={{ incus_project }} \
      --profile={{ incus_profile }}
```

**Terraform:**
```hcl
resource "incus_instance" "vm" {
  name    = var.instance_name
  project = var.incus_project
  
  profiles = [var.incus_profile]
  
  config = {
    "limits.cpu"    = var.cpu_cores
    "limits.memory" = "${var.memory_gb}GB"
  }
}
```

## State Management

### Workspace-Based State Isolation

Each ring uses a separate Terraform workspace. This maps directly to the ring model's identity isolation:

```bash
# Create workspaces (one-time)
cd terraform
terraform workspace new ring0
terraform workspace new ring1
terraform workspace new ring2

# Ring 0 operations
terraform workspace select ring0
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"

# Ring 1 operations
terraform workspace select ring1
terraform plan -var-file="../configs.private/envprod/ring1.tfvars"
terraform apply -var-file="../configs.private/envprod/ring1.tfvars"

# View state per ring
terraform workspace select ring0
terraform state list
terraform state show 'module.vm["truenas-primary"].incus_instance.vm'
```

State files are stored under `terraform.tfstate.d/<workspace>/terraform.tfstate`. A `check` block in `main.tf` warns if you try to plan/apply in the "default" workspace.

### Remote State (Production - Optional)

Set up S3 backend for team collaboration:

```hcl
# terraform/backends.tf
terraform {
  backend "s3" {
    bucket         = "homelab-terraform-state"
    key            = "incus/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

Initialize with backend:

```bash
terraform init -backend-config="bucket=homelab-terraform-state" \
  -backend-config="key=incus/terraform.tfstate"
```

## Hardware Discovery

### Ansible Approach

```bash
ansible-playbook playbooks/ring0/vm-incus-truenas-find-disk-pci.yaml \
  -i configs/envbase/ -i configs.private/envprod/inventory/
```

### Terraform Approach

Use Ansible playbook for discovery, then populate Terraform:

```bash
# 1. Run discovery playbook to get PCI addresses
ansible-playbook playbooks/ring0/vm-incus-truenas-find-disk-pci.yaml

# 2. Update pcie_controller in tfvars
# pcie_controller = "0000:07:00.1"

# 3. Apply Terraform
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
```

Or create a Terraform data source for discovery (advanced):

```hcl
# Not yet implemented - requires custom data source
# For now, use Ansible playbook
```

## Common Operations

### Deploy a New Ring0 VM

```bash
# 1. Update configs.private/envprod/ring0.tfvars with VM definition
# 2. Plan the deployment
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"

# 3. Review output
# 4. Apply
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"

# 5. Get output
terraform output
```

### Scale VM Resources

```bash
# Edit configs.private/envprod/ring0.tfvars
# Change: cpu_cores = 4 -> cpu_cores = 8

terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"

# Note: Some changes require VM restart
```

### Destroy a VM

```bash
# Plan destroy
terraform destroy -var-file="../configs.private/envprod/ring0.tfvars" \
  -target='module.vm["truenas-primary"].incus_instance.vm'

# Apply destroy
terraform destroy -var-file="../configs.private/envprod/ring0.tfvars"
```

### Import Existing Resources

If you have existing VMs managed by Ansible:

```bash
# Find the resource ID
incus list -p prodlayer0

# Import to Terraform
terraform import 'module.vm.incus_instance.vm' \
  'prodlayer0/truenas-primary,image=images:ubuntu/24.04'
```

## Validation and Testing

### Validate Configuration

```bash
terraform validate
```

### Format Code

```bash
terraform fmt -recursive
```

### Security Scanning (tfsec)

```bash
tfsec terraform/
```

### Plan Output Analysis

```bash
# Save plan to file
terraform plan -var-file="../configs.private/envprod/ring0.tfvars" -out=tfplan

# Review in JSON format
terraform show -json tfplan > plan.json
```

## Troubleshooting

### Issue: Provider Not Found

**Error:** `Error: Failed to query available provider packages`

**Solution:**
```bash
rm -rf terraform/.terraform
terraform init
```

### Issue: State Lock

**Error:** `Error acquiring the state lock`

**Solution:**
```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Issue: Resource Already Exists

**Error:** `Error: resource already exists`

**Solution:**
```bash
# Import the existing resource
terraform import 'module.vm.incus_instance.vm' 'prodlayer0/vm-name,image=...'
```

### Issue: Incus Connection Failed

**Error:** `Error: Failed to connect to Incus daemon`

**Solution:**
```bash
# Test Incus connection
incus list -r <remote_name>

# Check client certificates
ls ~/.config/incus/certs/

# Generate new certs if needed
incus admin trust <remote_name>
```

## Rollback Strategy

### Complete Rollback

```bash
# If something goes wrong:
terraform destroy -var-file="../configs.private/envprod/ring0.tfvars"

# Manually restore from backups or recreate via Ansible
```

### Selective Rollback

```bash
# Revert tfvars to previous version
git checkout HEAD~ configs.private/envprod/ring0.tfvars

# Apply previous state
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
```

## Monitoring and Maintenance

### Track State Changes

```bash
# View recent state changes
git diff HEAD terraform/tfstate

# Or with Terraform state tools
terraform state list
terraform state show <resource>
```

### Regular Backups

```bash
# Backup state file
cp terraform/terraform.tfstate terraform/terraform.tfstate.backup

# Or use remote backend for automatic versioning
```

## Next Steps

1. Review this refactor design
2. Set up Terraform files in workspace
3. Test with new VM deployments
4. Import existing VMs into state
5. Update CI/CD pipelines
6. Document team processes
7. Archive Ansible playbooks
