# Incus Virtual Machines Configuration

# Dynamic VM creation based on vm_configurations
resource "incus_instance" "vm" {
  for_each = local.vm_configurations
  
  name  = each.value.name
  image = each.key == "routeros" ? var.routeros_image : var.default_image
  type  = "virtual-machine"

  config = {
    "limits.cpu"    = each.value.cpu_cores
    "limits.memory" = "${each.value.memory_mb}MB"
  }

  # Main disk (always present)
  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = "default"
      size = "${each.value.disks[0].size_gb}GB"
    }
  }

  # Optional second disk (only if more than 1 disk is configured)
  dynamic "device" {
    for_each = length(each.value.disks) > 1 ? [each.value.disks[1]] : []
    content {
      name = device.value.name
      type = "disk"
      properties = {
        path = "/${device.value.name}"
        pool = "default"
        size = "${device.value.size_gb}GB"
      }
    }
  }

  # Network adapters - dynamically create based on configuration
  dynamic "device" {
    for_each = each.value.network_adapters
    content {
      name = "eth${index(each.value.network_adapters, device.value)}"
      type = "nic"
      properties = {
        network = device.value == "lab-wan" ? incus_network.lab_wan.name : incus_network.lab_lan.name
      }
    }
  }
}
