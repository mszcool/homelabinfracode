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

  # Main disk (always present)
  hard_disk_drives {
    controller_type                 = each.value.is_routeros ? "Ide" : "Scsi"
    controller_number               = 0
    controller_location             = 0
    path                            = hyperv_vhd.main_disks[each.key].path
    resource_pool_name              = "Primordial"
    support_persistent_reservations = false
    override_cache_attributes       = "Default"
    maximum_iops                    = 0
    minimum_iops                    = 0
    qos_policy_id                   = "00000000-0000-0000-0000-000000000000"
  }
  # Optional second disk (only if more than 1 disk is configured)
  dynamic "hard_disk_drives" {
    for_each = length(each.value.disks) > 1 ? [1] : []
    content {
      controller_type                 = each.value.is_routeros ? "Ide" : "Scsi"
      controller_number               = 0
      controller_location             = 1
      path                            = hyperv_vhd.secondary_disks[each.key].path
      resource_pool_name              = "Primordial"
      support_persistent_reservations = false
      override_cache_attributes       = "Default"
      maximum_iops                    = 0
      minimum_iops                    = 0
      qos_policy_id                   = "00000000-0000-0000-0000-000000000000"
    }
  }
  # DVD drive for all VMs
  dvd_drives {
    controller_number   = each.value.is_routeros ? 1 : 0
    controller_location = each.value.is_routeros ? 0 : 2
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
        controller_location = each.value.is_routeros ? 0 : 2
      }
      
      # Boot from hard disk second
      boot_order {
        boot_type           = "HardDiskDrive"
        controller_number   = 0
        controller_location = 0
        path                = hyperv_vhd.main_disks[each.key].path
      }
      
      # Add second disk to boot order if it exists
      dynamic "boot_order" {
        for_each = length(each.value.disks) > 1 ? [1] : []
        content {
          boot_type           = "HardDiskDrive"
          controller_number   = 0
          controller_location = 1
          path                = hyperv_vhd.secondary_disks[each.key].path
        }
      }
      # Network boot for each adapter
      dynamic "boot_order" {
        for_each = each.value.network_adapters
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

  # Network adapters - dynamically create based on configuration
  dynamic "network_adaptors" {
    for_each = each.value.network_adapters
    content {
      name            = network_adaptors.value.name
      switch_name     = network_adaptors.value.name == "lab-wan" ? hyperv_network_switch.lab_wan.name : hyperv_network_switch.lab_lan.name
      management_os   = false
      dynamic_mac_address    = network_adaptors.value.static_mac_address != null ? false : true
      wait_for_ips           = false
      static_mac_address     = network_adaptors.value.static_mac_address
      is_legacy              = false # Before had this: each.value.is_routeros ? true : false
      vmmq_enabled           = true
      vmmq_queue_pairs       = 16 # Before had this: each.value.is_routeros ? null : 16
      vmq_weight             = 100  # Before had this: each.value.is_routeros ? null : 100
      iov_weight             = 0
      iov_interrupt_moderation                   = "Default"  # Before had this: each.value.is_routeros ? "Off" : "Default"
      ipsec_offload_maximum_security_association = 512  # Before had this: each.value.is_routeros ? 0 : 512
      allow_teaming                              = "Off"
      packet_direct_moderation_count             = 64  # Before had this: each.value.is_routeros ? null : 64
      packet_direct_moderation_interval          = 1000000  # Before had this: each.value.is_routeros ? null : 1000000
    }
  }
  # Explicit dependency on network switches to ensure they exist before VM creation
  depends_on = [
    hyperv_network_switch.lab_wan,
    hyperv_network_switch.lab_lan
  ]
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
    command = "powershell.exe -ExecutionPolicy RemoteSigned -File ${replace(path.module, "/", "\\")}\\Fix-NetworkAdapters.ps1 ${each.value.name} ${join(",", [for adapter in each.value.network_adapters : adapter.name])}"
  }

  # Re-run if the VM is recreated
  triggers = {
    vm_id = hyperv_machine_instance.vm[each.key].id
    adapters = jsonencode(each.value.network_adapters)
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