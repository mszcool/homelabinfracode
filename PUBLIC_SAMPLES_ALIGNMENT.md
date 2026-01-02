# Public Sample Configs Alignment - CORRECTED

## Summary

Updated all public sample tfvars files to use test servers from `configs/host-incus-cluster.yaml` instead of production servers.

## Changes Made

### Public Sample Configuration Files (configs/)
**Updated to use TEST servers from public configs/host-incus-cluster.yaml:**

- **Ring0** (`configs/ring0/ring0.tfvars`):
  - `incussingledisk.mszlocaltest` - Single disk test server
  - `incusdualdisk.mszlocaltest` - Dual disk test server
  - Example VMs: test-ubuntu-single, test-ubuntu-dual
  - Includes production example (commented) referencing configs.private

- **Ring1** (`configs/ring1/ring1.tfvars`):
  - `incussingledisk.mszlocaltest` - Single disk test server
  - `incusdualdisk.mszlocaltest` - Dual disk test server
  - Example VMs: test-app-server, test-database (commented), test-service (commented)

- **Ring2** (`configs/ring2/ring2.tfvars`):
  - `incussingledisk.mszlocaltest` - Single disk test server
  - `incusdualdisk.mszlocaltest` - Dual disk test server
  - Example VMs: test-logging (commented)
  - Example Containers: test-utility-dns, test-monitoring, test-backup (all commented)

### Private Actual Configuration Files (configs.private/)
**Unchanged - Still use PRODUCTION servers:**

- **Ring0** (`configs.private/ring0/ring0.tfvars`):
  - `aoostar` - Production dual NVME server
  - `peladin` - Production single SSD server
  - `odyssey` - Production mixed storage server
  - Actual VMs: truenas-primary, truenas-secondary

- **Ring1** (`configs.private/ring1/ring1.tfvars`):
  - Templates for actual production VMs (empty/commented)

- **Ring2** (`configs.private/ring2/ring2.tfvars`):
  - Templates for actual production utilities (empty/commented)

## Directory Structure

```
PUBLIC REPOSITORY (homelabinfracode)
├── configs/                              ← PUBLIC SAMPLES
│   ├── host-incus-cluster.yaml          ← Test servers: incussingledisk, incusdualdisk
│   ├── ring0/ring0.tfvars               ← Uses test servers (examples)
│   ├── ring1/ring1.tfvars               ← Uses test servers (examples)
│   └── ring2/ring2.tfvars               ← Uses test servers (examples)
│
└── terraform/                            ← Terraform code
    ├── main.tf
    ├── variables.tf
    └── ...

PRIVATE REPOSITORY (homelabinfraprivateconfig - submodule)
├── configs.private/                      ← PRIVATE ACTUAL CONFIGS
│   ├── host-incus-cluster.yaml          ← Production servers: aoostar, peladin, odyssey
│   ├── ring0/ring0.tfvars               ← Uses production servers (actual)
│   ├── ring1/ring1.tfvars               ← Uses production servers (actual)
│   └── ring2/ring2.tfvars               ← Uses production servers (actual)
```

## Key Alignment

### Public Sample (configs/) 
✅ Aligned with `configs/host-incus-cluster.yaml`
- Test servers: incussingledisk, incusdualdisk
- Safe to commit to public repository
- Good for documentation and examples
- Placeholder/example values

### Private Actual (configs.private/)
✅ Aligned with `configs.private/ring0/host-incus-cluster.yaml`
- Production servers: aoostar, peladin, odyssey
- Protected in separate private repository
- Real infrastructure definitions
- Actual deployment configurations

## Usage

### Understanding Examples
```bash
# View test/example configurations
cat configs/ring0/ring0.tfvars      # Public samples with test servers
cat configs/host-incus-cluster.yaml # Test servers definition
```

### Actual Deployment
```bash
# Use production configurations
cd terraform
terraform plan -var-file="../configs.private/ring0/ring0.tfvars"
terraform apply -var-file="../configs.private/ring0/ring0.tfvars"
```

## Verification

All public sample files now reference test servers:
- ✅ `configs/ring0/ring0.tfvars` - Uses incussingledisk, incusdualdisk
- ✅ `configs/ring1/ring1.tfvars` - Uses incussingledisk, incusdualdisk
- ✅ `configs/ring2/ring2.tfvars` - Uses incussingledisk, incusdualdisk

All private actual files use production servers:
- ✅ `configs.private/ring0/ring0.tfvars` - Uses aoostar, peladin, odyssey
- ✅ `configs.private/ring1/ring1.tfvars` - Templates for production
- ✅ `configs.private/ring2/ring2.tfvars` - Templates for production

---

**Status:** ✅ Complete - Public samples now aligned with public configs
**Date:** 2024-12-26
