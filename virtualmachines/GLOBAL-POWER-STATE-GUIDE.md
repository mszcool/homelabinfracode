# Global VM Power State Control - Quick Reference

## Overview
All virtual machines in your lab can now be controlled collectively with a single `global_vm_power_state` variable. This works for both Incus and Hyper-V environments.

## Quick Usage

### Method 1: Command Line (Immediate)
```bash
# Start all VMs
terraform apply -var="global_vm_power_state=running"

# Stop all VMs
terraform apply -var="global_vm_power_state=stopped"
```

### Method 2: terraform.tfvars file (Persistent)
Create or edit `terraform.tfvars` in either `incus/` or `hyperv/` directory:

```hcl
# To start all VMs by default
global_vm_power_state = "running"

# To stop all VMs by default
global_vm_power_state = "stopped"
```

Then run: `terraform apply`

### Method 3: Using Management Scripts
```powershell
# For Hyper-V (Windows)
.\Manage-HyperV.ps1 -Action apply -ExtraArgs "-var=global_vm_power_state=running"
.\Manage-HyperV.ps1 -Action apply -ExtraArgs "-var=global_vm_power_state=stopped"
```

```bash
# For Incus (Linux)
./manage-incus.sh apply -var="global_vm_power_state=running"
./manage-incus.sh apply -var="global_vm_power_state=stopped"
```

## Common Scenarios

### Daily Lab Work
```bash
# Morning: Start your lab
cd virtualmachines/incus  # or hyperv
terraform apply -var="global_vm_power_state=running"

# Evening: Stop your lab to save resources
terraform apply -var="global_vm_power_state=stopped"
```

### Testing/Development
```bash
# Quick power cycling for testing
terraform apply -var="global_vm_power_state=stopped"
terraform apply -var="global_vm_power_state=running"
```

### Resource Management
```hcl
# In terraform.tfvars - Set default to stopped to save resources
global_vm_power_state = "stopped"

# Only start when needed with command line override
terraform apply -var="global_vm_power_state=running"
```

## What This Controls

### Incus VMs
- Controls the `running` parameter on all `incus_instance` resources
- `"running"` = `running: true` (VMs will be started)
- `"stopped"` = `running: false` (VMs will be stopped)

### Hyper-V VMs
- Controls the `state` parameter on all `hyperv_machine_instance` resources
- `"running"` = `state: "Running"` (VMs will be started)
- `"stopped"` = `state: "Off"` (VMs will be powered off)

## Validation
Run the validation script to ensure everything is configured correctly:

```powershell
# Windows
.\Test-PowerState.ps1

# Linux
./test-power-state.sh
```

## Technical Details

### Variable Definition
Located in `shared/variables.tf`:
```hcl
variable "global_vm_power_state" {
  description = "Global power state for all VMs (running, stopped)"
  type        = string
  default     = "running"
  
  validation {
    condition     = contains(["running", "stopped"], var.global_vm_power_state)
    error_message = "VM power state must be either 'running' or 'stopped'."
  }
}
```

### Provider Integration
Both providers access this via:
```hcl
locals {
  global_vm_power_state = module.shared_config.global_vm_power_state
}
```

### VM Resource Implementation
```hcl
# Incus
resource "incus_instance" "vm" {
  running = local.global_vm_power_state == "running" ? true : false
  # ... other configuration
}

# Hyper-V
resource "hyperv_machine_instance" "vm" {
  state = local.global_vm_power_state == "running" ? "Running" : "Off"
  # ... other configuration
}
```

## Troubleshooting

### Common Issues
1. **Variable not recognized**: Ensure you're in the correct directory (`incus/` or `hyperv/`)
2. **Permission errors**: Ensure your user has rights to control VMs
3. **State conflicts**: If VMs are manually started/stopped, Terraform will detect drift and correct it

### Validation Commands
```bash
# Check terraform configuration
terraform validate

# See what changes will be made
terraform plan -var="global_vm_power_state=running"

# View current state
terraform show
```

## Benefits
- **Consistency**: Same command works for all VMs across both providers
- **Efficiency**: Single command instead of managing each VM individually
- **Resource Management**: Easy way to save system resources
- **Testing**: Simplified power cycling for testing scenarios
- **Automation**: Can be integrated into scripts and CI/CD pipelines
