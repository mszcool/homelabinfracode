# Homelab Infrastructure as Code

Infrastructure as Code (IaC) for a production-grade homelab using a layered ring architecture. The project automates the provisioning and continuous configuration of networking, compute, storage, identity, and application services using **Ansible** and **Terraform**, with secrets managed through **1Password**.

## Ring Architecture

The homelab follows a strict layered dependency model where higher rings depend on lower rings, but **never** the reverse:

| Ring | Purpose | Automation | Examples |
|------|---------|------------|----------|
| **Ring 0** | Foundational infrastructure | Semi-automated (requires manual steps) | MikroTik router, Incus compute nodes, TrueNAS storage, Samba4 AD DC |
| **Ring 0a** | Continuous config of Ring 0 | Fully automated (GitOps-ready) | Firewall rules, DNS/DHCP, Incus cert rotation, TrueNAS datasets, identity lifecycle |
| **Ring 1** | Essential operations services | Fully automated | Kubernetes (k3s), MQTT brokers, Authentik, Home Assistant |
| **Ring 2** | Non-essential apps | Fully automated | Syncthing, Paperless NGX, TrueNAS companion apps |

## Key Principles

- **Layer inversion prevention**: Lower rings never depend on higher rings
- **Idempotent automation**: All playbooks and Terraform modules can be re-run safely
- **Secrets in vaults**: All sensitive data lives in 1Password, never in Git
- **Dual repository**: Public samples in `configs/`, production secrets in `configs.private/` (Git submodule)

## Documentation Index

Detailed documentation is organized in the [`docs/`](docs/) folder:

| Document | Description |
|----------|-------------|
| [Principles & Ring Model](docs/01-principles.md) | Core design principles, ring model, dependency rules |
| [Architecture Overview](docs/02-architecture.md) | Infrastructure components, automation structure, secrets management |
| [Environment Setup](docs/03-environment-setup.md) | How to prepare an Ansible control host for running playbooks and Terraform |
| [Ring 0 — Initial Setup](docs/04-ring0-setup.md) | Semi-automated bootstrap of foundational infrastructure |
| [Ring 0a — Continuous Config](docs/05-ring0a-automated.md) | Fully automated day-2 operations for Ring 0 services |
| [Ring 1 — Operations Services](docs/06-ring1-services.md) | Essential virtualized/containerized services (placeholder) |
| [Ring 2 — Application Services](docs/07-ring2-services.md) | Non-essential apps and containers |

### Reference Documentation

Additional reference material for specific subsystems:

| Document | Description |
|----------|-------------|
| [Unified ISO Generation](docs/incus-host/README-unified-iso.md) | How the multi-server unified autoinstall ISO works |
| [Incus Client Certificates](docs/incus-host/incus-client-certificates.md) | TLS certificate management for Incus remote access |
| [TrueNAS VM on Incus](docs/incus-host/vm-incus-truenas-guide.md) | Deploying TrueNAS Scale VMs with PCIe passthrough |
| [Samba4 AD DC Guide](docs/identity-addc/INDEX.md) | Complete Samba4 Active Directory setup and management |
| [Terraform Architecture](docs/terraform/INDEX.md) | Terraform module design, quickstart, and migration guide |
| [Cloud-Init Password Fix](docs/incus-host/CLOUD-INIT-CHPASSWD-FIX.md) | Using chpasswd module for yescrypt hashes |
| [Yescrypt Hashing](docs/incus-host/YESCRYPT-HASHING.md) | Password hashing for Ubuntu 24.04 |

## Repository Structure

```
├── configs/                  # Public sample configurations
│   ├── envbase/              # Base inventory (group hierarchy + group_vars)
│   ├── envtest/              # Test environment (tfvars + host inventory)
│   └── incus/                # Incus preseed and profile templates
├── configs.private/          # Production configs (Git submodule, not public)
├── docs/                     # All detailed documentation
├── playbooks/
│   ├── all-base/             # Cross-ring: bootstrap and upgrade
│   ├── ring0/                # Initial infrastructure setup
│   ├── ring0a/               # Continuous Ring 0 configuration
│   ├── ring1/                # Operations services
│   ├── ring2/                # Application services
│   └── tasks/                # Shared task includes
├── scripts/                  # Helper scripts (1Password sessions, validation, certs)
├── terraform/                # Terraform root module + VM module
│   └── modules/vm/           # Reusable VM provisioning module
└── virtualmachines/          # Legacy/alternate VM configs (Hyper-V, Incus)
```

## Quick Start

```bash
# 1. Prepare the Ansible control host
./initAnsibleHost.sh

# 2. Start a 1Password session
eval $(./scripts/op-session.sh 2h prod)

# 3. Run a playbook (example: continuous router config)
ansible-playbook -i configs/envbase/ -i configs.private/envprod/inventory/ \
    playbooks/ring0a/networking-mikrotik-continuous-configure-all.yaml

# 4. Run Terraform (example: Ring 0 VMs)
cd terraform
terraform init
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
```

## License

See [LICENSE](LICENSE) for details.
