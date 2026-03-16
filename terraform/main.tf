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

  instance_name           = each.key
  target_remote           = each.value.target_remote
  incus_project           = var.incus_project
  incus_profile           = each.value.incus_profile
  storage_pool            = each.value.storage_pool
  type                    = each.value.type
  image                   = each.value.image
  cpu_cores               = each.value.cpu_cores
  memory_gb               = each.value.memory_gb
  system_disk_gb          = each.value.system_disk_gb
  network_bridge          = each.value.network_bridge
  mac_address             = each.value.mac_address
  iso_volume_name         = each.value.iso_volume_name
  iso_mounted             = each.value.iso_mounted
  enable_pcie_passthrough = each.value.enable_pcie_passthrough
  pcie_controller         = each.value.pcie_controller
  data_disks              = each.value.data_disks
  enable_boot_autostart   = each.value.enable_boot_autostart
  root_username           = each.value.root_username
  sudo_passwordless       = each.value.sudo_passwordless
  ssh_public_key          = each.value.ssh_public_key
  root_password = (
    each.value.root_password != "" ? each.value.root_password :
    contains(keys(local.op_vm_passwords), each.key) ? local.op_vm_passwords[each.key] :
    lookup(var.root_passwords, each.key, "")
  )
  tags = var.tags
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

# Workspace validation
# Ensures Terraform is running inside a named workspace (not "default").
# Each ring uses its own workspace for state isolation (e.g., ring0, ring1, ring2).
# This prevents accidentally applying a ring's tfvars against the wrong state file.
check "workspace_not_default" {
  assert {
    condition     = terraform.workspace != "default"
    error_message = "You must select a Terraform workspace before plan/apply. Run: terraform workspace select <ring> (e.g., ring0, ring1, ring2). See docs/terraform/QUICKSTART.md for details."
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# MAC Address Validation
# These check blocks run during plan but do NOT create any state resources.
# Convention: 00:16:3e:11:xx:xx = ring0, 00:16:3e:12:xx:xx = ring1, etc.
# ──────────────────────────────────────────────────────────────────────────────

# Validate MAC address format: must be 00:16:3e:XX:YY:ZZ (Xen/LXC OUI)
check "mac_address_format" {
  assert {
    condition = alltrue([
      for id, mac in local.all_mac_addresses :
      can(regex("^00:16:3e:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}$", lower(mac)))
    ])
    error_message = "All MAC addresses must use format 00:16:3e:XX:YY:ZZ (Xen/LXC OUI). Offending entries: ${join(", ", [
      for id, mac in local.all_mac_addresses :
      "${id}=${mac}" if !can(regex("^00:16:3e:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}$", lower(mac)))
    ])}."
  }
}

# Validate MAC prefix matches the ring (based on incus_project)
check "mac_address_ring_prefix" {
  assert {
    condition = local.expected_mac_prefix == "" ? true : alltrue([
      for id, mac in local.all_mac_addresses :
      startswith(lower(mac), lower(local.expected_mac_prefix))
    ])
    error_message = "MAC addresses must use prefix '${local.expected_mac_prefix}' for project '${var.incus_project}'. Offending entries: ${join(", ", [
      for id, mac in local.all_mac_addresses :
      "${id}=${mac}" if local.expected_mac_prefix != "" && !startswith(lower(mac), lower(local.expected_mac_prefix))
    ])}. See docs/terraform/MAC_ADDRESS_CONVENTION.md."
  }
}

# Validate no duplicate MAC addresses across all instances
check "mac_address_uniqueness" {
  assert {
    condition     = local.unique_mac_count == length(local.mac_values)
    error_message = "Duplicate MAC addresses detected. Each instance must have a unique MAC. All MACs: ${join(", ", [for id, mac in local.all_mac_addresses : "${id}=${mac}"])}."
  }
}

# Docker/OCI Container Instances
# Deploy OCI application containers (e.g., Mosquitto MQTT broker) using the docker_container module.
# Requires an OCI remote configured in Incus: incus remote add docker https://docker.io --protocol=oci
module "docker_container" {
  for_each = var.docker_containers

  source = "./modules/docker_container"

  instance_name         = each.key
  target_remote         = each.value.target_remote
  incus_project         = var.incus_project
  incus_profile         = each.value.incus_profile
  storage_pool          = each.value.storage_pool
  image                 = each.value.image
  cpu_cores             = each.value.cpu_cores
  memory_limit_mb       = each.value.memory_limit_mb
  root_disk_gb          = each.value.root_disk_gb
  network_bridge        = each.value.network_bridge
  mac_address           = each.value.mac_address
  enable_boot_autostart = each.value.enable_boot_autostart
  environment           = each.value.environment
  volumes               = each.value.volumes
  tags                  = var.tags
}
