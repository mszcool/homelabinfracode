# Incus Virtual Machines Configuration

# RouterOS VM
resource "incus_instance" "routeros" {
  name  = local.vm_configurations["routeros"].name
  image = var.routeros_image
  type  = "virtual-machine"

  config = {
    "limits.cpu"    = local.vm_configurations["routeros"].cpu_cores
    "limits.memory" = "${local.vm_configurations["routeros"].memory_mb}MB"
  }

  # Main disk
  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = "default"
      size = "${local.vm_configurations["routeros"].disks[0].size_gb}GB"
    }
  }

  # Network adapters
  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = incus_network.lab_wan.name
    }
  }

  device {
    name = "eth1" 
    type = "nic"
    properties = {
      network = incus_network.lab_lan.name
    }
  }
}

# Incus Single Disk VM
resource "incus_instance" "incus_single_disk" {
  name  = local.vm_configurations["incus_single_disk"].name
  image = var.default_image
  type  = "virtual-machine"

  config = {
    "limits.cpu"    = local.vm_configurations["incus_single_disk"].cpu_cores
    "limits.memory" = "${local.vm_configurations["incus_single_disk"].memory_mb}MB"
  }

  # Main disk
  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = "default"
      size = "${local.vm_configurations["incus_single_disk"].disks[0].size_gb}GB"
    }
  }

  # Network adapter
  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = incus_network.lab_lan.name
    }
  }
}

# Incus Dual Disk VM
resource "incus_instance" "incus_dual_disk" {
  name  = local.vm_configurations["incus_dual_disk"].name
  image = var.default_image
  type  = "virtual-machine"

  config = {
    "limits.cpu"    = local.vm_configurations["incus_dual_disk"].cpu_cores
    "limits.memory" = "${local.vm_configurations["incus_dual_disk"].memory_mb}MB"
  }

  # Main disk
  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = "default"
      size = "${local.vm_configurations["incus_dual_disk"].disks[0].size_gb}GB"
    }
  }

  # Second disk
  device {
    name = "data"
    type = "disk"
    properties = {
      path = "/data"
      pool = "default"
      size = "${local.vm_configurations["incus_dual_disk"].disks[1].size_gb}GB"
    }
  }

  # Network adapter
  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = incus_network.lab_lan.name
    }
  }
}

# Test Client VM
resource "incus_instance" "test_client" {
  name  = local.vm_configurations["test_client"].name
  image = var.default_image
  type  = "virtual-machine"

  config = {
    "limits.cpu"    = local.vm_configurations["test_client"].cpu_cores
    "limits.memory" = "${local.vm_configurations["test_client"].memory_mb}MB"
  }

  # Main disk
  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = "default"
      size = "${local.vm_configurations["test_client"].disks[0].size_gb}GB"
    }
  }

  # Network adapter
  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = incus_network.lab_lan.name
    }
  }
}
