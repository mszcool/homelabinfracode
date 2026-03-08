# Terraform Incus Refactor — Documentation Index

> **Context**: This directory contains detailed Terraform reference documentation. For the master architecture overview (including Terraform's role), see [Architecture — Terraform](../02-architecture.md). For Ring 0 setup including Terraform provisioning, see [Ring 0 Setup](../04-ring0-setup.md). For environment setup (Terraform installation), see [Environment Setup](../03-environment-setup.md).
>
> **Path conventions**: Tfvars files are at `configs/envtest/ring0.tfvars` (test) or `configs.private/envprod/ring0.tfvars` (production). The 1Password Terraform provider (`1Password/onepassword`) resolves secrets at plan/apply time. See [Architecture](../02-architecture.md) for the full model.

This document helps you navigate the Terraform documentation.

## Quick Navigation

### For Different Audiences

**Project Manager / Decision Maker**
→ Start with [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md) (5 min read)

**Developer / DevOps Engineer**
→ Start with [QUICKSTART.md](QUICKSTART.md) (10 min hands-on)
→ Then [TERRAFORM-README.md](TERRAFORM-README.md) (understand architecture)
→ Then [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) (plan implementation)
→ Reference: [../../terraform/modules/vm/README.md](../../terraform/modules/vm/README.md) (module details)

**Architect / Infrastructure Designer**
→ Start with [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md)
→ Then [ARCHITECTURE.md](ARCHITECTURE.md) (detailed diagrams)
→ Then [TERRAFORM-README.md](TERRAFORM-README.md) (implementation details)

---

## File Organization

### Configuration Files (in `terraform/`)

```
terraform/
├── versions.tf              Terraform version constraints
├── providers.tf             Incus + 1Password provider authentication
├── variables.tf             Input variable definitions
├── locals.tf                Local computed values
├── main.tf                  Root module instantiation
└── outputs.tf               Infrastructure outputs
```

**Usage:** These are the core configuration files. Start by running:
```bash
cd terraform
terraform init
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
```

> **Note:** Variable files are organized in `configs/envtest/` (test samples) and `configs.private/envprod/` (actual production configs).
> See [TFVARS_ORGANIZATION.md](TFVARS_ORGANIZATION.md) for details.

### Module Files (Reusable Components)

```
modules/vm/
├── main.tf                  Core VM resources
├── variables.tf             VM input parameters
├── outputs.tf               VM output values
├── locals.tf                Internal VM logic
├── versions.tf              Module dependencies
└── README.md                Module documentation
```

**Usage:** The VM module is self-contained. Use for creating any VM:
```hcl
module "my_vm" {
  source = "./modules/vm"
  instance_name = "my-vm"
  # ... other parameters
}
```

### Variable Files (Environment Configuration)

**Test Samples** (reference and documentation):
```
configs/envtest/
├── ring0.tfvars             Infrastructure layer examples (TrueNAS, storage)
├── ring1.tfvars             Application layer examples
└── ring2.tfvars             User services examples
```

**Production Configs** (actual deployment):
```
configs.private/envprod/
├── ring0.tfvars             YOUR actual Ring 0 configuration
├── ring1.tfvars             YOUR actual Ring 1 configuration
└── ring2.tfvars             YOUR actual Ring 2 configuration
```

**Usage:** Always use configs.private for real deployment:
```bash
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
terraform apply -var-file="../configs.private/envprod/ring1.tfvars"
```

> See [TFVARS_ORGANIZATION.md](TFVARS_ORGANIZATION.md) for security rationale and detailed explanation.

### Documentation Files (Reference)

| File | Purpose | Read Time | Audience |
|------|---------|-----------|----------|
| [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md) | Overview of entire refactor | 10 min | Everyone |
| [QUICKSTART.md](QUICKSTART.md) | Hands-on 10-minute setup | 10 min | Developers |
| [TERRAFORM-README.md](TERRAFORM-README.md) | Architecture and usage guide | 15 min | DevOps/Arch |
| [TFVARS_ORGANIZATION.md](TFVARS_ORGANIZATION.md) | Variable file organization (public vs private) | 10 min | Everyone |
| [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) | Step-by-step migration from Ansible | 30 min | DevOps |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Detailed diagrams and flows | 15 min | Architects |

---

## Getting Started (Choose Your Path)

### Path 1: Deploy Now (10 minutes)

```bash
# 1. Initialize
cd terraform
terraform init

# 2. Preview
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"

# 3. Deploy
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"

# 4. Verify
terraform output
incus list -p prodlayer0
```

Documentation: [QUICKSTART.md](QUICKSTART.md)

### Path 2: Understand First (30 minutes)

1. Read: DESIGN_SUMMARY.md (10 min)
2. Read: ARCHITECTURE.md (10 min)
3. Skim: TERRAFORM-README.md for specifics (10 min)
4. Then proceed with Path 1 (10 min)

Start: [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md)

### Path 3: Migrating from Ansible (2 hours)

1. Read: DESIGN_SUMMARY.md (10 min)
2. Read: MIGRATION_GUIDE.md — detailed steps (30 min)
3. Review: Current Ansible playbooks
4. Setup: Terraform configuration
5. Test: Plan deployment
6. Execute: Gradual migration strategy

Start: [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)

---

## Architecture Overview

```
┌─────────────────────────────────────────┐
│  Terraform Incus Management             │
│  (Modular, State-Tracked, Reusable)    │
└────────────────┬────────────────────────┘
                 │
        ┌────────┼────────┐
        │        │        │
        ▼        ▼        ▼
     Ring 0   Ring 1   Ring 2
   (Storage) (Apps)   (Utils)
        │        │        │
        └────────┼────────┘
                 │
    ┌────────────┼────────────┐
    │            │            │
    ▼            ▼            ▼
  Storage     VMs/Containers   
  Volumes     Instances        
```

**Key Principle:** Pre-existing networks, pools, projects, and profiles are not touched by Terraform.

→ **Detailed:** [ARCHITECTURE.md](ARCHITECTURE.md)

---

## Core Concepts

### What Gets Managed by Terraform?

- **Storage Volumes** (ISO files, data disks)
- **VM Instances** (Virtual machines)
- **Instance Devices** (Network, disk attachments, PCI passthrough)

### What is Pre-existing (Not Managed)?

- **Networks** (phys-br, iso-nat)
- **Storage Pools** (incus-images, incus-instances)
- **Projects** (default, prodlayer0, prodlayer1)
- **Profiles** (default, defaultlan, production)

### How Does It Work?

1. **Define** infrastructure in `.tfvars` files
2. **Plan** with `terraform plan` (preview changes)
3. **Apply** with `terraform apply` (create resources)
4. **Track** state in `terraform.tfstate`
5. **Update** by editing tfvars and applying again
6. **Destroy** with `terraform destroy` (cleanup)

→ **Details:** [TERRAFORM-README.md](TERRAFORM-README.md)

---

## Documentation Map

```
Start Here
    │
    ├─→ DESIGN_SUMMARY.md ────→ (Understand what was built)
    │       │
    │       ├─→ ARCHITECTURE.md ─→ (How does it work internally?)
    │       │
    │       └─→ TERRAFORM-README.md ─→ (Detailed usage guide)
    │
    ├─→ QUICKSTART.md ─────────→ (Get hands-on in 10 min)
    │       │
    │       └─→ modules/vm/README.md ─→ (Understand the VM module)
    │
    ├─→ MIGRATION_GUIDE.md ─────→ (Migrate from Ansible)
    │       │
    │       └─→ Playbooks ────→ (Update Ansible workflows)
    │
    └─→ This File (INDEX.md) ──→ (Navigation help)
```

---

## Finding Specific Information

### "How do I...?"

| Task | Location |
|------|----------|
| Deploy a new VM | [QUICKSTART.md](QUICKSTART.md#common-tasks) |
| Modify VM resources | [QUICKSTART.md](QUICKSTART.md#modify-a-vm) |
| Handle ISO files | [../../terraform/modules/vm/README.md](../../terraform/modules/vm/README.md#iso-handling) |
| Enable PCIe passthrough | [TERRAFORM-README.md](TERRAFORM-README.md) — Variable Files section |
| Add data disks | [configs/envtest/ring0.tfvars](../../configs/envtest/ring0.tfvars) — example |
| Migrate from Ansible | [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) |
| Understand the architecture | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Troubleshoot errors | [QUICKSTART.md](QUICKSTART.md#troubleshooting) |

### "I'm getting an error..."

1. Check: [QUICKSTART.md](QUICKSTART.md#troubleshooting)
2. Check: [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md#troubleshooting) (longer list)
3. Check: [terraform/README.md](../../terraform/README.md)
4. Check: Terraform docs at https://www.terraform.io/docs

---

## File Structure

```
homelabinfracode/
├── terraform/                    ← Core Terraform config
│   ├── versions.tf               (Provider versions)
│   ├── providers.tf              (Incus + 1Password)
│   ├── variables.tf              (Input variables)
│   ├── locals.tf                 (Internal values)
│   ├── main.tf                   (Module instantiation)
│   ├── outputs.tf                (Export values)
│   └── modules/
│       └── vm/                   (VM creation module)
│
├── configs/envtest/               ← Test tfvars
│   ├── ring0.tfvars
│   ├── ring1.tfvars
│   └── ring2.tfvars
│
├── configs.private/envprod/       ← Production tfvars
│   ├── ring0.tfvars
│   ├── ring1.tfvars
│   └── ring2.tfvars
│
└── docs/terraform/               ← This directory
    ├── INDEX.md                  (Navigation)
    ├── DESIGN_SUMMARY.md         (Overview)
    ├── QUICKSTART.md             (Quick setup)
    ├── TERRAFORM-README.md       (Full guide)
    ├── MIGRATION_GUIDE.md        (Ansible→Terraform)
    ├── TFVARS_ORGANIZATION.md    (Tfvars layout)
    └── ARCHITECTURE.md           (Diagrams)
```

---

## Implementation Checklist

### Phase 1: Setup
- [ ] Review [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md)
- [ ] Read [QUICKSTART.md](QUICKSTART.md)
- [ ] Run `terraform init`
- [ ] Run `terraform plan -var-file="../configs.private/envprod/ring0.tfvars"`
- [ ] Review plan output

### Phase 2: Testing
- [ ] Run `terraform apply -var-file="../configs/envtest/ring0.tfvars"` (test environment)
- [ ] Verify VMs are created: `incus list -p prodlayer0`
- [ ] Verify outputs: `terraform output`
- [ ] Test modifying a VM
- [ ] Test destroying a VM

### Phase 3: Production
- [ ] Run `terraform apply -var-file="../configs.private/envprod/ring0.tfvars"`
- [ ] Verify production VMs
- [ ] Update CI/CD pipelines

---

## Key Takeaways

1. **Modular**: VM module can be reused for any VM
2. **State-Tracked**: Know exactly what's deployed
3. **Reversible**: `terraform destroy` cleans up
4. **Version Controlled**: Full audit trail in git
5. **Scalable**: Easy to add new VMs, rings, modules
6. **Non-Interfering**: Respects pre-existing infrastructure
7. **Safe**: `terraform plan` shows changes before applying

---

## Common Questions

**Q: Do I have to migrate all at once?**
A: No. Use parallel setup — Terraform for new VMs while keeping Ansible running.

**Q: What if something goes wrong?**
A: Run `terraform destroy` to clean up, or `git revert` to undo tfvars changes.

**Q: How do I handle sensitive data?**
A: Secrets are managed via the 1Password Terraform provider. See [Architecture — Secrets Management](../02-architecture.md).

**Q: Can I use this with existing Ansible playbooks?**
A: Yes. Terraform creates VMs, Ansible configures them. This is the standard workflow.

---

## Getting Help

1. **Local Troubleshooting**: [QUICKSTART.md#troubleshooting](QUICKSTART.md#troubleshooting)
2. **Migration Issues**: [MIGRATION_GUIDE.md#troubleshooting](MIGRATION_GUIDE.md#troubleshooting)
3. **Understanding Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md)
4. **Terraform Docs**: https://www.terraform.io/docs
5. **Incus Provider Docs**: https://registry.terraform.io/providers/lxc/incus/latest/docs

---

## Next Steps

- **Want to deploy in 10 minutes?** → [QUICKSTART.md](QUICKSTART.md)
- **Want to understand everything?** → [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md)
- **Want to plan a migration?** → [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)
- **Want to see diagrams?** → [ARCHITECTURE.md](ARCHITECTURE.md)
