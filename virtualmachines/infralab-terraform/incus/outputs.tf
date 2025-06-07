# Incus Outputs
output "routeros_id" {
  description = "RouterOS VM instance ID"
  value       = incus_instance.routeros.id
}

output "routeros_ipv4_address" {
  description = "RouterOS VM IPv4 address"
  value       = incus_instance.routeros.ipv4_address
}

output "incus_single_disk_id" {
  description = "Incus Single Disk VM instance ID"
  value       = incus_instance.incus_single_disk.id
}

output "incus_single_disk_ipv4_address" {
  description = "Incus Single Disk VM IPv4 address"
  value       = incus_instance.incus_single_disk.ipv4_address
}

output "incus_dual_disk_id" {
  description = "Incus Dual Disk VM instance ID"
  value       = incus_instance.incus_dual_disk.id
}

output "incus_dual_disk_ipv4_address" {
  description = "Incus Dual Disk VM IPv4 address"
  value       = incus_instance.incus_dual_disk.ipv4_address
}

output "test_client_id" {
  description = "Test Client VM instance ID"
  value       = incus_instance.test_client.id
}

output "test_client_ipv4_address" {
  description = "Test Client VM IPv4 address"
  value       = incus_instance.test_client.ipv4_address
}

output "lab_wan_network" {
  description = "Lab WAN network details"
  value = {
    name = incus_network.lab_wan.name
    type = incus_network.lab_wan.type
  }
}

output "lab_lan_network" {
  description = "Lab LAN network details"
  value = {
    name = incus_network.lab_lan.name
    type = incus_network.lab_lan.type
  }
}
