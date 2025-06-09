# Incus Outputs
output "vm_instances" {
  description = "All VM instance details"
  value = {
    for vm_key, vm in incus_instance.vm : vm_key => {
      name         = vm.name
      ipv4_address = vm.ipv4_address
      status       = vm.status
    }
  }
}

# Individual VM outputs for backwards compatibility
output "routeros_id" {
  description = "RouterOS VM instance name"
  value       = incus_instance.vm["routeros"].name
}

output "routeros_ipv4_address" {
  description = "RouterOS VM IPv4 address"
  value       = incus_instance.vm["routeros"].ipv4_address
}

output "incus_single_disk_id" {
  description = "Incus Single Disk VM instance name"
  value       = try(incus_instance.vm["incus_single_disk"].name, null)
}

output "incus_single_disk_ipv4_address" {
  description = "Incus Single Disk VM IPv4 address"
  value       = try(incus_instance.vm["incus_single_disk"].ipv4_address, null)
}

output "incus_dual_disk_id" {
  description = "Incus Dual Disk VM instance name"
  value       = try(incus_instance.vm["incus_dual_disk"].name, null)
}

output "incus_dual_disk_ipv4_address" {
  description = "Incus Dual Disk VM IPv4 address"
  value       = try(incus_instance.vm["incus_dual_disk"].ipv4_address, null)
}

output "test_client_id" {
  description = "Test Client VM instance name"
  value       = try(incus_instance.vm["test_client"].name, null)
}

output "test_client_ipv4_address" {
  description = "Test Client VM IPv4 address"
  value       = try(incus_instance.vm["test_client"].ipv4_address, null)
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
