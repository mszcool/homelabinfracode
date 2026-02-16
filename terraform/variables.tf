variable "incus_remotes" {
  description = "Map of Incus remotes and their addresses"
  type        = map(string)
  default     = {}
  # Example:
  # {
  #   "aoostar" = "incus.aoostar.mszlocal:8443"
  #   "peladin" = "incus.peladin.mszlocal:8443"
  #   "odyssey" = "incus.odyssey.mszlocal:8443"
  # }
}

variable "vms" {
  description = "Map of VM configurations"
  type = map(object({
    target_remote            = string
    incus_project            = string
    incus_profile            = optional(string, "production")
    storage_pool             = optional(string, "incus-instances")
    type                     = optional(string, "virtual-machine")
    image                    = optional(string, "")
    cpu_cores                = optional(number, 4)
    memory_gb                = optional(number, 8)
    system_disk_gb           = optional(number, 64)
    network_bridge           = optional(string, "phys-br")
    mac_address              = optional(string, "")
    iso_volume_name          = optional(string, "")
    iso_mounted              = optional(bool, false)
    enable_pcie_passthrough  = optional(bool, false)
    pcie_controller          = optional(string, "")
    enable_boot_autostart    = optional(bool, false)
    root_username            = optional(string, "admin")
    ssh_public_key           = optional(string, "")
    root_password            = optional(string, "")
    data_disks = optional(list(object({
      name  = string
      size  = optional(number, 100) # in GB
      pool  = optional(string, "incus-instances")
    })), [])
  }))
  default = {}
}

variable "containers" {
  description = "Map of container configurations"
  type = map(object({
    target_remote         = string
    incus_project         = optional(string, "default")
    incus_profile         = optional(string, "default")
    storage_pool          = optional(string, "incus-instances")
    image                 = optional(string, "images:ubuntu/24.04")
    cpu_cores             = optional(number, 2)
    memory_limit_gb       = optional(number, 2)
    ephemeral             = optional(bool, false)
    enable_boot_autostart = optional(bool, false)
  }))
  default = {}
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    environment = "homelab"
  }
}

variable "root_passwords" {
  description = <<-EOT
    Map of yescrypt hashed passwords by VM name. Allows per-VM password management.
    
    Can be set via:
    1. Direct entry in tfvars (easiest for homelab):
       root_passwords = {
         samba4-addc = "$y$j9T$...(hash1)..."
         truenas-primary = "$y$j9T$...(hash2)..."
       }
    
    2. Environment variable (for CI/CD):
       export TF_VAR_root_passwords='{"samba4-addc":"$y$j9T$hash1...","truenas-primary":"$y$j9T$hash2..."}'
    
    3. Per-VM override in vms map takes precedence over this map.
    
    Leave empty to disable password-based authentication.
  EOT
  type        = map(string)
  default     = {}
  sensitive   = true
}
