# Terraform — Quick Start Guide

> **Context**: For the master setup workflow, see [Ring 0 Setup](../04-ring0-setup.md). For Terraform installation, see [Environment Setup](../03-environment-setup.md). For the full Terraform documentation index, see [INDEX.md](./INDEX.md).
>
> **Path conventions**: Tfvars at `configs/envtest/` (test) or `configs.private/envprod/` (production). See [Architecture](../02-architecture.md).

Get up and running with Terraform for Incus in 10 minutes.

## Prerequisites

1. **Terraform installed** (v1.5.0 or later)
   ```bash
   terraform version
   # Terraform v1.5.0 or later
   ```

2. **Incus client configured** with remotes
   ```bash
   incus remote list
   # should show: incussingledisk, incusdualdisk (or your production servers)
   ```

3. **Client certificates** installed
   ```bash
   ls ~/.config/incus/certs/
   # should show: client.crt, client.key
   ```

## Quick Start (5 minutes)

### 1. Initialize Terraform

```bash
cd terraform
terraform init
```

**Expected output:**
```
Initializing the backend...
Initializing modules...
- vm in ./modules/vm

Terraform has been successfully configured!
```

### 2. Review Example Configuration

Sample configurations are provided in the public `configs/envtest/` directory for reference:
- `configs/envtest/ring0.tfvars` - Infrastructure layer examples
- `configs/envtest/ring1.tfvars` - Application layer examples  
- `configs/envtest/ring2.tfvars` - Utility services examples

**Actual configuration** is stored in the private `configs.private/envprod/` repository:
- `configs.private/envprod/ring0.tfvars` - Your Ring0 infrastructure
- `configs.private/envprod/ring1.tfvars` - Your Ring1 applications
- `configs.private/envprod/ring2.tfvars` - Your Ring2 utilities

### 3. Plan the Deployment

```bash
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
```

**What to expect:**
- Terraform analyzes the configuration
- Shows what will be created (adds/changes/destroys)
- Displays resource details

Example output:
```
Terraform will perform the following actions:

  # module.vm["truenas-primary"].incus_instance.vm will be created
  + resource "incus_instance" "vm" {
      + name    = "truenas-primary"
      + project = "prodlayer0"
      + type    = "virtual-machine"
      ...
    }

Plan: 3 to add, 0 to change, 0 to destroy.
```

### 4. Apply the Configuration (Optional - Testing)

```bash
# Dry run (shows what would happen)
terraform apply -var-file="../configs.private/envprod/ring0.tfvars" -auto-approve

# Or interactive (review before applying)
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
```

### 5. View Outputs

```bash
terraform output
```

Example output:
```json
{
  "vms": {
    "truenas-primary": {
      "instance_id": "prodlayer0/truenas-primary",
      "ipv4_address": "192.168.1.100",
      "ipv6_address": "fd00::100",
      "status": "RUNNING"
    }
  }
}
```

## Common Tasks

### View Current State

```bash
# List all managed resources
terraform state list

# Show details of a specific resource
terraform state show 'module.vm["truenas-primary"].incus_instance.vm'
```

### Modify a VM

1. Edit `../configs.private/envprod/ring0.tfvars`
2. Change a value (e.g., `cpu_cores = 4` → `cpu_cores = 8`)
3. Plan to see changes:
   ```bash
   terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
   ```
4. Apply:
   ```bash
   terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
   ```

### Destroy a VM

```bash
# Destroy specific VM
terraform destroy -var-file="../configs.private/envprod/ring0.tfvars" \
  -target='module.vm["truenas-primary"].incus_instance.vm'

# Or destroy everything
terraform destroy -var-file="../configs.private/envprod/ring0.tfvars"
```

### Create a New VM

1. Add to `../configs.private/envprod/ring0.tfvars`:
   ```hcl
   "new-ubuntu-vm" = {
     target_remote = "incussingledisk"  # Use your test or production server
     incus_project = "default"
     cpu_cores     = 2
     memory_gb     = 4
     image         = "images:ubuntu/24.04"
     # ... other settings
   }
   ```

2. Plan and apply:
   ```bash
   terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
   terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
   ```

## Understanding the Files

### `versions.tf`
Specifies Terraform version and provider versions
```hcl
required_version = ">= 1.5.0"
required_providers {
  incus = "~> 1.0"
}
```

### `providers.tf`
Configures how Terraform connects to Incus
```hcl
provider "incus" {
  # Uses pre-configured remotes from ~/.config/incus
}
```

### `variables.tf`
Defines input variables
```hcl
variable "vms" {
  type = map(object({
    target_remote   = string
    incus_project   = string
    # ... more fields
  }))
}
```

### `main.tf`
Uses the VM module for each VM in `vms` variable
```hcl
module "vm" {
  for_each = var.vms
  source   = "./modules/vm"
  # ... pass variables to module
}
```

### `configs/envtest/ring0.tfvars`
Environment-specific values
```hcl
vms = {
  "truenas-primary" = {
    # VM definition
  }
}
```

### `modules/vm/main.tf`
Core resources: storage volumes, instances, provisioners
- `incus_storage_volume` for ISO and data disks
- `incus_instance` for VMs
- `null_resource` for ISO import

## Troubleshooting

### Error: "Failed to connect to Incus daemon"

**Check:**
1. Verify Incus is running:
   ```bash
   incus list -r incussingledisk  # Use your configured remote name
   ```

2. Check client certs exist:
   ```bash
   ls ~/.config/incus/certs/
   ```

3. Test provider manually:
   ```bash
   incus remote list
   ```

### Error: "Provider not found"

**Solution:**
```bash
rm -rf terraform/.terraform/
terraform init
```

### Error: "Project not found"

**Cause:** The `incus_project` in tfvars doesn't exist

**Solution:**
- Create the project via preseed or incus CLI:
  ```bash
  incus project create prodlayer0
  ```
- Or update tfvars to use existing project

### Plan shows no changes but apply still modifies

**Possible causes:**
1. Incus daemon was updated
2. External changes to resources
3. Resource configuration drift

**Solution:**
```bash
terraform refresh
terraform plan
```

## Best Practices

### 1. Always Plan Before Apply

```bash
# Review what will change
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"

# Then apply if satisfied
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
```

### 2. Use Version Control

```bash
git add terraform/
git commit -m "Add truenas-primary VM"
```

### 3. Keep Secrets Out of VCS

If using sensitive data:
```bash
# Use environment variables
export TF_VAR_incus_token="<token>"

# Or use separate secrets file (not in git)
terraform apply -var-file="../configs.private/envprod/ring0.tfvars" \
  -var-file="secrets.tfvars.auto"
```

### 4. Organize by Environment

```
configs/envtest/                    # Test environment
├── ring0.tfvars                    # Infrastructure layer
├── ring1.tfvars                    # Application layer
└── ring2.tfvars                    # User services
configs.private/envprod/            # Production environment
├── ring0.tfvars
├── ring1.tfvars
└── ring2.tfvars
```

### 5. Document Changes

```bash
# Add comments to tfvars
# Updated cpu_cores from 4 to 8 for better performance
"truenas-primary" = {
  cpu_cores = 8  # Was 4
  ...
}
```

## Next Steps

1. **Test with a simple VM** (all files already set up)
2. **Review MIGRATION_GUIDE.md** for detailed migration steps
3. **Check DESIGN_SUMMARY.md** for architectural details
4. **Explore modules/vm/README.md** for module documentation
5. **Set up remote state** (optional, for team collaboration)

## Useful Commands Cheat Sheet

```bash
# Initialize working directory
terraform init

# Validate configuration syntax
terraform validate

# Format code
terraform fmt -recursive

# Plan changes
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"

# Apply changes
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"

# Destroy resources
terraform destroy -var-file="../configs.private/envprod/ring0.tfvars"

# View state
terraform state list
terraform state show <resource>

# View outputs
terraform output

# Refresh state
terraform refresh

# Debug (set before running)
export TF_LOG=DEBUG
```

## Getting Help

- **Terraform docs**: https://www.terraform.io/docs
- **Incus provider docs**: https://registry.terraform.io/providers/lxc/incus/latest/docs
- **Incus docs**: https://linuxcontainers.org/incus/docs/
- **Issues/Questions**: Check terraform/MIGRATION_GUIDE.md for common issues

## Success Indicators

You've successfully set up Terraform when:

- `terraform init` completes without errors
- `terraform validate` shows "Valid configuration"
- `terraform plan` shows planned resources without errors
- `terraform apply` creates resources successfully
- `incus list -p prodlayer0` shows the created VMs
- `terraform output` displays VM information

---

**Ready to deploy?** Run:
```bash
cd terraform
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
```
