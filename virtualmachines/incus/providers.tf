# Incus Provider Configuration
terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 0.1"
    }
  }
}

# Configure the Incus provider
provider "incus" {
  # Configuration options can be added here
  # generate_client_certificates = true
  # accept_remote_certificate    = true
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

# Incus-specific variables
variable "vm_base_path" {
  description = "Base path for VM storage"
  type        = string
  default     = "/var/lib/incus/storage-pools/default"
}

variable "default_image" {
  description = "Default image for VMs"
  type        = string
  default     = "ubuntu:22.04"
}
