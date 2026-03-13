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
}
