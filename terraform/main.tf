# VM Instances
# Deploy virtual machines using the vm module
module "vm" {
  for_each = var.vms

  source = "./modules/vm"

  instance_name            = each.key
  target_remote            = each.value.target_remote
  incus_project            = each.value.incus_project
  incus_profile            = each.value.incus_profile
  storage_pool             = each.value.storage_pool
  type                     = each.value.type
  image                    = each.value.image
  cpu_cores                = each.value.cpu_cores
  memory_gb                = each.value.memory_gb
  system_disk_gb           = each.value.system_disk_gb
  network_bridge           = each.value.network_bridge
  mac_address              = each.value.mac_address
  iso_volume_name          = each.value.iso_volume_name
  iso_mounted              = each.value.iso_mounted
  enable_pcie_passthrough  = each.value.enable_pcie_passthrough
  pcie_controller          = each.value.pcie_controller
  data_disks               = each.value.data_disks
  enable_boot_autostart    = each.value.enable_boot_autostart
  tags                     = var.tags
}

# Container Instances (future module)
# Placeholder for container management module
# module "container" {
#   for_each = var.containers
#   
#   source = "./modules/container"
#   
#   instance_name = each.key
#   # ... additional configuration
# }
