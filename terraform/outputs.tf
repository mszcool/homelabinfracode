output "vms" {
  description = "Information about created VMs"
  value = {
    for name, module_output in module.vm :
    name => {
      instance_name   = module_output.instance_name
      ipv4_address    = module_output.instance_ipv4_address
      ipv6_address    = module_output.instance_ipv6_address
      status          = module_output.instance_status
      data_disk_names = module_output.data_disk_names
    }
  }
}

output "docker_containers" {
  description = "Information about created Docker/OCI containers"
  value = merge(
    {
      for name, module_output in module.docker_container :
      name => {
        instance_name = module_output.instance_name
        ipv4_address  = module_output.instance_ipv4_address
        ipv6_address  = module_output.instance_ipv6_address
        status        = module_output.instance_status
        volume_names  = module_output.volume_names
      }
    },
    {
      for name, module_output in module.docker_container_with_deps :
      name => {
        instance_name = module_output.instance_name
        ipv4_address  = module_output.instance_ipv4_address
        ipv6_address  = module_output.instance_ipv6_address
        status        = module_output.instance_status
        volume_names  = module_output.volume_names
      }
    }
  )
}
