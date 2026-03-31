locals {
  volume_map = { for v in var.volumes : v.name => v }

  # Check if the image reference includes a remote prefix (e.g., "docker:library/eclipse-mosquitto:2")
  has_remote_prefix = length(regexall("^[a-zA-Z][a-zA-Z0-9.-]*:.+", var.image)) > 0

  # Generate a stable alias for the OCI image on the target remote.
  # e.g., "docker:library/eclipse-mosquitto:2" → "oci-library-eclipse-mosquitto-2"
  oci_image_alias = local.has_remote_prefix ? "oci-${replace(regex("^[^:]+:(.+)$", var.image)[0], "/[^a-zA-Z0-9-]/", "-")}" : ""

  # If the image has a remote prefix, use the pre-copied alias; otherwise use the image directly
  resolved_image = local.has_remote_prefix ? local.oci_image_alias : var.image
}

# Pre-copy OCI image to the target Incus remote.
# The Incus Terraform provider cannot resolve OCI images (docker: remote) without
# a local Incus daemon running. This workaround uses the Incus CLI to copy the
# image to the target remote first, then the incus_instance references the local alias.
resource "null_resource" "oci_image_copy" {
  count = local.has_remote_prefix ? 1 : 0

  triggers = {
    image   = var.image
    remote  = var.target_remote
    project = var.incus_project
  }

  provisioner "local-exec" {
    command     = <<-EOT
      # First, remove any existing image with this alias in the target project
      # (ignore errors if it doesn't exist)
      incus image delete "$REMOTE:$ALIAS" --project "$PROJECT" 2>/dev/null || true
      # Copy the fresh image (--target-project targets the destination project)
      incus image copy "$IMAGE" "$REMOTE:" --alias "$ALIAS" --target-project "$PROJECT"
    EOT
    environment = {
      IMAGE   = var.image
      REMOTE  = var.target_remote
      ALIAS   = local.oci_image_alias
      PROJECT = var.incus_project
    }
  }
}

# Persistent storage volumes (filesystem type for container mounts)
resource "incus_storage_volume" "volumes" {
  for_each = local.volume_map

  name         = "${var.instance_name}-${each.key}"
  pool         = each.value.pool != "" ? each.value.pool : var.storage_pool
  project      = var.incus_project
  remote       = var.target_remote
  type         = "custom"
  content_type = "filesystem"

  config = {
    "size" = "${each.value.size_gb}GiB"
  }

  description = "Volume '${each.key}' for Docker container ${var.instance_name}"
}

# Flatten volume files into a single map for iteration.
# Key format: "volumeName/targetPath" to ensure uniqueness.
locals {
  volume_files = merge([
    for vol_name, vol in local.volume_map : {
      for f in vol.files :
      "${vol_name}/${f.target_path}" => {
        volume_name = vol_name
        pool        = vol.pool != "" ? vol.pool : var.storage_pool
        content     = f.content
        source_path = f.source_path
        target_path = f.target_path
        mode        = f.mode
        uid         = f.uid
        gid         = f.gid
      }
    }
  ]...)
}

# Seed files into storage volumes before the container starts.
# TODO: Replace with native incus_storage_volume "file" block once
# the provider releases that feature (available on main, not yet in v1.0.2).
resource "null_resource" "volume_file_seed" {
  for_each = local.volume_files

  triggers = {
    content     = each.value.content
    source_path = each.value.source_path
    target_path = each.value.target_path
    mode        = each.value.mode
  }

  provisioner "local-exec" {
    command = <<-EOT
      if [ -n "$CONTENT" ]; then
        echo "$CONTENT" | incus storage volume file push - \
          "$REMOTE:$POOL" "$VOLUME$TARGET_PATH" \
          --project "$PROJECT" --uid "$UID_VAL" --gid "$GID_VAL" --mode "$MODE" -p
      else
        incus storage volume file push "$SOURCE_PATH" \
          "$REMOTE:$POOL" "$VOLUME$TARGET_PATH" \
          --project "$PROJECT" --uid "$UID_VAL" --gid "$GID_VAL" --mode "$MODE" -p
      fi
    EOT

    environment = {
      CONTENT     = each.value.content
      SOURCE_PATH = each.value.source_path
      TARGET_PATH = each.value.target_path
      MODE        = each.value.mode
      UID_VAL     = tostring(each.value.uid)
      GID_VAL     = tostring(each.value.gid)
      REMOTE      = var.target_remote
      POOL        = each.value.pool
      VOLUME      = "${var.instance_name}-${each.value.volume_name}"
      PROJECT     = var.incus_project
    }
  }

  depends_on = [incus_storage_volume.volumes]
}

# Docker/OCI container instance
resource "incus_instance" "container" {
  name    = var.instance_name
  project = var.incus_project
  remote  = var.target_remote
  type    = "container"
  image   = local.resolved_image
  running = var.running

  profiles = [var.incus_profile]

  config = merge(
    {
      "limits.cpu"     = tostring(var.cpu_cores)
      "limits.memory"  = "${var.memory_limit_mb}MB"
      "boot.autostart" = var.enable_boot_autostart ? "true" : "false"
    },
    # Pass environment variables to the OCI container
    { for k, v in var.environment : "environment.${k}" => v }
  )

  # Root disk — specifies the storage pool (and optional size limit) for the container rootfs
  device {
    name = "root"
    type = "disk"
    properties = merge(
      {
        path = "/"
        pool = var.storage_pool
      },
      var.root_disk_gb > 0 ? { "size" = "${var.root_disk_gb}GiB" } : {}
    )
  }

  # Primary network interface — bridged to the LAN for direct IP access
  device {
    name = "eth0"
    type = "nic"
    properties = merge(
      { network = var.network_bridge },
      var.mac_address != "" ? { hwaddr = var.mac_address } : {}
    )
  }

  # Persistent volume mounts
  dynamic "device" {
    for_each = local.volume_map
    content {
      name = "vol-${device.key}"
      type = "disk"
      properties = {
        source = "${var.instance_name}-${device.key}"
        pool   = device.value.pool != "" ? device.value.pool : var.storage_pool
        path   = device.value.path
      }
    }
  }

  depends_on = [incus_storage_volume.volumes, null_resource.oci_image_copy, null_resource.volume_file_seed]
}

# ──────────────────────────────────────────────────────────────────────────────
# Ansible post-provisioning
# Run an Ansible playbook after container creation to push production config
# (credentials, mapping files, etc.) and start/restart the container.
#
# Extra vars are passed via --extra-vars JSON with highest Ansible precedence,
# allowing Terraform-resolved values (e.g., container IPs) to override
# inventory group_vars without modifying any files.
# ──────────────────────────────────────────────────────────────────────────────
resource "null_resource" "ansible_configure" {
  count = var.ansible_playbook != null ? 1 : 0

  triggers = {
    instance_id = incus_instance.container.name
    playbook    = var.ansible_playbook
    extra_vars  = jsonencode(var.ansible_extra_vars)
  }

  provisioner "local-exec" {
    command = join(" ", concat(
      [
        "set -e && cd ${jsonencode(var.repo_root_dir)} &&",
        "ansible-playbook",
      ],
      var.ansible_limit != null ? ["--limit", jsonencode(var.ansible_limit)] : [],
      [for dir in var.ansible_inventory_dirs : "-i ${jsonencode(dir)}"],
      [for k, v in var.ansible_extra_vars : "-e ${jsonencode("${k}=${v}")}"],
      [jsonencode(var.ansible_playbook)]
    ))

    environment = {
      OP_SERVICE_ACCOUNT_TOKEN = var.op_service_account_token
    }
  }

  depends_on = [incus_instance.container]
}
