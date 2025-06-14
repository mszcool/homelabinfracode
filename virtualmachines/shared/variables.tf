# Shared VM Configuration Module
# This module contains centralized VM definitions that can be used across different providers

variable "global_vm_power_state" {
  description = "Global power state for all VMs (running, stopped)"
  type        = string
  default     = "stopped"

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
    network_adapters = list(object({
      name = string
      static_mac_address = optional(string, null)
    }))
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
      network_adapters = [
        {
          name = "lab-wan"
          static_mac_address = null
        },
        {
          name = "lab-lan"
          static_mac_address = null
        }
      ]
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
      network_adapters = [{
        name = "lab-lan"
        static_mac_address = "00:15:5D:63:A6:06"
      }]
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
      network_adapters = [{
        name = "lab-lan"
        static_mac_address = "00:15:5D:63:A6:07"
      }]
    }

    "test_client" = {
      name      = "Test-Client"
      cpu_cores = 2
      memory_mb = 1024
      disks = [{
        name    = "main"
        size_gb = 128
      }]
      network_adapters = [{
        name = "lab-lan"
        static_mac_address = "00:15:5D:63:A6:08"
      }]
    }

    "test_client_2" = {
      name      = "Test-Client-2"
      cpu_cores = 2
      memory_mb = 1024
      disks = [{
        name    = "main"
        size_gb = 128
      }]
      network_adapters = [{
        name = "lab-lan"
        static_mac_address = "00:15:5D:63:A6:09"
      }]
    }

    "test_client_3" = {
      name      = "Test-Client-3"
      cpu_cores = 2
      memory_mb = 1024
      disks = [{
        name    = "main"
        size_gb = 128
      }]
      network_adapters = [{
        name = "lab-lan"
        static_mac_address = "00:15:5D:63:A6:0A"
      }]
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
