# Hyper-V Outputs
output "vm_instances" {
  description = "All VM instance details"
  value = {
    for vm_key, vm in hyperv_machine_instance.vm : vm_key => {
      id   = vm.name
      name = vm.name
    }
  }
}

# Individual VM outputs for backwards compatibility
output "routeros_id" {
  description = "RouterOS VM instance ID"
  value       = hyperv_machine_instance.vm["routeros"].name
}

output "incus_single_disk_id" {
  description = "Incus Single Disk VM instance ID"
  value       = try(hyperv_machine_instance.vm["incus_single_disk"].name, null)
}

output "incus_dual_disk_id" {
  description = "Incus Dual Disk VM instance ID"
  value       = try(hyperv_machine_instance.vm["incus_dual_disk"].name, null)
}

output "test_client_id" {
  description = "Test Client VM instance ID"
  value       = try(hyperv_machine_instance.vm["test_client"].name, null)
}

output "truenas_id" {
  description = "TrueNAS VM instance ID"
  value       = try(hyperv_machine_instance.vm["truenas"].name, null)
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
    for vm_key, vm in module.shared_config.vm_configurations : vm_key => {
      disks = [
        for disk_idx, disk in vm.disks : {
          name = disk.name
          path = hyperv_vhd.vm_disks["${vm_key}_${disk_idx}"].path
          controller_location = disk_idx
        }
      ]
    }
  }
}
