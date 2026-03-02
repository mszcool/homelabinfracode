# 1Password integration for per-VM root passwords
# Each VM can specify its own root_pwd_vault, root_pwd_vault_item, and
# root_pwd_vault_field to fetch its hashed password (yescrypt) from a
# dedicated 1Password item.
data "onepassword_item" "vm_password" {
  for_each = {
    for name, vm in var.vms : name => vm
    if vm.root_pwd_vault_item != "" && vm.root_password == ""
  }

  vault = each.value.root_pwd_vault != "" ? each.value.root_pwd_vault : var.op_vault_name
  title = each.value.root_pwd_vault_item
}

# Resolve the per-VM hashed password from the 1Password item.
# When root_pwd_vault_field is "password", use the item's built-in password attribute.
# Otherwise, search the item's sections for a custom field with that name.
locals {
  op_vm_passwords = {
    for name, item in data.onepassword_item.vm_password : name => (
      var.vms[name].root_pwd_vault_field == "password"
        ? item.password
        : try(
            one([
              for section in item.section :
              one([for f in section.field : f.value if f.label == var.vms[name].root_pwd_vault_field])
            ]),
            ""
          )
    )
  }
}

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
  root_username            = each.value.root_username
  ssh_public_key           = each.value.ssh_public_key
  root_password            = (
    each.value.root_password != "" ? each.value.root_password :
    contains(keys(local.op_vm_passwords), each.key) ? local.op_vm_passwords[each.key] :
    lookup(var.root_passwords, each.key, "")
  )
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
