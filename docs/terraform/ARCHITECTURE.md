# Terraform — Architecture

> **Context**: For the master architecture overview (including Terraform's role in the overall system), see [Architecture](../02-architecture.md). This document provides detailed Terraform-specific architecture diagrams and data flows.
>
> **Path conventions**: Tfvars at `configs/envtest/` (test) or `configs.private/envprod/` (production). Documentation is in `docs/terraform/` (this directory).

## High-Level Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     Terraform Configuration                    │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ versions.tf  │  │ providers.tf  │  │ variables.tf│          │
│  │ (Versions)   │  │ (Auth)        │  │ (Inputs)    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                │
│         ↓                                                      │
│  ┌─────────────────────────────────────────────────┐           │
│  │              main.tf (Root Module)              │           │
│  │  check "workspace_not_default" (validation)     │           │
│  │  for_each var.vms → module.vm[...]              │           │
│  │  for_each var.docker_containers → module[...]   │           │
│  └──────────┬──────────────────────────────────────┘           │
│             │                                                  │
│             ├──→ ┌─────────────────────────────────────┐       │
│             │    │     modules/vm/main.tf              │       │
│             │    │  ┌────────────────────────────────┐ │       │
│             │    │  │ incus_storage_volume (ISO)     │ │       │
│             │    │  │ incus_storage_volume (data)    │ │       │
│             │    │  │ incus_instance (VM)            │ │       │
│             │    │  │ null_resource (provisioner)    │ │       │
│             │    │  └────────────────────────────────┘ │       │
│             │    └─────────────────────────────────────┘       │
│             │                                                  │
│             ├──→ ┌─────────────────────────────────────┐       │
│             │    │  modules/docker_container/main.tf   │       │
│             │    │  ┌────────────────────────────────┐ │       │
│             │    │  │ incus_storage_volume (volumes) │ │       │
│             │    │  │ incus_instance (container)     │ │       │
│             │    │  └────────────────────────────────┘ │       │
│             │    └─────────────────────────────────────┘       │
│             │                                                  │
│             └──→ [Repeat for each entry in tfvars]             │
│                                                                │
│  ┌──────────────────────────────────────────────────┐          │
│  │  outputs.tf (Export Results)                     │          │
│  │  Instance IDs, IP addresses, Volume names        │          │
│  └──────────────────────────────────────────────────┘          │
│                                                                │
└────────────────────────────────────────────────────────────────┘
                              ↓
              terraform.tfstate.d/<workspace>/
                   terraform.tfstate
                   (State per ring)
                              ↓
                    ┌──────────────────┐
                    │  Incus Daemons   │
                    │ (Local/Remote)   │
                    └──────────────────┘
```

## VM Module Internals

```
┌────────────────────────────────────────────────────────────────┐
│                    VM Module (modules/vm/)                     │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Input Variables                                               │
│  ├── instance_name       (VM name)                             │
│  ├── target_remote       (Incus remote)                        │
│  ├── incus_project       (Project name)                        │
│  ├── incus_profile       (Profile name)                        │
│  ├── storage_pool        (Storage pool)                        │
│  ├── cpu_cores           (CPU allocation)                      │
│  ├── memory_gb           (Memory allocation)                   │
│  ├── system_disk_gb      (Root disk size)                      │
│  ├── network_bridge      (Network to attach)                   │
│  ├── mac_address         (Static MAC)                          │
│  ├── iso_source_local    (Local ISO path)                      │
│  ├── iso_path            (Target ISO path)                     │
│  ├── enable_pcie_passthrough (Hardware passthrough)            │
│  ├── pcie_controller     (PCI address)                         │
│  ├── data_disks          (Data disk list)                      │
│  └── tags                (Resource tags)                       │
│                                                                │
│  ↓                                                             │
│                                                                │
│  Resource Creation Flow                                        │
│  ┌──────────────────────────────────────────────────┐          │
│  │ 1. incus_storage_volume (ISO)                    │          │
│  │    - Creates empty volume for ISO                │          │
│  │    - Name: {instance_name}-install-iso           │          │
│  │    - Depends on: (none)                          │          │
│  └──────────────────────────────────────────────────┘          │
│                      ↓                                         │
│  ┌──────────────────────────────────────────────────┐          │
│  │ 2. incus_storage_volume (Data Disks)             │          │
│  │    - One per disk in data_disks list             │          │
│  │    - Names: {instance_name}-{disk_name}          │          │
│  │    - Depends on: ISO volume                      │          │
│  └──────────────────────────────────────────────────┘          │
│                      ↓                                         │
│  ┌──────────────────────────────────────────────────┐          │
│  │ 3. incus_instance (VM)                           │          │
│  │    - Creates VM instance                         │          │
│  │    - Attaches root disk                          │          │
│  │    - Attaches network interface                  │          │
│  │    - Attaches ISO (if provided)                  │          │
│  │    - Attaches data disks (if provided)           │          │
│  │    - Attaches PCI device (if PCIe enabled)       │          │
│  │    - Depends on: All storage volumes             │          │
│  │    - Wait for: Agent availability                │          │
│  └──────────────────────────────────────────────────┘          │
│                      ↓                                         │
│  ┌──────────────────────────────────────────────────┐          │
│  │ 4. null_resource + local-exec (ISO Import)       │          │
│  │    - Runs: incus storage volume import ...       │          │
│  │    - Imports ISO into storage volume             │          │
│  │    - Only if iso_source_local is provided        │          │
│  │    - Depends on: incus_storage_volume (ISO)      │          │
│  └──────────────────────────────────────────────────┘          │
│                      ↓                                         │
│  Outputs                                                       │
│  ├── instance_id          (Incus instance ID)                  │
│  ├── instance_name        (VM name)                            │
│  ├── instance_ipv4_address (IPv4 address)                      │
│  ├── instance_ipv6_address (IPv6 address)                      │
│  ├── instance_status      (Running/Stopped)                    │
│  ├── iso_volume_name      (ISO volume name)                    │
│  └── data_disk_names      (List of data disk names)            │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## Data Flow: Planning and Applying

```
User Action: terraform plan -var-file="configs/envtest/ring0.tfvars"
             (in workspace: ring0)
                              ↓
                    ┌─────────────────┐
                    │  Load tfvars    │
                    │  Parse vars     │
                    └────────┬────────┘
                             ↓
                    ┌─────────────────┐
                    │ Check workspace │
                    │ != "default"    │
                    └────────┬────────┘
                             ↓
                    ┌─────────────────┐
                    │ Load State File │
                    │ (workspace dir) │
                    └────────┬────────┘
                             ↓
                    ┌─────────────────┐
                    │ Instantiate     │
                    │ Modules         │
                    │ (module.vm[x])  │
                    └────────┬────────┘
                             ↓
              ┌──────────────────────────────┐
              │  For Each VM in var.vms:     │
              │  ├─ Build resource graph     │
              │  ├─ Validate inputs          │
              │  ├─ Check resource state     │
              │  └─ Compare desired vs actual│
              └──────────┬───────────────────┘
                         ↓
                 Show Planned Changes
                 (Add/Change/Destroy)
```

```
User Action: terraform apply -var-file="configs/envtest/ring0.tfvars"
                              ↓
                         Plan Phase
                         (same as above)
                              ↓
                    ┌──────────────────┐
                    │ Ask for confirmation
                    │ (or auto-approve)
                    └────────┬─────────┘
                             ↓
              ┌──────────────────────────────┐
              │  For Each Resource:          │
              │  ├─ Create/Update/Destroy    │
              │  ├─ Wait for completion      │
              │  ├─ Capture outputs          │
              │  └─ Update state             │
              └──────────┬───────────────────┘
                         ↓
                Update terraform.tfstate
                         ↓
            Display Outputs and Summary
```

## Incus Integration Points

```
┌──────────────────────────────────────────────────────────┐
│              Incus Infrastructure                        │
│              (Pre-existing, not managed)                 │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Networks              Storage Pools                     │
│  ├─ phys-br            ├─ incus-images                   │
│  └─ iso-nat            └─ incus-instances                │
│                                                          │
│  Projects              Profiles                          │
│  ├─ default            ├─ default                        │
│  ├─ prodlayer0         ├─ defaultlan                     │
│  └─ prodlayer1         └─ production                     │
│                                                          │
└────────────┬─────────────────────────────────────────────┘
             │ (Terraform reads from)
             │
             ├──→ Terraform Provider
             │    ├── connects to Incus daemon
             │    ├── authenticates with certs
             │    └── manages:
             │        ├─ Custom storage volumes
             │        ├─ VM instances
             │        ├─ Device attachments
             │        └─ Resource state
             │
             ↓
        terraform.tfstate
        (Tracks all managed resources)
```

## Environment Separation

```
┌─────────────────────────────────────────────────────────┐
│  Terraform Workspaces (Per-Ring State Isolation)        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Workspace: ring0                                       │
│  ├── incus_project = "prodlayer0"                       │
│  ├── configs.private/envprod/ring0.tfvars               │
│  ├── terraform.tfstate.d/ring0/terraform.tfstate        │
│  └── Foundational VMs (TrueNAS, Samba4 AD DC)          │
│                                                         │
│  Workspace: ring1                                       │
│  ├── incus_project = "prodlayer1"                       │
│  ├── configs.private/envprod/ring1.tfvars               │
│  ├── terraform.tfstate.d/ring1/terraform.tfstate        │
│  └── Operations (k3s nodes, MQTT broker, containers)    │
│                                                         │
│  Workspace: ring2                                       │
│  ├── incus_project = "default"                          │
│  ├── configs.private/envprod/ring2.tfvars               │
│  ├── terraform.tfstate.d/ring2/terraform.tfstate        │
│  └── Utility services and containers                    │
│                                                         │
│  Workspace: default (BLOCKED by check block)            │
│  └── Not used — validation warns if selected            │
│                                                         │
│  Identity Isolation:                                    │
│  ├── ring0 identity → manages prodlayer0 only           │
│  ├── ring1 identity → manages prodlayer1 only           │
│  └── ring2 identity → manages default project only      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Workspace Commands

```bash
# One-time setup
terraform workspace new ring0
terraform workspace new ring1
terraform workspace new ring2

# Daily usage
terraform workspace select ring0
terraform plan  -var-file="../configs.private/envprod/ring0.tfvars"
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"

# Switch rings
terraform workspace select ring1
terraform plan  -var-file="../configs.private/envprod/ring1.tfvars"
terraform apply -var-file="../configs.private/envprod/ring1.tfvars"

# List all workspaces (* marks current)
terraform workspace list
```

## Resource Dependency Graph Example

```
Data Dependencies for truenas-primary:

incus_storage_volume.iso
  └── (inputs)
      ├── instance_name = "test-ubuntu-single"
      ├── storage_pool = "incus-instances" (pre-existing)
      ├── incus_project = "default" (pre-existing)
      └── target_remote = "incussingledisk"

incus_storage_volume.data_disks (none for this example)
  └── Optional: creates additional storage volumes
      ├── instance_name = "test-ubuntu-single"
      ├── storage_pool = "incus-instances" (pre-existing)
      └── target_remote = "incussingledisk"

incus_instance.vm
  └── depends_on:
      ├── incus_profile "default" (pre-existing)
      ├── incus_project "default" (pre-existing)
      ├── network "br0" (pre-existing)
      └── storage_pool "incus-instances" (pre-existing)
  
  └── creates:
      ├── Root device → storage_pool
      ├── Network device → br0 (auto-generated MAC)
      └── Image-based boot → images:ubuntu/24.04

null_resource.image_import
  └── depends_on: pre-built image available
      ├── uses: images:ubuntu/24.04
      ├── source: image repository
      └── target: "incussingledisk" remote
```

## Typical Deployment Timeline

```
Minute  Event
─────  ──────────────────────────────────────────────
0      User: terraform init
       → Download provider, setup modules

1      User: terraform plan -var-file="configs/envtest/ring0.tfvars"
       → Analyze configuration
       → Compare with state (empty)
       → Show 8+ resources to create

3      User: terraform apply -var-file="configs/envtest/ring0.tfvars"
       → Create incus_storage_volume (ISO) - 0.5s
       → Create incus_storage_volume (data disk) - 0.5s
       → Create incus_instance (VM) - 10-15s
       → Wait for agent - 20-30s
       → Execute null_resource (ISO import) - 30-60s
       → Update state - 1s

60     Completion: VM running, ISO mounted, data disks attached
       → terraform output shows IP addresses and status
```

---

This architecture provides a clear separation of concerns while maintaining flexibility for future expansion and respecting the pre-existing Incus infrastructure configuration.
