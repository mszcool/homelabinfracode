# Hyper-V Virtual Machines Configuration

# RouterOS VM
resource "hyperv_machine_instance" "routeros" {
  
  depends_on = [hyperv_vhd.routeros_disk]

  name                   = local.vm_configurations["routeros"].name
  generation             = 1  # Generation 1 for RouterOS compatibility
  automatic_critical_error_action = "Pause"
  automatic_critical_error_action_timeout = 30
  automatic_start_action = var.automatic_start_action
  automatic_start_delay = 0
  automatic_stop_action  = var.automatic_stop_action
  checkpoint_type        = var.checkpoint_type
  guest_controlled_cache_types = false
  high_memory_mapped_io_space = 536870912
  lock_on_disconnect     = "Off"
  low_memory_mapped_io_space = 134217728
  memory_maximum_bytes   = local.vm_configurations["routeros"].memory_mb * 1024 * 1024
  memory_minimum_bytes   = local.vm_configurations["routeros"].memory_mb * 1024 * 1024
  memory_startup_bytes   = local.vm_configurations["routeros"].memory_mb * 1024 * 1024
  notes                  = "RouterOS Virtual Machine"
  processor_count        = local.vm_configurations["routeros"].cpu_cores
  smart_paging_file_path = "${var.vm_base_path}\\PagingFiles"
  snapshot_file_location = "${var.vm_base_path}\\Snapshots"
  static_memory          = true
  
  # Main disk
  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path               = "${var.vm_base_path}\\${local.vm_configurations["routeros"].name}\\${local.vm_configurations["routeros"].name}.vhdx"
    ##disk_number        = 0
    resource_pool_name = ""
    support_persistent_reservations = false
    override_cache_attributes = "Default"
  }

  # Network adapters
  network_adaptors {
    name                = "lab-wan"
    switch_name         = hyperv_network_switch.lab_wan.name
    management_os       = false
    is_legacy           = false
    dynamic_mac_address = true
  }

  network_adaptors {
    name                = "lab-lan"
    switch_name         = hyperv_network_switch.lab_lan.name
    management_os       = false
    is_legacy           = false
    dynamic_mac_address = true
  }
}

# Create VHDX for RouterOS
resource "hyperv_vhd" "routeros_disk" {
  path                 = "${var.vm_base_path}\\${local.vm_configurations["routeros"].name}\\${local.vm_configurations["routeros"].name}.vhdx"
  size                 = local.vm_configurations["routeros"].disks[0].size_gb * 1024 * 1024 * 1024
  block_size           = 0
  logical_sector_size  = 0
  physical_sector_size = 0
  vhd_type             = var.vhd_type
}

# Incus Single Disk VM
resource "hyperv_machine_instance" "incus_single_disk" {

  depends_on = [hyperv_vhd.incus_single_disk_main]

  name                   = local.vm_configurations["incus_single_disk"].name
  generation             = 2
  automatic_critical_error_action = "Pause"
  automatic_critical_error_action_timeout = 30
  automatic_start_action = "Nothing"
  automatic_start_delay = 0
  automatic_stop_action  = "ShutDown"
  checkpoint_type        = "Production"
  guest_controlled_cache_types = false
  high_memory_mapped_io_space = 536870912
  lock_on_disconnect     = "Off"
  low_memory_mapped_io_space = 134217728
  memory_maximum_bytes   = local.vm_configurations["incus_single_disk"].memory_mb * 1024 * 1024
  memory_minimum_bytes   = local.vm_configurations["incus_single_disk"].memory_mb * 1024 * 1024
  memory_startup_bytes   = local.vm_configurations["incus_single_disk"].memory_mb * 1024 * 1024
  notes                  = "Incus Single Disk Virtual Machine"
  processor_count        = local.vm_configurations["incus_single_disk"].cpu_cores
  smart_paging_file_path = "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V"
  snapshot_file_location = "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V"
  static_memory          = true

  # Main disk
  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path               = "C:\\VMs\\${local.vm_configurations["incus_single_disk"].name}\\${local.vm_configurations["incus_single_disk"].name}.vhdx"
    ##disk_number        = 0
    resource_pool_name = ""
    support_persistent_reservations = false
    override_cache_attributes = "Default"
    # Add these QoS parameters explicitly
    maximum_iops       = 0
    minimum_iops       = 0
    qos_policy_id      = ""
  }

  # Network adapter
  network_adaptors {
    name                = "lab-lan"
    switch_name         = hyperv_network_switch.lab_lan.name
    management_os       = false
    is_legacy           = false
    dynamic_mac_address = true
  }
}

# Create VHDX for Incus Single Disk
resource "hyperv_vhd" "incus_single_disk_main" {
  path                 = "C:\\VMs\\${local.vm_configurations["incus_single_disk"].name}\\${local.vm_configurations["incus_single_disk"].name}.vhdx"
  size                 = local.vm_configurations["incus_single_disk"].disks[0].size_gb * 1024 * 1024 * 1024
  block_size           = 0
  logical_sector_size  = 0
  physical_sector_size = 0
  vhd_type             = "Dynamic"
}

# Incus Dual Disk VM
resource "hyperv_machine_instance" "incus_dual_disk" {

  depends_on = [hyperv_vhd.incus_dual_disk_main, hyperv_vhd.incus_dual_disk_data]

  name                   = local.vm_configurations["incus_dual_disk"].name
  generation             = 2
  automatic_critical_error_action = "Pause"
  automatic_critical_error_action_timeout = 30
  automatic_start_action = "Nothing"
  automatic_start_delay = 0
  automatic_stop_action  = "ShutDown"
  checkpoint_type        = "Production"
  guest_controlled_cache_types = false
  high_memory_mapped_io_space = 536870912
  lock_on_disconnect     = "Off"
  low_memory_mapped_io_space = 134217728
  memory_maximum_bytes   = local.vm_configurations["incus_dual_disk"].memory_mb * 1024 * 1024
  memory_minimum_bytes   = local.vm_configurations["incus_dual_disk"].memory_mb * 1024 * 1024
  memory_startup_bytes   = local.vm_configurations["incus_dual_disk"].memory_mb * 1024 * 1024
  notes                  = "Incus Dual Disk Virtual Machine"
  processor_count        = local.vm_configurations["incus_dual_disk"].cpu_cores
  smart_paging_file_path = "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V"
  snapshot_file_location = "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V"
  static_memory          = true

  # Main disk
  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path               = "C:\\VMs\\${local.vm_configurations["incus_dual_disk"].name}\\${local.vm_configurations["incus_dual_disk"].name}.vhdx"
    ##disk_number        = 0
    resource_pool_name = ""
    support_persistent_reservations = false
    override_cache_attributes = "Default"
  }

  # Second disk
  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 1
    path               = "C:\\VMs\\${local.vm_configurations["incus_dual_disk"].name}\\${local.vm_configurations["incus_dual_disk"].name}-data.vhdx"
    ##disk_number        = 1
    resource_pool_name = ""
    support_persistent_reservations = false
    override_cache_attributes = "Default"
    # Add these QoS parameters explicitly
    maximum_iops       = 0
    minimum_iops       = 0
    qos_policy_id      = ""
  }

  # Network adapter
  network_adaptors {
    name                = "lab-lan"
    switch_name         = hyperv_network_switch.lab_lan.name
    management_os       = false
    is_legacy           = false
    dynamic_mac_address = true
  }
}

# Create VHDXs for Incus Dual Disk
resource "hyperv_vhd" "incus_dual_disk_main" {
  path                 = "C:\\VMs\\${local.vm_configurations["incus_dual_disk"].name}\\${local.vm_configurations["incus_dual_disk"].name}.vhdx"
  size                 = local.vm_configurations["incus_dual_disk"].disks[0].size_gb * 1024 * 1024 * 1024
  block_size           = 0
  logical_sector_size  = 0
  physical_sector_size = 0
  vhd_type             = "Dynamic"
}

resource "hyperv_vhd" "incus_dual_disk_data" {
  path                 = "C:\\VMs\\${local.vm_configurations["incus_dual_disk"].name}\\${local.vm_configurations["incus_dual_disk"].name}-data.vhdx"
  size                 = local.vm_configurations["incus_dual_disk"].disks[1].size_gb * 1024 * 1024 * 1024
  block_size           = 0
  logical_sector_size  = 0
  physical_sector_size = 0
  vhd_type             = "Dynamic"
}

# Test Client VM
resource "hyperv_machine_instance" "test_client" {

  depends_on = [hyperv_vhd.test_client_disk]

  name                   = local.vm_configurations["test_client"].name
  generation             = 2
  automatic_critical_error_action = "Pause"
  automatic_critical_error_action_timeout = 30
  automatic_start_action = "Nothing"
  automatic_start_delay = 0
  automatic_stop_action  = "ShutDown"
  checkpoint_type        = "Production"
  guest_controlled_cache_types = false
  high_memory_mapped_io_space = 536870912
  lock_on_disconnect     = "Off"
  low_memory_mapped_io_space = 134217728
  memory_maximum_bytes   = local.vm_configurations["test_client"].memory_mb * 1024 * 1024
  memory_minimum_bytes   = local.vm_configurations["test_client"].memory_mb * 1024 * 1024
  memory_startup_bytes   = local.vm_configurations["test_client"].memory_mb * 1024 * 1024
  notes                  = "Test Client Virtual Machine"
  processor_count        = local.vm_configurations["test_client"].cpu_cores
  smart_paging_file_path = "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V"
  snapshot_file_location = "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V"
  static_memory          = true
  # Main disk
  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path               = "C:\\VMs\\${local.vm_configurations["test_client"].name}\\${local.vm_configurations["test_client"].name}.vhdx"
    ##disk_number        = 0
    resource_pool_name = ""
    support_persistent_reservations = false
    override_cache_attributes = "Default"
    # Add these QoS parameters explicitly
    maximum_iops       = 0
    minimum_iops       = 0
    qos_policy_id      = ""
  }

  # Network adapter
  network_adaptors {
    name                = "lab-lan"
    switch_name         = hyperv_network_switch.lab_lan.name
    management_os       = false
    is_legacy           = false
    dynamic_mac_address = true
  }
}

# Create VHDX for Test Client
resource "hyperv_vhd" "test_client_disk" {
  path                 = "C:\\VMs\\${local.vm_configurations["test_client"].name}\\${local.vm_configurations["test_client"].name}.vhdx"
  size                 = local.vm_configurations["test_client"].disks[0].size_gb * 1024 * 1024 * 1024
  block_size           = 0
  logical_sector_size  = 0
  physical_sector_size = 0
  vhd_type             = "Dynamic"
}
