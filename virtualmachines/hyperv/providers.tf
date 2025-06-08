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
  user     = "terraform-hyperv"
  password = "TerraformHyperV2025!@#"
  host     = "127.0.0.1"
  port     = 5986
  https    = true
  insecure = true  # Accept self-signed certificates
  use_ntlm = true
  timeout  = "30s"
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
