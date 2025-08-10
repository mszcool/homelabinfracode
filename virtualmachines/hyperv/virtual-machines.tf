# Hyper-V Virtual Machines Configuration

# Local variables to help with disk management
locals {
  # Flatten disks for all VMs with additional metadata
  all_vm_disks = flatten([
    for vm_key, vm_config in module.shared_config.vm_configurations : [
      for disk_idx, disk in vm_config.disks : {
        vm_key = vm_key
        vm_name = vm_config.name
        disk_key = "${vm_key}_${disk_idx}"
        disk_name = disk.name
        size_gb = disk.size_gb
        disk_index = disk_idx  # Sequential disk index
        is_routeros = vm_config.is_routeros != null ? vm_config.is_routeros : false
      }
    ]
  ])

  # Convert to map for for_each
  vm_disks_map = {
    for disk in local.all_vm_disks : disk.disk_key => disk
  }
}

# Dynamic VHD creation for all disks
resource "hyperv_vhd" "vm_disks" {
  for_each = local.vm_disks_map

  path                 = "${var.vm_base_path}\\${each.value.vm_name}\\${each.value.vm_name}-${each.value.disk_name}.vhdx"
  size                 = each.value.size_gb * 1024 * 1024 * 1024
  block_size           = 0
  logical_sector_size  = 0
  physical_sector_size = 0
  vhd_type             = var.vhd_type
}

# Dynamic VM creation based on vm_configurations
resource "hyperv_machine_instance" "vm" {
  for_each = module.shared_config.vm_configurations
  name     = each.value.name
  state    = var.global_vm_power_state == "running" ? "Running" : "Off"
  # VM Generation and basic settings
  generation                          = each.value.is_routeros ? 1 : var.hyperv_generation
  automatic_critical_error_action     = "Pause"
  automatic_critical_error_action_timeout = 30
  automatic_start_action              = var.automatic_start_action
  automatic_start_delay               = 0
  automatic_stop_action               = var.automatic_stop_action
  checkpoint_type                     = var.checkpoint_type
  guest_controlled_cache_types        = false
  high_memory_mapped_io_space         = 536870912
  lock_on_disconnect                  = "Off"
  low_memory_mapped_io_space          = 134217728
  memory_maximum_bytes                = each.value.memory_mb * 1024 * 1024
  memory_minimum_bytes                = each.value.memory_mb * 1024 * 1024
  memory_startup_bytes                = each.value.memory_mb * 1024 * 1024
  notes                              = ""
  processor_count                     = each.value.cpu_cores
  smart_paging_file_path             = "${var.vm_base_path}\\${each.value.name}"
  snapshot_file_location             = "${var.vm_base_path}\\${each.value.name}"
  static_memory                      = true

  # Dynamic hard disk drives - all disks go to controller 0 (default)
  dynamic "hard_disk_drives" {
    for_each = [
      for disk_idx, disk in each.value.disks : {
        controller_location = disk_idx  # Simple sequential location on controller 0
        path_key = "${each.key}_${disk_idx}"
        is_routeros = each.value.is_routeros != null ? each.value.is_routeros : false
      }
    ]
    content {
      controller_type                 = hard_disk_drives.value.is_routeros ? "Ide" : "Scsi"
      controller_number               = 0  # All disks on controller 0
      controller_location             = hard_disk_drives.value.controller_location
      path                            = hyperv_vhd.vm_disks[hard_disk_drives.value.path_key].path
      resource_pool_name              = "Primordial"
      support_persistent_reservations = false
      override_cache_attributes       = "Default"
      maximum_iops                    = 0
      minimum_iops                    = 0
      qos_policy_id                   = "00000000-0000-0000-0000-000000000000"
    }
  }
  # DVD drive for all VMs - placed after all disks on controller 0
  dvd_drives {
    controller_number   = each.value.is_routeros ? 1 : 0
    controller_location = each.value.is_routeros ? 0 : length(each.value.disks)
    path                = null  # No ISO mounted by default
    resource_pool_name  = "Primordial"
  }

  # VM Processor configuration
  vm_processor {
    compatibility_for_migration_enabled               = false
    compatibility_for_older_operating_systems_enabled = false
    enable_host_resource_protection                   = false
    expose_virtualization_extensions                  = false
    hw_thread_count_per_core                          = 0
    maximum                                           = 100
    maximum_count_per_numa_node                       = 16
    maximum_count_per_numa_socket                     = 1
    relative_weight                                   = 100
    reserve                                           = 0
  }
  # VM Firmware configuration (only for Generation 2 VMs)
  dynamic "vm_firmware" {
    for_each = (each.value.is_routeros ? 1 : var.hyperv_generation) == 2 ? [1] : []
    content {
      console_mode                    = "Default"
      enable_secure_boot              = "Off" # Before had this; need to disable because of my custom ISO images: each.value.is_routeros ? "Off" : "On"
      pause_after_boot_failure        = "Off"
      preferred_network_boot_protocol = "IPv4"
      secure_boot_template            = null # Before had this; need to disable because of my custom ISO images: each.value.is_routeros ? "OpenSourceShieldedVM" : "MicrosoftWindows"
      
      # Boot from DVD first
      boot_order {
        boot_type           = "DvdDrive"
        controller_number   = each.value.is_routeros ? 1 : 0
        controller_location = each.value.is_routeros ? 0 : length(each.value.disks)
      }
      
      # Boot from hard disks - dynamically add all disks to boot order
      dynamic "boot_order" {
        for_each = [
          for disk_idx, disk in each.value.disks : {
            controller_number = 0  # All disks on controller 0
            controller_location = disk_idx
            path = hyperv_vhd.vm_disks["${each.key}_${disk_idx}"].path
          }
        ]
        content {
          boot_type           = "HardDiskDrive"
          controller_number   = boot_order.value.controller_number
          controller_location = boot_order.value.controller_location
          path                = boot_order.value.path
        }
      }

      # Network boot for connected adapters only (those with switches)
      dynamic "boot_order" {
        for_each = [
          for adapter in each.value.network_adapters : adapter
          if adapter.name == "lab-wan" || adapter.name == "lab-lan"
        ]
        content {
          boot_type            = "NetworkAdapter"
          controller_location  = -1
          controller_number    = -1
          network_adapter_name = boot_order.value.name
          switch_name          = boot_order.value.name == "lab-wan" ? hyperv_network_switch.lab_wan.name : hyperv_network_switch.lab_lan.name
        }
      }
    }
  }

  # Network adapters - only connected adapters (lab-wan, lab-lan)
  dynamic "network_adaptors" {
    for_each = [
      for adapter in each.value.network_adapters : adapter
      if adapter.name == "lab-wan" || adapter.name == "lab-lan"
    ]
    content {
      name            = network_adaptors.value.name
      switch_name     = network_adaptors.value.name == "lab-wan" ? hyperv_network_switch.lab_wan.name : hyperv_network_switch.lab_lan.name
      management_os   = false
      dynamic_mac_address    = network_adaptors.value.static_mac_address != null ? false : true
      wait_for_ips           = false
      static_mac_address     = network_adaptors.value.static_mac_address
      is_legacy              = false
      vmmq_enabled           = true
      vmmq_queue_pairs       = 16
      vmq_weight             = 100
      iov_weight             = 0
      iov_interrupt_moderation                   = "Default"
      ipsec_offload_maximum_security_association = 512
      allow_teaming                              = "Off"
      packet_direct_moderation_count             = 64
      packet_direct_moderation_interval          = 1000000
    }
  }
  # Explicit dependency on network switches to ensure they exist before VM creation
  depends_on = [
    hyperv_network_switch.lab_wan,
    hyperv_network_switch.lab_lan
  ]
}

# Add disconnected network adapters using PowerShell
resource "null_resource" "disconnected_network_adapters" {
  for_each = {
    for vm_key, vm_config in module.shared_config.vm_configurations : vm_key => vm_config
    if length([for adapter in vm_config.network_adapters : adapter if adapter.name != "lab-wan" && adapter.name != "lab-lan"]) > 0
  }

  # This will run after the VM is created
  depends_on = [hyperv_machine_instance.vm]

  provisioner "local-exec" {
    command = "powershell.exe -ExecutionPolicy RemoteSigned -File ${replace(path.module, "/", "\\")}\\Add-DisconnectedAdapters.ps1 -VMName ${each.value.name} -AdapterNames ${join(",", [for adapter in each.value.network_adapters : adapter.name if adapter.name != "lab-wan" && adapter.name != "lab-lan"])} -StaticMacAddresses ${join(",", [for adapter in each.value.network_adapters : (adapter.static_mac_address != null ? adapter.static_mac_address : "") if adapter.name != "lab-wan" && adapter.name != "lab-lan"])}"
  }

  # Re-run if the VM is recreated or adapter configuration changes
  triggers = {
    vm_id = hyperv_machine_instance.vm[each.key].id
    disconnected_adapters = jsonencode([for adapter in each.value.network_adapters : adapter if adapter.name != "lab-wan" && adapter.name != "lab-lan"])
  }
}

# Workaround for Hyper-V provider network adapter issue
resource "null_resource" "fix_network_adapters" {
  for_each = {
    for vm_key, vm_config in module.shared_config.vm_configurations : vm_key => vm_config
    if !vm_config.is_routeros  # Only apply this fix to non-RouterOS VMs
  }
  # This will run after the VM is created
  depends_on = [hyperv_machine_instance.vm]

  provisioner "local-exec" {
    command = "powershell.exe -ExecutionPolicy RemoteSigned -File ${replace(path.module, "/", "\\")}\\Fix-NetworkAdapters.ps1 ${each.value.name} ${join(",", [for adapter in each.value.network_adapters : adapter.name if adapter.name == "lab-wan" || adapter.name == "lab-lan"])}"
  }

  # Re-run if the VM is recreated or connected adapter configuration changes
  triggers = {
    vm_id = hyperv_machine_instance.vm[each.key].id
    connected_adapters = jsonencode([for adapter in each.value.network_adapters : adapter if adapter.name == "lab-wan" || adapter.name == "lab-lan"])
  }
}

# Disable automatic checkpoints for all VMs
resource "null_resource" "disable_automatic_checkpoints" {
  for_each = module.shared_config.vm_configurations

  # This will run after the VM is created
  depends_on = [hyperv_machine_instance.vm]

  provisioner "local-exec" {
    command = "powershell.exe -ExecutionPolicy RemoteSigned -File ${replace(path.module, "/", "\\")}\\disable-checkpoints.ps1 -VMName ${each.value.name}"
  }

  # Re-run if the VM is recreated
  triggers = {
    vm_id = hyperv_machine_instance.vm[each.key].id
  }
}