# Hyper-V Outputs
output "routeros_id" {
  description = "RouterOS VM instance ID"
  value       = hyperv_machine_instance.routeros.name
}

output "incus_single_disk_id" {
  description = "Incus Single Disk VM instance ID"
  value       = hyperv_machine_instance.incus_single_disk.name
}

output "incus_dual_disk_id" {
  description = "Incus Dual Disk VM instance ID"
  value       = hyperv_machine_instance.incus_dual_disk.name
}

output "test_client_id" {
  description = "Test Client VM instance ID"
  value       = hyperv_machine_instance.test_client.name
}

output "lab_wan_switch" {
  description = "Lab WAN switch details"
  value = {
    name = hyperv_network_switch.lab_wan.name
    type = hyperv_network_switch.lab_wan.switch_type
  }
}

output "lab_lan_switch" {
  description = "Lab LAN switch details"
  value = {
    name = hyperv_network_switch.lab_lan.name
    type = hyperv_network_switch.lab_lan.switch_type
  }
}

output "vm_disk_paths" {
  description = "Virtual machine disk paths"
  value = {
    routeros = {
      main = hyperv_vhd.routeros_disk.path
    }
    incus_single_disk = {
      main = hyperv_vhd.incus_single_disk_main.path
    }
    incus_dual_disk = {
      main = hyperv_vhd.incus_dual_disk_main.path
      data = hyperv_vhd.incus_dual_disk_data.path
    }
    test_client = {
      main = hyperv_vhd.test_client_disk.path
    }
  }
}
