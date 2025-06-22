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
  user     = var.hyperv_username
  password = var.hyperv_password
  host     = "127.0.0.1"
  port     = 5986
  https    = true
  insecure = true # Accept self-signed certificates
  use_ntlm = true
  timeout  = "30s"
}

# Import shared configuration module
module "shared_config" {
  source = "../shared"
}

# Local variables to access shared configurations
locals {
  vm_configurations      = module.shared_config.vm_configurations
  network_configurations = module.shared_config.network_configurations
  global_vm_power_state  = module.shared_config.global_vm_power_state
}

variable "switch_type" {
  description = "Default virtual switch type"
  type        = string
  default     = "Internal"
}

variable "hyperv_username" {
  description = "Username for Hyper-V authentication"
  type        = string
}

variable "hyperv_password" {
  description = "Password for Hyper-V authentication"
  type        = string
  sensitive   = true
}
