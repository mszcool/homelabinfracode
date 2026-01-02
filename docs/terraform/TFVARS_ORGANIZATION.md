# Terraform Variable Files Organization

## Overview

This Terraform configuration uses a dual-repository approach to manage infrastructure as code while protecting sensitive information:

- **Public Repository** (`homelabinfracode`): Contains Terraform code and sample configurations
- **Private Repository** (`homelabinfraprivateconfig` - submodule): Contains actual deployment configurations

## Directory Structure

### Sample Configurations (Public)
Located in `configs/` directory of the public `homelabinfracode` repository:

```
configs/
├── ring0/
│   ├── ring0.tfvars              # Sample Ring0 infrastructure
│   └── networking-foundation.yaml
├── ring1/
│   └── ring1.tfvars              # Sample Ring1 applications
├── ring2/
│   └── ring2.tfvars              # Sample Ring2 utilities
├── host-incus-cluster.yaml       # Sample host configuration
├── networking-foundation.yaml
└── archive/                       # Legacy configurations
```

**Purpose:**
- Reference examples for different infrastructure tiers
- Documentation showing configuration structure
- Safe to commit to public repository
- Include helpful comments and explanations
- Aligned with server names: aoostar, peladin, odyssey

**Content Examples:**
- Ring0: TrueNAS VMs with ISO-based installation
- Ring1: Application servers with image-based deployment
- Ring2: Utility containers and services (future)

### Actual Configurations (Private)
Located in `configs.private/` directory (Git submodule pointing to `homelabinfraprivateconfig`):

```
configs.private/
├── ring0/
│   ├── ring0.tfvars              # YOUR actual Ring0 configuration
│   ├── host-incus-cluster.yaml
│   ├── networking-foundation.yaml
│   └── incus/                    # Generated preseed configurations
├── ring1/
│   └── ring1.tfvars              # YOUR actual Ring1 configuration
├── ring1-test/
│   └── networking-pi-edge-configs.yaml
├── ring2/
│   └── ring2.tfvars              # YOUR actual Ring2 configuration
└── switch-infra-as-code/
    └── # Network switch configurations
```

**Purpose:**
- Your actual infrastructure definitions
- Contains sensitive data (IP addresses, MAC addresses, ISO paths, PCI controller IDs)
- Never committed to public repository
- Submodule in separate private Git repository
- Protected from accidental public disclosure

## Using the Configuration Files

### For Development / Understanding Structure

1. Browse sample files in `configs/` directory
2. Review comments and examples
3. Understand the structure of required parameters
4. Use as template for your own configuration

Example:
```bash
# View sample Ring0 configuration
cat configs/ring0/ring0.tfvars

# View sample Ring1 configuration
cat configs/ring1/ring1.tfvars
```

### For Actual Deployment

1. Ensure `configs.private` submodule is initialized
2. Create/edit actual configuration in `configs.private/ring*/`
3. Always reference `configs.private` paths in Terraform commands

Example:
```bash
# Initialize Terraform (from terraform/ directory)
cd terraform
terraform init

# Plan deployment with private configuration
terraform plan -var-file="../configs.private/ring0/ring0.tfvars"

# Apply deployment with private configuration
terraform apply -var-file="../configs.private/ring0/ring0.tfvars"
```

## Configuration File Naming Convention

Each ring has a `ring*.tfvars` file following this pattern:

```
configs/ring{N}/ring{N}.tfvars       # PUBLIC sample
configs.private/ring{N}/ring{N}.tfvars  # PRIVATE actual
```

Where N is the ring number:
- **ring0**: Infrastructure/storage/networking (foundational)
- **ring1**: Applications and services
- **ring2**: Utility services and monitoring

## Setting Up the Private Repository

### Initial Setup

```bash
# Clone the public repository
git clone https://github.com/mszcool/homelabinfracode.git
cd homelabinfracode

# Initialize the Git submodule (configs.private)
git submodule init
git submodule update
```

### After Cloning

If you've already cloned but submodule is empty:

```bash
# From repository root
git submodule update --init --recursive

# Or manually:
git clone https://github.com/mszcool/homelabinfraprivateconfig.git configs.private
```

### Updating Private Configuration

```bash
# Navigate to private configs
cd configs.private

# Make changes to ring0.tfvars, ring1.tfvars, etc
# Edit: ring0/ring0.tfvars, ring1/ring1.tfvars, etc

# Commit changes
git add ring0/ring0.tfvars
git commit -m "Update Ring0 configuration"
git push origin main

# Back to public repo root
cd ..

# Update submodule reference
git add configs.private
git commit -m "Update configs.private submodule reference"
git push origin main
```

## Security Considerations

### What Goes in Configs.Private

✅ **Sensitive Information (KEEP PRIVATE):**
- IP addresses and MAC addresses
- ISO file paths and local file locations
- PCIe controller addresses (hardware-specific)
- Authentication tokens and credentials
- Network configuration details
- Storage paths and mount points

### What Goes in Configs (Public)

✅ **Reference Information (SAFE TO SHARE):**
- Configuration structure and format
- Example values (with placeholders)
- Helpful comments and explanations
- List of available options
- Alternative configuration examples
- Server names as placeholders (aoostar, peladin, odyssey)

## Example: Ring0 Configuration

### Public Sample (`configs/ring0/ring0.tfvars`)
```hcl
incus_remotes = {
  "aoostar" = "incus.aoostar.mszlocal:8443"
  "peladin" = "incus.peladin.mszlocal:8443"
  "odyssey" = "incus.odyssey.mszlocal:8443"
}

vms = {
  "truenas-primary" = {
    target_remote           = "aoostar"        # Example server
    incus_project           = "prodlayer0"
    cpu_cores               = 4
    memory_gb               = 16
    iso_source_local        = "/home/user/iso/TrueNAS-SCALE-25.04.2.5.iso"  # Example path
    iso_path                = "/srv/iso/truenas-25.04.2.5.iso"
    pcie_controller         = "0000:07:00.1"   # Discover via: lspci | grep "PCI"
    # ... other settings
  }
}
```

### Private Actual (`configs.private/ring0/ring0.tfvars`)
```hcl
incus_remotes = {
  "aoostar" = "incus.aoostar.mszlocal:8443"
  "peladin" = "incus.peladin.mszlocal:8443"
  "odyssey" = "incus.odyssey.mszlocal:8443"
}

vms = {
  "truenas-primary" = {
    target_remote           = "aoostar"
    incus_project           = "prodlayer0"
    cpu_cores               = 4
    memory_gb               = 16
    iso_source_local        = "/home/mszcool/iso/TrueNAS-SCALE-25.04.2.5.iso"  # Actual path
    iso_path                = "/srv/iso/truenas-25.04.2.5.iso"
    pcie_controller         = "0000:07:00.1"   # Actual hardware address
    # ... other settings
  }
}
```

## Troubleshooting

### "Error reading config file" or "File not found"

**Problem:** Terraform can't find the tfvars file
**Solution:** Verify you're using the correct path:
```bash
# From terraform/ directory, use:
terraform plan -var-file="../configs.private/ring0/ring0.tfvars"

# NOT:
terraform plan -var-file="tfvars/ring0.tfvars"  # ❌ Wrong path
```

### Submodule appears empty

**Problem:** `configs.private/` directory exists but has no files
**Solution:** Initialize the submodule:
```bash
git submodule update --init --recursive
cd configs.private
git pull origin main
cd ..
```

### Changes not reflected in deployment

**Problem:** Updated `configs.private` tfvars but Terraform still uses old values
**Solution:** Ensure Terraform reads the updated file:
```bash
# Force re-read of variables
terraform apply -var-file="../configs.private/ring0/ring0.tfvars" -refresh=true
```

## Best Practices

1. **Never commit private configs to public repo**
   - Use separate Git repositories
   - Use submodule for linking

2. **Keep samples well-commented**
   - Explain each parameter's purpose
   - Provide reasonable default examples
   - Document required vs optional fields

3. **Use consistent naming**
   - Match ring numbers in directory and file names
   - Use descriptive VM names in tfvars
   - Document server roles (aoostar=compute, etc)

4. **Document changes**
   - Add comments in private tfvars explaining customizations
   - Keep changelog of infrastructure modifications
   - Document reasons for parameter choices

5. **Validate before applying**
   - Always run `terraform plan` first
   - Review output carefully
   - Never apply without understanding changes

## See Also

- [QUICKSTART.md](./QUICKSTART.md) - Get running in 10 minutes
- [README.md](./README.md) - Complete architecture overview
- [DESIGN_SUMMARY.md](./DESIGN_SUMMARY.md) - Design decisions and rationale
