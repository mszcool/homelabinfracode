# Architecture Overview

This document covers both the infrastructure architecture (what physical and logical components make up the homelab) and the automation architecture (how Ansible playbooks, Terraform modules, inventory, and secrets management are structured).

## Infrastructure Architecture

### Physical Topology

```
                    ┌─────────────┐
                    │   Internet   │
                    └──────┬──────┘
                           │ WAN
                    ┌──────┴──────┐
                    │  MikroTik   │
                    │   Router    │
                    │ (Ring 0)    │
                    └──────┬──────┘
                           │ LAN / VLANs
            ┌──────────────┼──────────────┐
            │              │              │
     ┌──────┴──────┐┌─────┴──────┐┌──────┴──────┐
     │ Incus Node 1││ Incus Node 2││ Edge Devices│
     │ (compute)   ││ (compute)   ││ (Raspberry  │
     │             ││             ││  Pi bridge) │
     └──────┬──────┘└─────┬──────┘└─────────────┘
            │              │
     ┌──────┴──────────────┴──────┐
     │     Virtual Machines       │
     │  ┌─────────┐ ┌──────────┐ │
     │  │TrueNAS  │ │ Samba4   │ │
     │  │Scale VM │ │ AD DC VM │ │
     │  │(storage)│ │(identity)│ │
     │  └─────────┘ └──────────┘ │
     │  ┌─────────┐ ┌──────────┐ │
     │  │ k3s     │ │ App VMs  │ │
     │  │ cluster │ │ (Ring 1) │ │
     │  └─────────┘ └──────────┘ │
     └────────────────────────────┘
```

### Component Inventory

#### Ring 0 — Foundational Components

| Component | Role | Type | Notes |
|-----------|------|------|-------|
| **MikroTik Router** | Network gateway, firewall, DHCP, DNS, VLANs, VPN | Physical appliance | Managed via RouterOS CLI over SSH |
| **Incus Compute Nodes** | Virtualization hosts (VMs + containers) | Bare-metal Ubuntu servers | LVM storage pools, macvlan + NAT networking |
| **TrueNAS Scale** | Network-attached storage (SMB, NFS), snapshots | VM on Incus (PCIe passthrough) | SATA controller passed through for direct disk access |
| **Samba4 AD DC** | Active Directory, DNS, Kerberos, LDAP | VM on Incus | Centralized identity for all services |
| **Edge Devices** | WiFi bridging (optional) | Raspberry Pi | Bridge remote network segments |

#### Ring 1 — Operations Components

| Component | Role | Type | Notes |
|-----------|------|------|-------|
| **k3s Cluster** | Kubernetes orchestration | VMs on Incus | Lightweight k8s for containerized workloads |
| **Authentik** | OAuth/OIDC SSO provider | Container (planned) | Security token service |
| **MQTT Broker** | Event messaging | Container (planned) | IoT and home automation messaging |
| **Home Assistant** | Home automation | Container (planned) | Integrates with MQTT and identity |

#### Ring 2 — Application Components

| Component | Role | Type | Notes |
|-----------|------|------|-------|
| **Syncthing** | File synchronization | TrueNAS Docker app | Deployed via TrueNAS apps system |
| **Paperless NGX** | Document management | Container (planned) | OCR and document archival |

### Networking Architecture

The MikroTik router manages all network segments:

- **WAN interface**: DHCP client to upstream ISP
- **LAN bridge**: Primary network with static IP assignments
- **VLANs**: Segmented networks for isolation (e.g., IoT, management)
- **Firewall**: Rule-based filtering with named address lists for device groups
- **DHCP**: Static leases for known devices, DNS static entries
- **Site-to-site VPN**: IPsec tunnels for remote network bridging (optional)

Incus nodes provide two network modes for VMs:

- **macvlan (phys-br)**: Bridged directly to the physical network — VMs get LAN IPs
- **NAT (iso-nat)**: Internal network with NAT — used for isolated workloads

### Storage Architecture

TrueNAS Scale runs as a VM on Incus with PCIe/SATA controller passthrough, giving it direct access to physical disks. It provides:

- **ZFS storage pools**: Mirrored or RAID-Z configurations
- **Dataset hierarchies**: Organized by purpose with inheritance (compression, ACL type, record size)
- **SMB shares**: Windows-compatible file sharing, integrated with Active Directory
- **NFS shares**: Linux-compatible exports for VM and container mounts
- **NFSv4 ACLs**: Fine-grained access control based on AD groups and users
- **Docker/Apps**: Built-in container runtime for Ring 2 applications

### Identity Architecture

Samba4 AD DC provides centralized identity:

- **Active Directory domain**: Users, groups, organizational units synced across all services
- **DNS**: Authoritative DNS for the local domain
- **Kerberos**: Single sign-on authentication
- **LDAP**: Directory services for service integration
- **TrueNAS integration**: AD domain join for unified file access permissions

## Automation Architecture

### Repository Layout

```
homelabinfracode/                    # Main public repository
├── ansible.cfg                      # Global Ansible configuration
├── ansible-requirements.yaml        # Galaxy collection dependencies
├── initAnsibleHost.sh               # Bootstrap script for control host
├── configs/
│   ├── envbase/                     # Base inventory (shared across envs)
│   │   ├── hosts.yaml               # Group hierarchy definition
│   │   └── group_vars/              # Per-group variable files
│   │       ├── all/                  # Global variables + secrets vault example
│   │       ├── incus_scope/          # Incus cluster shared config
│   │       ├── mainrouter/           # Router config (networks, firewall, devices)
│   │       ├── truenas/              # TrueNAS setup + ongoing config
│   │       ├── identityprovider/     # Samba4 AD config + identity definitions
│   │       └── edge_devices/         # Raspberry Pi edge configs
│   ├── envtest/                     # Test environment overlay
│   │   ├── inventory/hosts.yaml     # Test host assignments
│   │   ├── ring0.tfvars             # Test Terraform variables (Ring 0)
│   │   ├── ring1.tfvars             # Test Terraform variables (Ring 1)
│   │   └── ring2.tfvars             # Test Terraform variables (Ring 2)
│   └── incus/                       # Incus preseed and profile files
├── configs.private/                 # Private repo (Git submodule)
│   └── envprod/                     # Production environment overlay
│       ├── inventory/hosts.yaml     # Production host assignments
│       ├── ring0.tfvars             # Production Terraform variables
│       └── ...                      # Actual secrets references, IPs, MACs
├── playbooks/                       # All Ansible playbooks
│   ├── prepare-localhost.yaml       # Control host package setup
│   ├── all-base/                    # Cross-ring host bootstrap/upgrade
│   ├── ring0/                       # Initial infrastructure setup
│   │   ├── templates/               # Jinja2 templates (RouterOS, autoinstall, Incus)
│   │   ├── tasks/                   # Reusable task includes
│   │   └── projects/                # Incus project definitions (YAML per project)
│   ├── ring0a/                      # Continuous configuration
│   │   ├── tasks/                   # Reusable task includes
│   │   └── filter_plugins/          # Custom Ansible filter plugins
│   ├── ring1/                       # Operations service deployment
│   └── ring2/                       # Application deployment
│       └── tasks/                   # Reusable task includes
├── scripts/                         # Operational helper scripts
│   ├── op-session.sh                # 1Password session creation
│   ├── validate-inventory.sh        # Inventory structure validation
│   ├── validate-playbooks.sh        # Playbook syntax validation
│   └── manage-incus-client-certs.sh # Incus TLS certificate management
└── terraform/                       # Infrastructure provisioning
    ├── main.tf                      # Root module (VM instantiation loop)
    ├── variables.tf                 # Input variable definitions
    ├── providers.tf                 # Incus + 1Password provider config
    ├── versions.tf                  # Version constraints
    ├── locals.tf                    # Computed identifiers
    ├── outputs.tf                   # VM output information
    └── modules/vm/                  # Reusable VM module
        ├── main.tf                  # VM resource definition
        └── variables.tf             # VM input parameters
```

### Ansible Inventory Model

The inventory uses a **directory-based, layered approach**. A base inventory defines the group hierarchy and shared variables. Environment-specific overlays assign actual hosts and override values.

```
ansible-playbook -i configs/envbase/ -i configs.private/envprod/inventory/ <playbook>
                      │                        │
                      │                        └── Production hosts + overrides
                      └── Group hierarchy + group_vars (shared config)
```

**Base inventory** (`configs/envbase/`):

- `hosts.yaml` — Defines all Ansible groups: `incus_scope`, `incus`, `identityprovider`, `truenas`, `mainrouter`, `edge_devices`
- `group_vars/` — Variable files per group containing configuration constants, firewall rules, network definitions, dataset structures, identity definitions

**Environment overlays** (`configs/envtest/inventory/` or `configs.private/envprod/inventory/`):

- `hosts.yaml` — Maps actual hostnames, IP addresses, and host-specific variables to groups

This separation means the **same playbooks** work across test and production environments with different inventory paths.

### Ansible Group Structure

```
all
├── incus_scope                     # Incus management scope
│   ├── localhost                   # Control node (for local operations)
│   └── incus                       # Bare-metal Incus compute nodes
├── identityprovider                # Samba4 AD DC hosts
├── securitytokenservice            # OAuth/OIDC providers (future)
├── truenas                         # TrueNAS Scale instances
├── mainrouter                      # MikroTik network router
└── edge_devices                    # Raspberry Pi edge bridges
```

### Terraform Module Architecture

Terraform manages VM and container provisioning on Incus. The architecture separates concerns into ring-specific variable files:

```
┌────────────────────────────────────────────────┐
│  terraform/                                     │
│                                                 │
│  versions.tf ─→ providers.tf ─→ variables.tf   │
│                                       │         │
│                                  locals.tf      │
│                                       │         │
│  main.tf ─────────────────────────────┘         │
│     │                                           │
│     │  for_each var.vms                         │
│     ▼                                           │
│  modules/vm/                                    │
│     ├── Storage volumes (data disks)            │
│     ├── Instance (CPU, memory, disk, network)   │
│     ├── Cloud-init (SSH key + password)         │
│     ├── ISO device (optional)                   │
│     └── PCIe passthrough (optional)             │
│                                                 │
│  outputs.tf ─→ VM info (IPs, status, disks)     │
└────────────────────────────────────────────────┘
```

Each ring uses a separate `.tfvars` file:

- `ring0.tfvars` — Foundational VMs (TrueNAS, Samba4 AD DC)
- `ring1.tfvars` — Operations VMs (k3s nodes, application servers)
- `ring2.tfvars` — Utility VMs/containers (future)

### Secrets Management

All secrets are managed through **1Password** with two integration patterns:

#### Ansible — `community.general.onepassword` Lookup

Ansible resolves secrets at runtime using the 1Password lookup plugin. A vault file (`group_vars/all/secrets-vault.yaml`) maps `vault_*` variables to 1Password items:

```yaml
# Example structure (not actual values)
vault_incus_root_password: "{{ lookup('community.general.onepassword', 'incus-root', vault='HomeLab') }}"
vault_router_admin_password: "{{ lookup('community.general.onepassword', 'mikrotik-admin', vault='HomeLab') }}"
vault_samba4_admin_password: "{{ lookup('community.general.onepassword', 'samba4-admin', vault='HomeLab') }}"
```

#### Terraform — `1Password/onepassword` Provider

Terraform resolves VM root passwords from 1Password using data sources. Each VM definition in `.tfvars` references a vault, item, and field:

```hcl
# Example structure (not actual values)
vms = {
  "my-vm" = {
    root_pwd_vault      = "HomeLab"
    root_pwd_vault_item = "my-vm-root"
    root_pwd_vault_field = "password"
    # ...
  }
}
```

#### Authentication

Both tools authenticate via the `OP_SERVICE_ACCOUNT_TOKEN` environment variable. Use the helper script to create time-limited sessions:

```bash
eval $(./scripts/op-session.sh 2h prod)   # 2-hour production session
eval $(./scripts/op-session.sh 1h test)   # 1-hour test session
```

### Playbook-to-Ring Mapping

| Playbook | Ring | Purpose |
|----------|------|---------|
| `prepare-localhost.yaml` | — | Install control host packages |
| `all-base/bootstrap-machines.yaml` | — | Bootstrap OS packages on all hosts |
| `all-base/upgrade-machines.yaml` | — | Safe OS upgrades (serial: 1) |
| `ring0/networking-mikrotik.yaml` | 0 | Generate router bootstrap scripts |
| `ring0/host-incus-image-unified.yaml` | 0 | Generate unified autoinstall ISO |
| `ring0/identity-samba4-addc-setup.yaml` | 0 | Provision Samba4 AD DC |
| `ring0/storage-truenas-scale-fundamental-config.yaml` | 0 | Initial TrueNAS configuration |
| `ring0/storage-vm-incus-truenas-find-disk-pci.yaml` | 0 | Discover PCI-to-disk mappings |
| `ring0a/networking-mikrotik-continuous-configure-all.yaml` | 0a | Continuous router configuration |
| `ring0a/networking-mikrotik-continuous-cleanup.yaml` | 0a | Remove orphaned router entries |
| `ring0a/host-incus-update.yaml` | 0a | Incus node maintenance |
| `ring0a/host-incus-import-iso.yaml` | 0a | Import ISO images to Incus |
| `ring0a/identity-lifecycle.yaml` | 0a | Identity user/group lifecycle |
| `ring0a/storage-truenas-configure.yaml` | 0a | Ongoing TrueNAS dataset/share config |
| `ring1/create-k8s-cluster.yaml` | 1 | Deploy k3s Kubernetes cluster |
| `ring2/apps-truenas-syncthing.yaml` | 2 | Deploy Syncthing on TrueNAS |

## Further Reading

- [Principles & Ring Model](01-principles.md) — Design principles and dependency rules
- [Environment Setup](03-environment-setup.md) — How to prepare the Ansible control host
- [Terraform Architecture](terraform/INDEX.md) — Detailed Terraform module documentation
