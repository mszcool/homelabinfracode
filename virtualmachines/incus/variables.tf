# Incus Variables
# Additional configuration variables specific to Incus
# Note: Main variables are defined in providers.tf to keep them with the module configuration

variable "global_vm_power_state" {
  description = "Global power state for all VMs (running, stopped)"
  type        = string
  default     = "running"

  validation {
    condition     = contains(["running", "stopped"], var.global_vm_power_state)
    error_message = "VM power state must be either 'running' or 'stopped'."
  }
}
