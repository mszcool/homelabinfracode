# Shared VM Configuration Module
# This module contains centralized VM definitions that can be used across different providers

variable "global_vm_power_state" {
  description = "Global power state for all VMs (running, stopped)"
  type        = string
  default     = "running"

  validation {
    condition     = contains(["running", "stopped"], var.global_vm_power_state)
    error_message = "VM power state must be either 'running' or 'stopped'."
  }
}

variable "vm_configurations" {
  description = "Centralized VM configurations"
  type = map(object({
    name      = string
    cpu_cores = number
    memory_mb = number
    disks = list(object({
      name    = string
      size_gb = number
    }))
    network_adapters = list(string)
    is_routeros      = optional(bool, false) # Special flag for RouterOS VMs
  }))
  default = {
    "routeros" = {
      name      = "RouterOS"
      cpu_cores = 2
      memory_mb = 512
      disks = [{
        name    = "main"
        size_gb = 64
      }]
      network_adapters = ["lab-wan", "lab-lan"]
      is_routeros      = true
    }

    "incus_single_disk" = {
      name      = "Incus-SingleDisk"
      cpu_cores = 2
      memory_mb = 2048
      disks = [{
        name    = "main"
        size_gb = 128
      }]
      network_adapters = ["lab-lan"]
    }

    "incus_dual_disk" = {
      name      = "Incus-DualDisk"
      cpu_cores = 2
      memory_mb = 2048
      disks = [
        {
          name    = "main"
          size_gb = 128
        },
        {
          name    = "data"
          size_gb = 128
        }
      ]
      network_adapters = ["lab-lan"]
    }

    "test_client" = {
      name      = "Test-Client"
      cpu_cores = 2
      memory_mb = 1024
      disks = [{
        name    = "main"
        size_gb = 128
      }]
      network_adapters = ["lab-lan"]
    }

    "test_client_2" = {
      name      = "Test-Client-2"
      cpu_cores = 2
      memory_mb = 1024
      disks = [{
        name    = "main"
        size_gb = 128
      }]
      network_adapters = ["lab-lan"]
    }

    "test_client_3" = {
      name      = "Test-Client-3"
      cpu_cores = 2
      memory_mb = 1024
      disks = [{
        name    = "main"
        size_gb = 128
      }]
      network_adapters = ["lab-lan"]
    }
  }
}

variable "network_configurations" {
  description = "Network switch configurations"
  type = map(object({
    name        = string
    description = string
    type        = string
  }))

  default = {
    "lab_wan" = {
      name        = "lab-wan"
      description = "External network with internet connection"
      type        = "external"
    }

    "lab_lan" = {
      name        = "lab-lan"
      description = "Internal VM network"
      type        = "internal"
    }
  }
}
