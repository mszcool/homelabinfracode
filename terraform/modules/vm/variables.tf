variable "instance_name" {
  description = "Name of the VM instance"
  type        = string
}

variable "target_remote" {
  description = "Name of the Incus remote where the VM will be created"
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
  description = "Name of the storage pool for instance storage (must exist)"
  type        = string
  default     = "incus-instances"
}

variable "type" {
  description = "Instance type: 'container' or 'virtual-machine'"
  type        = string
  default     = "virtual-machine"

  validation {
    condition     = contains(["container", "virtual-machine"], var.type)
    error_message = "Instance type must be 'container' or 'virtual-machine'."
  }
}

variable "image" {
  description = "Base image to use for the instance (e.g., 'images:ubuntu/24.04'). Leave empty if using ISO installation."
  type        = string
  default     = ""
}

variable "cpu_cores" {
  description = "Number of CPU cores to allocate"
  type        = number
  default     = 4

  validation {
    condition     = var.cpu_cores > 0 && var.cpu_cores <= 256
    error_message = "CPU cores must be between 1 and 256."
  }
}

variable "memory_gb" {
  description = "Memory allocation in GB"
  type        = number
  default     = 8

  validation {
    condition     = var.memory_gb > 0 && var.memory_gb <= 1024
    error_message = "Memory must be between 1 GB and 1024 GB."
  }
}

variable "system_disk_gb" {
  description = "Size of the root disk in GB"
  type        = number
  default     = 64

  validation {
    condition     = var.system_disk_gb > 0 && var.system_disk_gb <= 10240
    error_message = "System disk size must be between 1 GB and 10240 GB."
  }
}

variable "network_bridge" {
  description = "Name of the network bridge to attach to"
  type        = string
  default     = "phys-br"
}

variable "mac_address" {
  description = "MAC address for the primary network interface (optional)"
  type        = string
  default     = ""
}

variable "iso_volume_name" {
  description = "Name of the pre-imported ISO storage volume (e.g., 'truenas-25.10.1'). Must exist in the specified storage pool. The volume must be imported via Ansible playbook before applying Terraform."
  type        = string
  default     = ""
}

variable "iso_mounted" {
  description = "Whether to mount the ISO device to the VM. Set to true to attach the ISO for installation, false to remove it after installation is complete."
  type        = bool
  default     = false
}

variable "enable_pcie_passthrough" {
  description = "Enable PCIe controller passthrough"
  type        = bool
  default     = false
}

variable "pcie_controller" {
  description = "PCIe controller PCI address (format: 0000:XX:YY.Z)"
  type        = string
  default     = ""
}

variable "data_disks" {
  description = "List of data disks to create and attach"
  type = list(object({
    name = string
    size = number # in GB
    pool = optional(string, "incus-instances")
  }))
  default = []
}

variable "enable_boot_autostart" {
  description = "Automatically start VM on host boot"
  type        = bool
  default     = false
}

variable "root_username" {
  description = "Username for the privileged user (e.g., 'admin', 'sysadmin'). Only used with image-based VMs. Will be created with full sudo access."
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\\$)$", var.root_username))
    error_message = "root_username must be a valid Linux username (lowercase letters, numbers, underscore, hyphen)."
  }
}

variable "ssh_public_key" {
  description = "SSH public key to add to the instance for passwordless access (optional). Only used with image-based VMs."
  type        = string
  default     = ""
  sensitive   = true
}

variable "root_password" {
  description = <<-EOT
    Yescrypt hashed password for the root_username user. Must be pre-hashed - do NOT pass plaintext.
    
    Ubuntu 24.04 uses yescrypt hashing by default (see /etc/pam.d/common-password). The hash format starts with $y$.
    
    Generate the hash before running Terraform using one of these methods:
    
    Using mkpasswd (Ubuntu/Debian):
      mkpasswd -m yescrypt
      # Paste your password, press Enter twice, copy the output
    
    Using Python passlib:
      python3 << 'EOF'
      from passlib.hash import yescrypt
      print(yescrypt.hash('YourPassword'))
      EOF
    
    Then pass it to Terraform:
      export TF_VAR_root_password='$y$j9T$....(hashed_password)....'
      terraform apply --var-file="../configs.private/ring0/ring0.tfvars"
    
    Leave empty ("") to skip password-based authentication for this user.
    Only used with image-based VMs (cloud-init).
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
  }
}
