variable "instance_name" {
  description = "Name of the Docker/OCI container instance"
  type        = string
}

variable "target_remote" {
  description = "Name of the Incus remote where the container will be created"
  type        = string
}

variable "incus_project" {
  description = "Name of the Incus project (must exist)"
  type        = string
  default     = "default"
}

variable "incus_profile" {
  description = "Name of the Incus profile to apply (must exist)"
  type        = string
  default     = "default"
}

variable "storage_pool" {
  description = "Default storage pool for container rootfs and volumes"
  type        = string
  default     = "incus-instances"
}

variable "image" {
  description = <<-EOT
    OCI image reference for the container.
    
    Requires an OCI-compatible remote configured in your Incus client, e.g.:
      incus remote add docker https://docker.io --protocol=oci
    
    Then reference images as: "docker:library/eclipse-mosquitto:2"
    
    The remote name (before the colon) must match a configured Incus remote.
  EOT
  type        = string
}

variable "cpu_cores" {
  description = "CPU core limit for the container"
  type        = number
  default     = 1

  validation {
    condition     = var.cpu_cores > 0 && var.cpu_cores <= 64
    error_message = "CPU cores must be between 1 and 64."
  }
}

variable "memory_limit_mb" {
  description = "Memory limit in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.memory_limit_mb >= 64 && var.memory_limit_mb <= 131072
    error_message = "Memory limit must be between 64 MB and 128 GB."
  }
}

variable "root_disk_gb" {
  description = "Root disk size limit in GB. Set to 0 for no explicit limit (uses pool default)."
  type        = number
  default     = 0
}

variable "network_bridge" {
  description = "Network bridge to attach the container NIC to (e.g., 'phys-br' for LAN access)"
  type        = string
  default     = "phys-br"
}

variable "mac_address" {
  description = "Optional MAC address for the container's primary NIC. Leave empty for auto-assignment."
  type        = string
  default     = ""
}

variable "enable_boot_autostart" {
  description = "Automatically start the container on host boot"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment variables passed to the OCI container (key = value pairs)"
  type        = map(string)
  default     = {}
}

variable "volumes" {
  description = "Persistent filesystem volumes to create and mount into the container"
  type = list(object({
    name    = string
    path    = string # Mount path inside the container
    size_gb = optional(number, 10)
    pool    = optional(string, "") # Empty = use container's storage_pool
    files = optional(list(object({
      content            = optional(string, "")
      source_path        = optional(string, "")
      target_path        = string
      mode               = optional(string, "0644")
      uid                = optional(number, 0)
      gid                = optional(number, 0)
      create_directories = optional(bool, true)
    })), [])
  }))
  default = []
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
  }
}
