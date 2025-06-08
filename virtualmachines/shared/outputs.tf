# Shared Configuration Outputs
# These outputs make the centralized configurations available to consuming modules

output "vm_configurations" {
  description = "Centralized VM configurations"
  value       = var.vm_configurations
}

output "network_configurations" {
  description = "Centralized network configurations"
  value       = var.network_configurations
}

# Individual VM configurations for easy access
output "routeros_config" {
  description = "RouterOS VM configuration"
  value       = var.vm_configurations["routeros"]
}

output "incus_single_disk_config" {
  description = "Incus SingleDisk VM configuration"
  value       = var.vm_configurations["incus_single_disk"]
}

output "incus_dual_disk_config" {
  description = "Incus DualDisk VM configuration"
  value       = var.vm_configurations["incus_dual_disk"]
}

output "test_client_config" {
  description = "Test Client VM configuration"
  value       = var.vm_configurations["test_client"]
}

# Network configurations
output "lab_wan_config" {
  description = "Lab WAN network configuration"
  value       = var.network_configurations["lab_wan"]
}

output "lab_lan_config" {
  description = "Lab LAN network configuration"
  value       = var.network_configurations["lab_lan"]
}
