variable "incus_project" {
  description = <<-EOT
    The Incus project used for ALL instances (VMs and Docker containers) managed
    by this Terraform state.
    
    This is a centralized, single-source-of-truth variable. No per-instance
    override is possible — every resource in this state file lands in this project.
    
    This enforces ring isolation:
      ring0.tfvars -> incus_project = "prodlayer0"
      ring1.tfvars -> incus_project = "prodlayer1"
    
    For test environments, use "default".
  EOT
  type        = string
}

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
    target_remote           = string
    incus_profile           = optional(string, "production")
    storage_pool            = optional(string, "incus-instances")
    type                    = optional(string, "virtual-machine")
    image                   = optional(string, "")
    cpu_cores               = optional(number, 4)
    memory_gb               = optional(number, 8)
    system_disk_gb          = optional(number, 64)
    network_bridge          = optional(string, "phys-br")
    mac_address             = optional(string, "")
    iso_volume_name         = optional(string, "")
    iso_mounted             = optional(bool, false)
    enable_pcie_passthrough = optional(bool, false)
    pcie_controller         = optional(string, "")
    enable_boot_autostart   = optional(bool, false)
    root_username           = optional(string, "admin")
    ssh_public_key          = optional(string, "")
    root_password           = optional(string, "")
    root_pwd_vault          = optional(string, "")
    root_pwd_vault_item     = optional(string, "")
    root_pwd_vault_field    = optional(string, "password") # 1Password field name containing the yescrypt hash
    data_disks = optional(list(object({
      name = string
      size = optional(number, 100) # in GB
      pool = optional(string, "incus-instances")
    })), [])
  }))
  default = {}
}

variable "containers" {
  description = "Map of container configurations"
  type = map(object({
    target_remote         = string
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

variable "docker_containers" {
  description = <<-EOT
    Map of Docker/OCI container configurations for Incus.
    
    These are OCI application containers (e.g., Eclipse Mosquitto, Home Assistant)
    running natively on Incus. Requires an OCI-compatible remote configured in
    your Incus client:
      incus remote add docker https://docker.io --protocol=oci
    
    Containers get a bridged NIC on the specified network bridge and are directly
    accessible on their own LAN IP address.
  EOT
  type = map(object({
    target_remote         = string
    incus_profile         = optional(string, "default")
    storage_pool          = optional(string, "incus-instances")
    image                 = string # OCI image ref, e.g., "docker:library/eclipse-mosquitto:2"
    cpu_cores             = optional(number, 1)
    memory_limit_mb       = optional(number, 512)
    root_disk_gb          = optional(number, 0) # 0 = no explicit limit
    network_bridge        = optional(string, "phys-br")
    mac_address           = optional(string, "")
    enable_boot_autostart = optional(bool, true)
    environment           = optional(map(string), {})
    volumes = optional(list(object({
      name    = string
      path    = string # Mount path inside container
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
    })), [])
  }))
  default = {}
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    managed_by  = "terraform"
    environment = "homelab"
  }
}

variable "root_passwords" {
  description = <<-EOT
    Map of yescrypt hashed passwords by VM name. Allows per-VM password management.
    
    DEPRECATED: Prefer using per-VM 1Password integration via op_vault/op_item fields
    in the vms variable. This variable is kept as a fallback for environments
    without 1Password access.
    
    Can be set via:
    1. Direct entry in tfvars (easiest for homelab):
       root_passwords = {
         samba4-addc = "$y$j9T$...(hash1)..."
         truenas-primary = "$y$j9T$...(hash2)..."
       }
    
    2. Environment variable (for CI/CD):
       export TF_VAR_root_passwords='{"samba4-addc":"$y$j9T$hash1...","truenas-primary":"$y$j9T$hash2..."}'
    
    3. Per-VM override: set root_password directly in the vm definition.
    
    4. Per-VM 1Password (recommended): Set op_vault and op_item on each VM
       to fetch the password from the VM's own 1Password item.
    
    Leave empty to disable password-based authentication.
  EOT
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "op_vault_name" {
  description = <<-EOT
    Default 1Password vault name. Used as the default for per-VM op_vault when
    a VM specifies op_item but not op_vault.
    
    Requires OP_SERVICE_ACCOUNT_TOKEN environment variable to be set.
    
    Leave empty to disable 1Password integration.
  EOT
  type        = string
  default     = ""
}
