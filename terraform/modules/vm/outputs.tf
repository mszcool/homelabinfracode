output "instance_name" {
  description = "The name of the instance"
  value       = incus_instance.vm.name
}

output "instance_ipv4_address" {
  description = "The IPv4 address of the instance"
  value       = try(incus_instance.vm.ipv4_address, null)
}

output "instance_ipv6_address" {
  description = "The IPv6 address of the instance"
  value       = try(incus_instance.vm.ipv6_address, null)
}

output "instance_status" {
  description = "The current status of the instance"
  value       = incus_instance.vm.status
}

output "data_disk_names" {
  description = "List of data disk volume names"
  value       = [for disk in incus_storage_volume.data_disks : disk.name]
}
