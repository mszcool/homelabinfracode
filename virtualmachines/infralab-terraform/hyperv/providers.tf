# Hyper-V Provider Configuration
terraform {
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.0"
    }
  }
}

# Configure the Hyper-V provider
provider "hyperv" {
  # Provider will use default connection to local Hyper-V
}

# Import shared configuration module
module "shared_config" {
  source = "../shared"
}

# Local variables to access shared configurations
locals {
  vm_configurations     = module.shared_config.vm_configurations
  network_configurations = module.shared_config.network_configurations
}

variable "switch_type" {
  description = "Default virtual switch type"
  type        = string
  default     = "Internal"
}
