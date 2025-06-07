# Hyper-V Variables
# Additional configuration variables specific to Hyper-V

variable "vm_base_path" {
  description = "Base path for VM storage"
  type        = string
  default     = "C:\\VMs"
}

variable "hyperv_generation" {
  description = "Hyper-V generation (1 or 2)"
  type        = number
  default     = 2
}

variable "vhd_type" {
  description = "Type of VHD to create (Dynamic, Fixed)"
  type        = string
  default     = "Dynamic"
}

variable "checkpoint_type" {
  description = "Checkpoint type (Production, Standard)"
  type        = string
  default     = "Production"
}

variable "automatic_start_action" {
  description = "Action to take when host starts (Nothing, StartIfRunning, Start)"
  type        = string
  default     = "Nothing"
}

variable "automatic_stop_action" {
  description = "Action to take when host stops (ShutDown, Save, TurnOff)"
  type        = string
  default     = "ShutDown"
}
