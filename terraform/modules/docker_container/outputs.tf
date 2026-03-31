output "instance_name" {
  description = "The name of the container instance"
  value       = incus_instance.container.name
}

output "instance_ipv4_address" {
  description = "The IPv4 address of the container"
  value       = try(incus_instance.container.ipv4_address, null)
}

output "instance_ipv6_address" {
  description = "The IPv6 address of the container"
  value       = try(incus_instance.container.ipv6_address, null)
}

output "instance_status" {
  description = "The current status of the container"
  value       = incus_instance.container.status
}

output "volume_names" {
  description = "List of persistent volume names created for this container"
  value       = [for vol in incus_storage_volume.volumes : vol.name]
}
