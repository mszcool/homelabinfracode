# Validate that SSH key and root password are only used with image-based VMs
resource "null_resource" "cloud_init_validation" {
  lifecycle {
    precondition {
      condition     = (var.ssh_public_key == "" && var.root_password == "") || var.image != ""
      error_message = "ssh_public_key and root_password can only be used with image-based VMs (when 'image' is specified). They are not compatible with ISO-based installations (when 'iso_volume_name' is specified)."
    }
  }
}

# Data Disks Storage Volumes
# Creates separate storage volumes for each data disk
resource "incus_storage_volume" "data_disks" {
  for_each = {
    for disk in local.data_disks_config :
    disk.name => disk
  }

  name         = "${var.instance_name}-${each.key}"
  pool         = each.value.pool
  project      = var.incus_project
  remote       = var.target_remote
  type         = "custom"
  content_type = "block"

  config = {
    "size" = "${each.value.size}GiB"
  }

  description = "Data disk '${each.key}' for ${var.instance_name}"
}

# Validate that either image or ISO is provided, but not both
resource "null_resource" "source_validation" {
  lifecycle {
    precondition {
      condition     = !local.source_validation.both_specified && !local.source_validation.neither_specified
      error_message = "Must specify either 'image' or 'iso_volume_name', but not both. For ISO-based VMs (like TrueNAS), leave 'image' empty. For standard VMs, specify 'image' and leave 'iso_volume_name' empty."
    }
  }
}

# Main VM Instance
resource "incus_instance" "vm" {
  name    = var.instance_name
  project = var.incus_project
  remote  = var.target_remote
  type    = var.type
  image   = var.image != "" ? var.image : null
  running = true

  # Profile provides base configuration (security, boot settings)
  profiles = [var.incus_profile]

  # Instance-specific configuration
  config = merge(
    {
      # CPU and Memory
      "limits.cpu"    = var.cpu_cores
      "limits.memory" = "${var.memory_gb}GB"

      # Boot settings
      "boot.autostart" = var.enable_boot_autostart ? "true" : "false"
    },
    # Disable secure boot for VMs (not applicable to containers)
    var.type == "virtual-machine" ? {
      "security.secureboot" = "false"
    } : {},
    # Add cloud-init user-data if SSH key or root password is provided
    # VMs use "cloud-init.user-data"; containers use "user.user-data"
    (var.ssh_public_key != "" || var.root_password != "") ? {
      (var.type == "container" ? "user.user-data" : "cloud-init.user-data") = "#cloud-config\n${local.cloud_init_user_data}"
    } : {}
  )

  # Root disk device (primary boot device)
  device {
    name = "root"
    type = "disk"

    properties = merge(
      {
        path = "/"
        pool = var.storage_pool
        size = "${var.system_disk_gb}GiB"
      },
      # boot.priority only applies to VMs
      var.type == "virtual-machine" ? { "boot.priority" = "1" } : {}
    )
  }

  # Primary network interface
  device {
    name = "eth0"
    type = "nic"

    properties = merge(
      {
        network = var.network_bridge
      },
      var.mac_address != "" ? { "hwaddr" = var.mac_address } : {}
    )
  }

  # ISO device (if ISO mounting is enabled and volume name is provided)
  # Assumes the ISO has been pre-imported via separate Ansible playbook
  dynamic "device" {
    for_each = var.iso_mounted && var.iso_volume_name != "" ? [1] : []
    content {
      name = "iso"
      type = "disk"

      properties = {
        source          = var.iso_volume_name
        pool            = var.storage_pool
        "boot.priority" = "2" # Boot from ISO second (fallback/installation)
      }
    }
  }

  # Data disk devices
  dynamic "device" {
    for_each = incus_storage_volume.data_disks
    content {
      name = "data-${device.key}"
      type = "disk"

      properties = {
        source = device.value.name
        pool   = device.value.pool
      }
    }
  }

  # PCIe device passthrough
  dynamic "device" {
    for_each = var.enable_pcie_passthrough ? [1] : []
    content {
      name = "pci-controller"
      type = "pci"

      properties = {
        address = var.pcie_controller
      }
    }
  }

  # Wait for instance to be ready
  # For image-based VMs: wait for agent to be ready
  # For containers: wait for IPv4 address (agent is not supported)
  # For ISO-based VMs: skip (agent won't be available during OS installation)
  dynamic "wait_for" {
    for_each = var.image != "" && var.iso_volume_name == "" ? [1] : []
    content {
      type = var.type == "container" ? "ipv4" : "agent"
    }
  }

  depends_on = [
    incus_storage_volume.data_disks
  ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Ansible post-provisioning
# Run an Ansible playbook after VM creation to configure the instance
# (install packages, push scripts, set up credentials, etc.).
#
# Extra vars are passed via --extra-vars with highest Ansible precedence,
# allowing Terraform-resolved values to override inventory group_vars.
# ──────────────────────────────────────────────────────────────────────────────
resource "null_resource" "ansible_configure" {
  count = var.ansible_playbook != null ? 1 : 0

  triggers = {
    instance_id = incus_instance.vm.name
    playbook    = var.ansible_playbook
    extra_vars  = jsonencode(var.ansible_extra_vars)
  }

  provisioner "local-exec" {
    command = <<-SCRIPT
      set -e
      cd ${jsonencode(var.repo_root_dir)}

      # Remove stale known_hosts entry for this IP so a recreated VM
      # with a new host key does not cause SSH to abort the connection.
      if [ -n "$TARGET_IP" ]; then
        ssh-keygen -R "$TARGET_IP" 2>/dev/null || true
      fi

      # Wait for SSH to become available on newly created VM
      if [ -n "$TARGET_IP" ]; then
        echo "Waiting for SSH on $TARGET_IP..."
        for i in $(seq 1 60); do
          ssh-keyscan -T 5 "$TARGET_IP" 2>/dev/null | grep -q . && break
          if [ "$i" -eq 60 ]; then echo "ERROR: SSH not available after 5 minutes"; exit 1; fi
          sleep 5
        done
      fi

      exec ansible-playbook \
        ${join(" ", concat(
          var.ansible_limit != null ? ["--limit", jsonencode(var.ansible_limit)] : [],
          [for dir in var.ansible_inventory_dirs : "-i ${jsonencode(dir)}"],
          var.ansible_instance_ip_var != null ? ["-e ${jsonencode("${var.ansible_instance_ip_var}=${incus_instance.vm.ipv4_address}")}"] : [],
          [for k, v in var.ansible_extra_vars : "-e ${jsonencode("${k}=${v}")}"],
          [jsonencode(var.ansible_playbook)]
        ))}
    SCRIPT

    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      TARGET_IP                 = var.ansible_instance_ip_var != null ? incus_instance.vm.ipv4_address : ""
      OP_SERVICE_ACCOUNT_TOKEN  = var.op_service_account_token
    }
  }

  depends_on = [incus_instance.vm]
}
