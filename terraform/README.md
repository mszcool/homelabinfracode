# Terraform Configuration

This directory contains the Terraform code for managing Incus infrastructure.

## ⚙️ Prerequisites

### System Requirements
- Terraform >= 1.0
- Incus CLI configured with remotes

### Cloud-Init User Configuration (Optional)

If using cloud-init to create users with passwords on image-based VMs, you need to pre-hash passwords before running Terraform:

**⚠️ Important:** Ubuntu 24.04 uses **yescrypt** hashing (not SHA-512). Use `mkpasswd -m yescrypt`.

**Generate and pass hashed password via environment variable:**
```bash
# Generate hash (choose one method)
HASH=$(mkpasswd -m yescrypt)  # Recommended for Ubuntu 24.04
# or: HASH=$(python3 -c "from passlib.hash import yescrypt; print(yescrypt.hash('YourPassword'))")

# IMPORTANT: Make sure ring0.tfvars has root_password = "" (empty default)
# This allows the environment variable to take precedence

# Set environment variable and deploy
export TF_VAR_root_password="$HASH"
terraform apply -var-file="../configs.private/ring0/ring0.tfvars"
```

**⚠️ Important:** 
- Terraform tfvars files **always take precedence** over environment variables
- Set `root_password = ""` in tfvars to allow environment variable to work
- Never commit actual password hashes to tfvars—use the environment variable approach instead
- Use **yescrypt** hashing, not SHA-512 (see `/etc/pam.d/common-password`)

See the [VM module README](./modules/vm/README.md#cloud-init-and-user-configuration) for detailed instructions.

## 📚 Documentation

All documentation has been moved to the [../docs/](../docs) directory for better organization.

**Quick Links:**
- [Getting Started →](../docs/00-START-HERE.md)
- [Quick Start (10 minutes) →](../docs/QUICKSTART.md)
- [Complete Index →](../docs/INDEX.md)
- [Architecture Overview →](../docs/TERRAFORM-README.md)

## 📁 Directory Structure

```
terraform/
├── versions.tf              # Terraform and provider versions
├── providers.tf             # Incus provider configuration
├── variables.tf             # Input variables
├── locals.tf                # Local computed values
├── main.tf                  # Root module instantiation
├── outputs.tf               # Output values
├── modules/
│   ├── vm/                  # Virtual machine module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── locals.tf
│   │   ├── versions.tf
│   │   └── README.md
│   └── container/           # Container module (future)
├── .gitignore               # Git ignore rules
└── README.md                # This file
```

## 🚀 Quick Start

1. **Initialize Terraform**
   ```bash
   cd terraform
   terraform init
   ```

2. **Review Configuration**
   ```bash
   terraform plan -var-file="../configs.private/ring0/ring0.tfvars"
   ```

3. **Deploy**
   ```bash
   terraform apply -var-file="../configs.private/ring0/ring0.tfvars"
   ```

## 📖 Learn More

- See [../docs/INDEX.md](../docs/INDEX.md) for navigation guide
- See [../docs/00-START-HERE.md](../docs/00-START-HERE.md) for introduction
- See [../docs/QUICKSTART.md](../docs/QUICKSTART.md) for hands-on guide
- See [modules/vm/README.md](modules/vm/README.md) for VM module details

## 🔒 Configuration Files

**Public Samples** (in `configs/`)
- Reference examples for different environments
- Safe to commit to public repository

**Actual Configurations** (in `configs.private/`)
- Your actual infrastructure definitions
- Protected in private Git submodule
- Contains sensitive information

**Important:** Always use `configs.private/` paths for actual deployments.

## 📋 Resources

### NOT Managed by Terraform
- Networks (pre-created via preseed)
- Storage Pools (pre-created via preseed)
- Projects (pre-created via preseed)
- Profiles (pre-created via preseed)

### Managed by Terraform
- Storage Volumes (ISO, data disks)
- VM Instances
- Container Instances
- Device Attachments
- PCIe Passthrough Configuration

---

**For complete documentation, see [../docs/INDEX.md](../docs/INDEX.md)**
