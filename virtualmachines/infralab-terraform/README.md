# Terraform VM Automation

This directory contains Terraform configurations for automating the creation of virtual machines using both Incus and Hyper-V providers.

## Structure

```
terraform/
├── shared/
│   ├── variables.tf              # ✨ CENTRALIZED VM configurations
│   ├── outputs.tf               # Shared configuration outputs
│   └── terraform.tfvars.example # Example customization file
├── incus/
│   ├── providers.tf             # Incus provider + shared config import
│   ├── variables.tf             # Incus-specific variables only
│   ├── networks.tf              # Incus network setup
│   ├── virtual-machines.tf      # Incus VM definitions (uses shared config)
│   └── outputs.tf              # Incus outputs
└── hyperv/
    ├── providers.tf             # Hyper-V provider + shared config import
    ├── variables.tf             # Hyper-V-specific variables only
    ├── networks.tf              # Hyper-V network switches
    ├── virtual-machines.tf      # Hyper-V VM definitions (uses shared config)
    └── outputs.tf              # Hyper-V outputs
```

## VM Configuration

The following VMs are defined in the centralized configuration:

- **RouterOS**: 2 CPU cores, 512MB RAM, 64GB disk, connected to lab-wan and lab-lan
- **Incus-SingleDisk**: 2 CPU cores, 2GB RAM, 128GB disk, connected to lab-lan
- **Incus-DualDisk**: 2 CPU cores, 2GB RAM, 2x 128GB disks, connected to lab-lan  
- **Test-Client**: 2 CPU cores, 2GB RAM, 128GB disk, connected to lab-lan

## Network Configuration

- **lab-wan**: External network with internet connectivity
- **lab-lan**: Internal network for VM-to-VM communication (192.168.100.0/24)

## Usage

### Quick Start with Management Scripts

For convenience, use the provided management scripts:

#### Incus (Linux)
```bash
./manage-incus.sh init
./manage-incus.sh plan
./manage-incus.sh apply
```

#### Hyper-V (Windows)
```powershell
.\Manage-HyperV.ps1 -Action init
.\Manage-HyperV.ps1 -Action plan
.\Manage-HyperV.ps1 -Action apply
```

### Manual Terraform Commands

#### Incus Provider

1. Navigate to the incus directory:
   ```bash
   cd terraform/incus
   ```

2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Plan the deployment:
   ```bash
   terraform plan
   ```

4. Apply the configuration:
   ```bash
   terraform apply
   ```

#### Hyper-V Provider (Manual)

1. Navigate to the hyperv directory:
   ```powershell
   cd terraform/hyperv
   ```

2. Initialize Terraform:
   ```powershell
   terraform init
   ```

3. Plan the deployment:
   ```powershell
   terraform plan
   ```

4. Apply the configuration:
   ```powershell
   terraform apply
   ```

## Prerequisites

### Incus
- Incus installed and configured
- Terraform with Incus provider

### Hyper-V
- Windows machine with Hyper-V enabled
- Administrator privileges
- Terraform with Hyper-V provider

## Customization

### Centralized VM Configuration

VM specifications are now centralized in the `shared/variables.tf` file. To modify VM configurations:

1. **Option 1: Edit the default values** in `shared/variables.tf` directly
2. **Option 2: Create a terraform.tfvars file** in the `shared/` directory

#### Example: Increasing VM Resources

Create `shared/terraform.tfvars`:

```hcl
vm_configurations = {
  "routeros" = {
    name          = "RouterOS"
    cpu_cores     = 4          # Increased from 2 to 4
    memory_mb     = 1024       # Increased from 512 to 1024
    disks = [{
      name     = "main"
      size_gb  = 128           # Increased from 64 to 128
    }]
    network_adapters = ["lab-wan", "lab-lan"]
  }
  
  "incus_single_disk" = {
    name          = "Incus-SingleDisk"
    cpu_cores     = 4          # Increased from 2 to 4
    memory_mb     = 4096       # Increased from 2GB to 4GB
    disks = [{
      name     = "main"
      size_gb  = 256           # Increased from 128GB to 256GB
    }]
    network_adapters = ["lab-lan"]
  }
  # ... other VMs with same pattern
}
```

#### Benefits of Centralized Configuration:
- ✅ **Single Source of Truth**: Change VM specs once, applies to both Incus and Hyper-V
- ✅ **Consistency**: No risk of mismatched configurations between providers
- ✅ **Easy Maintenance**: Update one file instead of multiple provider configs
- ✅ **Version Control**: Track configuration changes in one place

### Provider-Specific Settings

Provider-specific variables remain in their respective directories:
- `incus/variables.tf`: Incus-specific settings (storage pools, images, etc.)
- `hyperv/variables.tf`: Hyper-V-specific settings (VM paths, VHD types, etc.)

## Clean Up

### Using Management Scripts

#### Incus
```bash
./manage-incus.sh destroy
```

#### Hyper-V  
```powershell
.\Manage-HyperV.ps1 -Action destroy
```

### Manual Terraform Command

To destroy all resources manually:

```bash
terraform destroy
```

## Notes

- Hyper-V VMs will be created in `C:\VMs\<VM_Name>\` directories
- Incus VMs use the default storage pool
- Network configurations may need adjustment based on your specific environment
- For RouterOS, you may need to specify the correct image source
