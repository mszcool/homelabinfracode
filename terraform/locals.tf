locals {
  # Convert instance names to resource-safe identifiers
  vm_names = {
    for name, config in var.vms :
    name => {
      resource_id = replace(lower(name), "/[^a-z0-9_-]/", "_")
      config      = config
    }
  }

  container_names = {
    for name, config in var.containers :
    name => {
      resource_id = replace(lower(name), "/[^a-z0-9_-]/", "_")
      config      = config
    }
  }

  docker_container_names = {
    for name, config in var.docker_containers :
    name => {
      resource_id = replace(lower(name), "/[^a-z0-9_-]/", "_")
      config      = config
    }
  }

  # MAC address validation helpers
  # Collect all non-empty MAC addresses with their source for validation
  all_mac_addresses = merge(
    { for name, vm in var.vms : "vm/${name}" => vm.mac_address if vm.mac_address != "" },
    { for name, dc in var.docker_containers : "docker/${name}" => dc.mac_address if dc.mac_address != "" }
  )

  # Expected MAC prefix for the current ring (based on incus_project)
  expected_mac_prefix = lookup(var.mac_prefix_by_project, var.incus_project, "")

  # Detect duplicate MAC addresses
  mac_values       = values(local.all_mac_addresses)
  unique_mac_count = length(toset(local.mac_values))
}
