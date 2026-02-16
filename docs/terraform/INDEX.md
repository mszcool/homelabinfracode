# Terraform Incus Refactor - Complete Documentation Index

Welcome! This document helps you navigate the complete Terraform refactor of your Incus infrastructure.

## 📋 Quick Navigation

### For Different Audiences

**👤 Project Manager / Decision Maker**
→ Start with [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md) (5 min read)
→ Then [COMPARISON.md](COMPARISON.md) (15 min read)

**👨‍💻 Developer / DevOps Engineer**
→ Start with [QUICKSTART.md](QUICKSTART.md) (10 min hands-on)
→ Then [TERRAFORM-README.md](TERRAFORM-README.md) (understand architecture)
→ Then [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) (plan implementation)
→ Reference: [../terraform/modules/vm/README.md](../terraform/modules/vm/README.md) (module details)

**🏗️ Architect / Infrastructure Designer**
→ Start with [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md)
→ Then [ARCHITECTURE.md](ARCHITECTURE.md) (detailed diagrams)
→ Then [README.md](README.md) (implementation details)
→ Then [COMPARISON.md](COMPARISON.md) (Ansible vs Terraform)

**📚 Student / New to Terraform**
→ Start with [QUICKSTART.md](QUICKSTART.md)
→ Then [modules/vm/README.md](modules/vm/README.md)
→ Then Terraform official docs

---

## 📁 Files and Their Purpose

### Configuration Files (Ready to Use)

```
terraform/
├── versions.tf              ✅ Terraform version constraints
├── providers.tf             ✅ Incus provider authentication
├── variables.tf             ✅ Input variable definitions
├── locals.tf                ✅ Local computed values
├── main.tf                  ✅ Root module instantiation
└── outputs.tf               ✅ Infrastructure outputs
```

**Usage:** These are the core configuration files. Start by running:
```bash
cd terraform
terraform init
terraform plan -var-file="../configs.private/ring0/ring0.tfvars"
```

> 📝 **Note:** Variable files are now organized in `configs/` (public samples) and `configs.private/` (actual configs).
> See [TFVARS_ORGANIZATION.md](TFVARS_ORGANIZATION.md) for details.

### Module Files (Reusable Components)

```
modules/vm/
├── main.tf                  ✅ Core VM resources
├── variables.tf             ✅ VM input parameters
├── outputs.tf               ✅ VM output values
├── locals.tf                ✅ Internal VM logic
├── versions.tf              ✅ Module dependencies
└── README.md                📖 Module documentation
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

**Public Samples** (reference and documentation):
```
configs/
├── ring0/ring0.tfvars       ✅ Infrastructure layer examples (TrueNAS, storage)
├── ring1/ring1.tfvars       ✅ Application layer examples
└── ring2/ring2.tfvars       ✅ User services examples
```

**Private Actual Configs** (deployment configurations):
```
configs.private/
├── ring0/ring0.tfvars       ✅ YOUR actual Ring0 configuration
├── ring1/ring1.tfvars       ✅ YOUR actual Ring1 configuration
└── ring2/ring2.tfvars       ✅ YOUR actual Ring2 configuration
```

**Usage:** Always use configs.private for deployment:
```bash
terraform plan -var-file="../configs.private/ring0/ring0.tfvars"
terraform apply -var-file="../configs.private/ring1/ring1.tfvars"
```

> 📚 See [TFVARS_ORGANIZATION.md](TFVARS_ORGANIZATION.md) for security rationale and detailed explanation.

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

## 🚀 Getting Started (Choose Your Path)

### Path 1: I Just Want to Deploy (10 minutes)

```bash
# 1. Initialize
cd terraform
terraform init

# 2. Preview
terraform plan -var-file="../configs.private/ring0/ring0.tfvars"

# 3. Review output (check if it looks right)

# 4. Deploy
terraform apply -var-file="../configs.private/ring0/ring0.tfvars"

# 5. Verify
terraform output
incus list -p prodlayer0
```

→ **Documentation:** [QUICKSTART.md](QUICKSTART.md)

### Path 2: I Need to Understand the Design First (30 minutes)

```
1. Read: DESIGN_SUMMARY.md (10 min)
2. Read: ARCHITECTURE.md (10 min)
3. Skim: TERRAFORM-README.md for specifics (10 min)
4. Then proceed with Path 1 (10 min)
```

→ **Start:** [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md)

### Path 3: I'm Migrating from Ansible (2 hours)

```
1. Read: DESIGN_SUMMARY.md (10 min)
2. Read: COMPARISON.md - understand differences (20 min)
3. Read: MIGRATION_GUIDE.md - detailed steps (30 min)
4. Review: Current Ansible playbooks
5. Setup: Terraform configuration
6. Test: Plan deployment
7. Execute: Gradual migration strategy
```

→ **Start:** [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)

### Path 4: I'm Building Something New (1 hour)

```
1. Understand: QUICKSTART.md (10 min)
2. Study: ../terraform/modules/vm/README.md (15 min)
3. Copy: Example from ../configs/ring0/ring0.tfvars
4. Modify: For your VM needs
5. Plan: terraform plan
6. Apply: terraform apply
7. Reference: TERRAFORM-README.md for advanced features
```

→ **Start:** [QUICKSTART.md](QUICKSTART.md)

---

## 📊 Architecture Overview

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

## 🎯 Core Concepts

### What Gets Managed by Terraform?

✅ **Storage Volumes** (ISO files, data disks)
✅ **VM Instances** (Virtual machines)
✅ **Instance Devices** (Network, disk attachments, PCI passthrough)

### What is Pre-existing (Not Managed)?

❌ **Networks** (phys-br, iso-nat)
❌ **Storage Pools** (incus-images, incus-instances)
❌ **Projects** (default, prodlayer0, prodlayer1)
❌ **Profiles** (default, defaultlan, production)

### How Does It Work?

1. **Define** infrastructure in `.tfvars` files
2. **Plan** with `terraform plan` (preview changes)
3. **Apply** with `terraform apply` (create resources)
4. **Track** state in `terraform.tfstate`
5. **Update** by editing tfvars and applying again
6. **Destroy** with `terraform destroy` (cleanup)

→ **Details:** [README.md](README.md)

---

## 📖 Documentation Map

```
Start Here
    │
    ├─→ DESIGN_SUMMARY.md ────→ (Understand what was built)
    │       │
    │       ├─→ COMPARISON.md  ─→ (Why Terraform over Ansible?)
    │       │
    │       ├─→ ARCHITECTURE.md ─→ (How does it work internally?)
    │       │
    │       └─→ README.md ────→ (Detailed usage guide)
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

## 🔍 Finding Specific Information

### "How do I...?"

| Task | Location |
|------|----------|
| Deploy a new VM | [QUICKSTART.md](QUICKSTART.md#common-tasks) |
| Modify VM resources | [QUICKSTART.md](QUICKSTART.md#modify-a-vm) |
| Handle ISO files | [modules/vm/README.md](modules/vm/README.md#iso-handling) |
| Enable PCIe passthrough | [README.md](README.md) - Variable Files section |
| Add data disks | [tfvars/ring0.tfvars](tfvars/ring0.tfvars) - example |
| Migrate from Ansible | [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) |
| Understand the architecture | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Compare Ansible vs Terraform | [COMPARISON.md](COMPARISON.md) |
| Troubleshoot errors | [QUICKSTART.md](QUICKSTART.md#troubleshooting) |
| Set up remote state | [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md#remote-state) |

### "I'm getting an error..."

1. Check: [QUICKSTART.md](QUICKSTART.md#troubleshooting)
2. Check: [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md#troubleshooting) (longer list)
3. Check: [README.md](README.md#troubleshooting)
4. Check: Terraform docs at https://www.terraform.io/docs

---

## 🗂️ File Structure

```
homelabinfracode/
├── terraform/                    ← YOU ARE HERE
│   ├── versions.tf               (Provider versions)
│   ├── providers.tf              (Incus connection)
│   ├── variables.tf              (Input variables)
│   ├── locals.tf                 (Internal values)
│   ├── main.tf                   (Module instantiation)
│   ├── outputs.tf                (Export values)
│   ├── .gitignore                (Exclude tfstate, etc)
│   │
│   ├── modules/
│   │   └── vm/                   (VM creation module)
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       ├── locals.tf
│   │       ├── versions.tf
│   │       └── README.md
│   │
│   ├── tfvars/                   (Environment configs)
│   │   ├── ring0.tfvars          (Infrastructure layer)
│   │   ├── ring1.tfvars          (Applications - future)
│   │   └── ring2.tfvars          (Utilities - future)
│   │
│   └── docs/                     (Documentation)
│       ├── INDEX.md              ← YOU ARE HERE
│       ├── DESIGN_SUMMARY.md     (Overview)
│       ├── QUICKSTART.md         (Quick setup)
│       ├── README.md             (Full guide)
│       ├── MIGRATION_GUIDE.md    (Ansible→Terraform)
│       ├── COMPARISON.md         (Detailed comparison)
│       └── ARCHITECTURE.md       (Diagrams)
│
├── playbooks/                    (Keep these, use with Terraform)
├── configs/                      (Reference configs)
├── configs.private/              (Sensitive configs)
└── ... (other files)
```

---

## ✅ Implementation Checklist

### Phase 1: Setup (Week 1)
- [ ] Review [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md)
- [ ] Read [QUICKSTART.md](QUICKSTART.md)
- [ ] Run `terraform init`
- [ ] Run `terraform plan -var-file="tfvars/ring0.tfvars"`
- [ ] Review plan output
- [ ] Update documentation for team

### Phase 2: Testing (Week 2)
- [ ] Run `terraform apply -var-file="tfvars/ring0.tfvars"` (test environment)
- [ ] Verify VMs are created: `incus list -p prodlayer0`
- [ ] Verify outputs: `terraform output`
- [ ] Test modifying a VM
- [ ] Test destroying a VM

### Phase 3: Migration (Week 3-4)
- [ ] Read [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)
- [ ] Plan migration strategy
- [ ] Import existing Ansible-created VMs (optional)
- [ ] Archive Ansible playbooks
- [ ] Update CI/CD pipelines

### Phase 4: Optimization (Week 5+)
- [ ] Set up remote state backend (optional)
- [ ] Add container module (future)
- [ ] Add automation scripts
- [ ] Document team workflows

---

## 💡 Key Takeaways

1. **Modular**: VM module can be reused for any VM
2. **State-Tracked**: Know exactly what's deployed
3. **Reversible**: `terraform destroy` cleans up
4. **Version Controlled**: Full audit trail in git
5. **Scalable**: Easy to add new VMs, rings, modules
6. **Non-Interfering**: Respects pre-existing infrastructure
7. **Safe**: `terraform plan` shows changes before applying

---

## 🤝 Common Questions

**Q: Do I have to migrate all at once?**
A: No. Use parallel setup - Terraform for new VMs while keeping Ansible running.

**Q: What if something goes wrong?**
A: Run `terraform destroy` to clean up, or `git revert` to undo tfvars changes.

**Q: How do I handle sensitive data?**
A: Use `.tfvars.auto` files (not in git) or environment variables.

**Q: Can I use this with existing Ansible playbooks?**
A: Yes! Terraform creates VMs, Ansible configures them.

**Q: How do I set up a remote state backend?**
A: See [MIGRATION_GUIDE.md - Remote State](MIGRATION_GUIDE.md#remote-state-production-optional)

---

## 📞 Getting Help

1. **Local Troubleshooting**: [QUICKSTART.md#troubleshooting](QUICKSTART.md#troubleshooting)
2. **Migration Issues**: [MIGRATION_GUIDE.md#troubleshooting](MIGRATION_GUIDE.md#troubleshooting)
3. **Understanding Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md)
4. **Comparing Approaches**: [COMPARISON.md](COMPARISON.md)
5. **Terraform Docs**: https://www.terraform.io/docs
6. **Incus Provider Docs**: https://registry.terraform.io/providers/lxc/incus/latest/docs

---

## 📝 Next Steps

**Choose your starting point above and dive in!**

- **Want to deploy in 10 minutes?** → [QUICKSTART.md](QUICKSTART.md)
- **Want to understand everything?** → [DESIGN_SUMMARY.md](DESIGN_SUMMARY.md)
- **Want to plan a migration?** → [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)
- **Want to see diagrams?** → [ARCHITECTURE.md](ARCHITECTURE.md)

---

**Happy Terraforming! 🚀**

Last Updated: December 2025
Status: ✅ Complete and Ready for Use
