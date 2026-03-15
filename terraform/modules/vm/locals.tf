locals {
  # Validate that required parameters are not empty where needed
  iso_provided   = var.iso_volume_name != ""
  image_provided = var.image != ""

  # Validate that either image or iso is provided, but not both
  source_validation = {
    both_specified    = local.image_provided && local.iso_provided
    neither_specified = !local.image_provided && !local.iso_provided
  }

  # Validate pcie configuration
  pcie_required = var.enable_pcie_passthrough && var.pcie_controller == ""

  # Data disks should only be used when pcie passthrough is disabled
  data_disks_config = var.enable_pcie_passthrough ? [] : var.data_disks

  # The root_password variable should already be hashed (yescrypt format: $y$...)
  # Users must provide the hashed password via TF_VAR_root_password
  # Ubuntu 24.04 uses yescrypt by default; see /etc/pam.d/common-password
  # See variables.tf documentation for examples on how to generate the hash
  hashed_password = var.root_password

  # Build users list conditionally
  # Only include properties that are actually set (no null values)
  cloud_init_users = (var.image != "" && (var.ssh_public_key != "" || var.root_password != "")) ? [
    merge(
      {
        name        = var.root_username
        sudo        = ["ALL=(ALL) NOPASSWD:ALL"]
        shell       = "/bin/bash"
        lock_passwd = false
      },
      # Only add SSH keys if provided (users module property)
      var.ssh_public_key != "" ? { ssh_authorized_keys = [var.ssh_public_key] } : {}
    )
  ] : []

  # Build the cloud-init configuration using the chpasswd module
  # The chpasswd module is specifically designed to handle password authentication
  # It supports both plaintext and hashed passwords (automatically detected by format)
  # This will be passed directly to cloud-init via cloud-init.user-data
  cloud_init_user_data = (var.image != "") ? yamlencode(merge(
    # Base configuration (package updates, SSH setup, users, and key-only auth)
    {
      package_update  = true
      package_upgrade = true
      packages        = ["openssh-server"]
      ssh_pwauth      = false
      users           = local.cloud_init_users
      # Drop an sshd config snippet that enforces key-only authentication
      write_files = [
        {
          path        = "/etc/ssh/sshd_config.d/50-no-password-auth.conf"
          content     = "PasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\n"
          owner       = "root:root"
          permissions = "0644"
        }
      ]
      # Restart sshd after write_files to pick up the new config
      runcmd = [
        ["systemctl", "restart", "ssh"]
      ]
    },
    # Add chpasswd section for password authentication if password is provided
    local.hashed_password != "" ? {
      chpasswd = {
        expire = false
        users = [
          {
            name     = var.root_username
            password = local.hashed_password
          }
        ]
      }
    } : {}
  )) : ""
}
