# Hyper-V Virtual Machines Configuration

# Dynamic VHD creation for main disks
resource "hyperv_vhd" "main_disks" {
  for_each = local.vm_configurations
  
  path                 = "${var.vm_base_path}\\${each.value.name}\\${each.value.name}.vhdx"
  size                 = each.value.disks[0].size_gb * 1024 * 1024 * 1024
  block_size           = 0
  logical_sector_size  = 0
  physical_sector_size = 0
  vhd_type             = var.vhd_type
}

# Dynamic VHD creation for secondary disks (only if VM has more than 1 disk)
resource "hyperv_vhd" "secondary_disks" {
  for_each = {
    for vm_key, vm_config in local.vm_configurations : vm_key => vm_config
    if length(vm_config.disks) > 1
  }
  
  path                 = "${var.vm_base_path}\\${each.value.name}\\${each.value.name}-${each.value.disks[1].name}.vhdx"
  size                 = each.value.disks[1].size_gb * 1024 * 1024 * 1024
  block_size           = 0
  logical_sector_size  = 0
  physical_sector_size = 0
  vhd_type             = var.vhd_type
}

# Dynamic VM creation based on vm_configurations
resource "hyperv_machine_instance" "vm" {
  for_each = local.vm_configurations
  
  depends_on = [
    hyperv_vhd.main_disks
  ]

  name                                    = each.value.name
  generation                              = each.value.is_routeros ? 1 : 2  # Generation 1 for RouterOS compatibility
  automatic_critical_error_action         = "Pause"
  automatic_critical_error_action_timeout = 30
  automatic_start_action                  = var.automatic_start_action
  automatic_start_delay                   = 0
  automatic_stop_action                   = var.automatic_stop_action
  checkpoint_type                         = var.checkpoint_type
  guest_controlled_cache_types            = false
  high_memory_mapped_io_space             = 536870912
  lock_on_disconnect                      = "Off"
  low_memory_mapped_io_space              = 134217728
  memory_maximum_bytes                    = each.value.memory_mb * 1024 * 1024
  memory_minimum_bytes                    = each.value.memory_mb * 1024 * 1024
  memory_startup_bytes                    = each.value.memory_mb * 1024 * 1024
  notes                                   = "${each.value.name} Virtual Machine"
  processor_count                         = each.value.cpu_cores
  smart_paging_file_path                  = each.value.is_routeros ? "${var.vm_base_path}\\PagingFiles" : "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V"
  snapshot_file_location                  = each.value.is_routeros ? "${var.vm_base_path}\\Snapshots" : "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V"
  static_memory                           = true
  
  # Main disk (always present)
  hard_disk_drives {
    controller_type                 = "Scsi"
    controller_number               = 0
    controller_location             = 0
    path                            = hyperv_vhd.main_disks[each.key].path
    resource_pool_name              = ""
    support_persistent_reservations = false
    override_cache_attributes       = "Default"
    maximum_iops                    = 0
    minimum_iops                    = 0
    qos_policy_id                   = ""
  }

  # Optional second disk (only if more than 1 disk is configured)
  dynamic "hard_disk_drives" {
    for_each = length(each.value.disks) > 1 ? [1] : []
    content {
      controller_type                 = "Scsi"
      controller_number               = 0
      controller_location             = 1
      path                            = hyperv_vhd.secondary_disks[each.key].path
      resource_pool_name              = ""
      support_persistent_reservations = false
      override_cache_attributes       = "Default"
      maximum_iops                    = 0
      minimum_iops                    = 0
      qos_policy_id                   = ""
    }
  }

  # Network adapters - dynamically create based on configuration
  dynamic "network_adaptors" {
    for_each = each.value.network_adapters
    content {
      name                = network_adaptors.value
      switch_name         = network_adaptors.value == "lab-wan" ? hyperv_network_switch.lab_wan.name : hyperv_network_switch.lab_lan.name
      management_os       = false
      is_legacy           = false
      dynamic_mac_address = true
    }
  }
}
