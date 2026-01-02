# Terraform Configuration

This directory contains the Terraform code for managing Incus infrastructure.

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
