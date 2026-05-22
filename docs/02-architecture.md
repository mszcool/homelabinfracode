# Architecture Overview

This document covers both the infrastructure architecture (what physical and logical components make up the homelab) and the automation architecture (how Ansible playbooks, Terraform modules, inventory, and secrets management are structured).

## Infrastructure Architecture

### Physical Topology

```
                    ┌──────────────┐
                    │   Internet   │
                    └──────┬───────┘
                           │ WAN
                    ┌──────┴──────┐
                    │  MikroTik   │
                    │   Router    │
                    │ (Ring 0)    │
                    └──────┬──────┘
                           │ LAN / VLANs
            ┌──────────────┼──────────────┐
            │              │              │
     ┌──────┴──────┐┌──────┴──────┐┌──────┴──────┐
     │ Incus Node 1││ Incus Node 2││ Edge Devices│
     │ (compute)   ││ (compute)   ││ (Raspberry  │
     │             ││             ││  Pi bridge) │
     └──────┬──────┘└──────┬──────┘└─────────────┘
            │              │
     ┌──────┴──────────────┴──────┐
     │     Virtual Machines       │
     │  ┌─────────┐ ┌──────────┐  │
     │  │TrueNAS  │ │ Samba4   │  │
     │  │Scale VM │ │ AD DC VM │  │
     │  │(storage)│ │(identity)│  │
     │  └─────────┘ └──────────┘  │
     │  ┌─────────┐ ┌──────────┐  │
     │  │ k3s     │ │ App VMs  │  │
     │  │ cluster │ │ (Ring 1) │  │
     │  └─────────┘ └──────────┘  │
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
| **step-ca** | Internal X.509 Certificate Authority (root + intermediate) | OCI container on Incus | Root key in 1Password, intermediate key in container $STEPPATH volume |
| **Edge Devices** | WiFi bridging (optional) | Raspberry Pi | Bridge remote network segments |

#### Ring 1 — Operations Components

| Component | Role | Type | Notes |
|-----------|------|------|-------|
| **k3s Cluster** | Kubernetes orchestration | VMs on Incus | Lightweight k8s for containerized workloads |
| **Authentik** | OAuth/OIDC SSO provider | Container (planned) | Security token service |
| **MQTT Broker** | Event messaging | Container | IoT and home automation messaging (Mosquitto) |
| **Home Assistant** | Home automation | VM on Incus | TLS via step-ca (Ring 0), MQTT broker, MariaDB recorder |

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

### PKI Architecture

`step-ca` (Smallstep) runs as an OCI container on Incus and acts as the internal Certificate Authority for the homelab. It is a Ring 0 *peer* of identity/storage/networking — never consumed by Incus or Samba4 themselves (see the layering invariant in [01-principles.md](01-principles.md)).

- **Two-tier hierarchy**: a long-lived **Root CA** (NIST P-384, 10 years) signs a shorter-lived **Intermediate CA**, which signs leaf certificates for services.
- **Root key custody**: the encrypted Root CA private key lives only as a 1Password document attachment (`rootcakeyenc` on item `Step CA Root <env_id>`). It is never written to a container or VM. The public Root CA cert is published to `configs/envbase/pki/homelab-<env_id_lower>-root-ca.crt` so it can be imported on client devices.
- **Intermediate key custody**: lives inside the step-ca container's persistent `$STEPPATH` volume (a dedicated Incus storage volume), encrypted with the passphrase from `vault_step_ca.intermediate_password` in 1Password.
- **Provisioner**: a single **JWK provisioner** (named via `step_ca_jwk_provisioner_name`) authenticates issuance requests with a password from 1Password. The JWK key pair itself is also backed up to 1Password as document attachments so that destroying the container does not require rotating the provisioner.
- **Trust distribution**: clients (browsers, OS keychains, mobile devices) only need to import the **Root CA** public cert once. Leaves are served with the intermediate appended, so the chain validates without per-leaf trust.
- **SAN policy**: enforced by step-ca on every issuance request. step-ca requires the wildcard `*` to be the leading label and only allows one wildcard per rule, so deeper service names are covered by enumerating per-service entries like `*.homeassistant.<localdomain>`.
- **Issuance integration**: Ring 1 / Ring 2 service playbooks call the shared primitive `playbooks/tasks/pki/issue-cert-stepca.yaml` (or the local-only fallback `issue-cert-selfsigned.yaml`) to request a cert; the primitive handles CSR generation on the controller, signing inside the step-ca container, and idempotent reuse of unexpired certs.

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
│   ├── tasks/                       # Cross-ring reusable task primitives
│   │   └── pki/                     # Cert issuance primitives (stepca, selfsigned)
│   ├── ring0/                       # Initial infrastructure setup
│   │   ├── templates/               # Jinja2 templates (RouterOS, autoinstall, Incus, ca.json)
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
    ├── main.tf                      # Root module (VM + container loops, workspace check)
    ├── variables.tf                 # Input variable definitions (incus_project, vms, docker_containers)
    ├── providers.tf                 # Incus + 1Password provider config
    ├── versions.tf                  # Version constraints
    ├── locals.tf                    # Computed identifiers
    ├── outputs.tf                   # VM + container output information
    └── modules/
        ├── vm/                      # Reusable VM module
        │   ├── main.tf              # VM resource definition
        │   └── variables.tf         # VM input parameters
        └── docker_container/        # Docker/OCI container module
            ├── main.tf              # Container + volume resources
            └── variables.tf         # Container input parameters
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

Terraform manages VM and container provisioning on Incus. The architecture separates concerns into ring-specific variable files, with state isolated per ring using Terraform workspaces:

```
┌─────────────────────────────────────────────────┐
│  terraform/                                     │
│                                                 │
│  versions.tf ─→ providers.tf ─→ variables.tf    │
│                                       │         │
│                                  locals.tf      │
│                                       │         │
│  main.tf ─────────────────────────────┘         │
│     │                                           │
│     │  check "workspace_not_default"            │
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
│     for_each var.docker_containers              │
│     ▼                                           │
│  modules/docker_container/                      │
│     ├── Storage volumes (persistent data)       │
│     └── Container (OCI image, network, env)     │
│                                                 │
│  outputs.tf ─→ VM + Container info              │
└─────────────────────────────────────────────────┘
```

Each ring uses a **separate Terraform workspace** for state isolation:

- `ring0.tfvars` → workspace `ring0` → `incus_project = "prodlayer0"` — Foundational VMs (TrueNAS, Samba4 AD DC)
- `ring1.tfvars` → workspace `ring1` → `incus_project = "prodlayer1"` — Operations VMs + containers (k3s nodes, MQTT broker)
- `ring2.tfvars` → workspace `ring2` → `incus_project = "default"` — Utility VMs/containers

State is stored under `terraform.tfstate.d/<workspace>/terraform.tfstate`. This ensures that the ring1 identity (which manages `prodlayer1`) cannot accidentally access ring0 resources in `prodlayer0`.

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
| `ring0/pki-stepca-bootstrap-root.yaml` | 0 | Generate Root CA (controller-side), store encrypted key in 1Password |
| `ring0/pki-stepca-bootstrap.yaml` | 0 | Initialise `$STEPPATH` and Intermediate CA inside the step-ca container |
| `ring0a/networking-mikrotik-continuous-configure-all.yaml` | 0a | Continuous router configuration |
| `ring0a/networking-mikrotik-continuous-cleanup.yaml` | 0a | Remove orphaned router entries |
| `ring0a/host-incus-update.yaml` | 0a | Incus node maintenance |
| `ring0a/host-incus-import-iso.yaml` | 0a | Import ISO images to Incus |
| `ring0a/identity-lifecycle.yaml` | 0a | Identity user/group lifecycle |
| `ring0a/storage-truenas-configure.yaml` | 0a | Ongoing TrueNAS dataset/share config |
| `ring0a/pki-stepca-configure.yaml` | 0a | Reconcile JWK provisioner, SAN policy, and leaf-duration claims on step-ca |
| `ring1/create-k8s-cluster.yaml` | 1 | Deploy k3s Kubernetes cluster |
| `ring1/apps-homeassistant-configure.yaml` | 1 | Configure Home Assistant (TLS via step-ca, MQTT, recorder) |
| `tasks/pki/issue-cert-stepca.yaml` | — | Shared primitive: request a leaf cert from step-ca |
| `tasks/pki/issue-cert-selfsigned.yaml` | — | Shared primitive: generate a self-signed leaf cert on the controller |
| `ring2/apps-truenas-syncthing.yaml` | 2 | Deploy Syncthing on TrueNAS |

## Further Reading

- [Principles & Ring Model](01-principles.md) — Design principles and dependency rules
- [Environment Setup](03-environment-setup.md) — How to prepare the Ansible control host
- [Terraform Architecture](terraform/INDEX.md) — Detailed Terraform module documentation
