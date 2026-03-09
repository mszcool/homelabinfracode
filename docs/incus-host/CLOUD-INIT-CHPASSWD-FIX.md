# Cloud-Init chpasswd Module Fix

> **Context**: This is a reference document for the Incus compute node setup. For the full setup workflow, see [Ring 0 Setup](../04-ring0-setup.md). For Terraform VM provisioning, see [Architecture Overview](../02-architecture.md).

## The Problem

Previously, we were trying to set passwords directly in the `users` module using the `passwd` field, which was not working properly with yescrypt hashes.

## The Solution

Use cloud-init's dedicated **`chpasswd` module** which is specifically designed to handle password authentication with proper hash format detection.

## How It Works

The `chpasswd` module:
- Automatically detects the password hash format (yescrypt, SHA-512, MD5, etc.)
- Properly applies hashes to existing users
- Is the official cloud-init way to change passwords

## Generated Cloud-Init Configuration

The module now generates cloud-init YAML like this:

```yaml
users:
- name: yourdomainadmin
  shell: /bin/bash
  sudo:
  - ALL=(ALL) NOPASSWD:ALL
  ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1y...

chpasswd:
  list:
  - yourdomainadmin:$y$j9T$QoxxlrhWpPrL.RHUrBXtL.$yxOB1Yw6VIcfnmsVdhNWeclhHz6cIR6RxrMqD.Dozh4
  expire: false
```

This configuration:
1. Creates the user with SSH key support
2. Applies the yescrypt hashed password using the `chpasswd` module
3. Sets `expire: false` so password change is not required on first login

## Usage

Nothing changes from the user perspective:

```bash
# Generate yescrypt hash
HASH=$(mkpasswd -m yescrypt)

# Set environment variable
export TF_VAR_root_password="$HASH"

# Deploy
terraform apply --var-file="../configs.private/envprod/ring0.tfvars"
```

## Why This Works

- Cloud-init's `chpasswd` module is designed for this exact use case
- It properly handles hash format detection
- It correctly applies yescrypt hashes to /etc/shadow
- It integrates seamlessly with the `users` module

## References

- Cloud-init Set Passwords module: https://docs.cloud-init.io/en/latest/reference/modules.html#set-passwords
- Cloud-init chpasswd documentation shows it accepts both plaintext and hashed passwords
- Hash format is automatically detected by cloud-init
