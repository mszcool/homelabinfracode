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
  vm_configurations      = module.shared_config.vm_configurations
  network_configurations = module.shared_config.network_configurations
  global_vm_power_state  = module.shared_config.global_vm_power_state
}

# Incus-specific variables
variable "incus_remote" {
  description = "Incus remote name"
  type        = string
  default     = "local"
}

variable "default_storage_pool" {
  description = "Default storage pool for Incus"
  type        = string
  default     = "default"
}

variable "default_image" {
  description = "Default image for VMs"
  type        = string
  default     = "ubuntu:22.04"
}

variable "routeros_image" {
  description = "RouterOS image (override for RouterOS VM)"
  type        = string
  default     = "ubuntu:22.04" # Change this to actual RouterOS image when available
}

# Network configuration
variable "lab_lan_subnet" {
  description = "Lab LAN subnet configuration"
  type        = string
  default     = "192.168.100.1/24"
}

variable "lab_lan_domain" {
  description = "Lab LAN domain name"
  type        = string
  default     = "lab.local"
}
