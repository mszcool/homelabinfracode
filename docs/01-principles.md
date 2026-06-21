# Principles & Ring Model

This document describes the core design principles behind the homelab infrastructure-as-code project and explains the ring-based layered architecture that governs all service dependencies and automation decisions.

## The Ring Model

Infrastructure and services are organized into concentric rings. Each ring represents a layer of the homelab stack, ordered by how foundational the services are to overall operations.

```
┌─────────────────────────────────────────────────────┐
│  Ring 2 — Non-essential apps (Syncthing, Paperless) │
│  ┌─────────────────────────────────────────────┐    │
│  │  Ring 1 — Operations (k8s, Authentik, MQTT) │    │
│  │  ┌─────────────────────────────────────┐    │    │
│  │  │  Ring 0a — Automated continuous     │    │    │
│  │  │  config of Ring 0 services          │    │    │
│  │  │  ┌─────────────────────────────┐    │    │    │
│  │  │  │  Ring 0 — Foundational      │    │    │    │
│  │  │  │  (compute, storage, network,│    │    │    │
│  │  │  │   identity)                 │    │    │    │
│  │  │  └─────────────────────────────┘    │    │    │
│  │  └─────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

### Ring 0 — Foundational Infrastructure

Ring 0 contains the physical and logical foundation that everything else depends on:

- **Networking**: MikroTik router — VLANs, DHCP, DNS, firewall, site-to-site VPN
- **Compute**: Incus virtualization nodes — bare-metal servers running Ubuntu with Incus for VMs and containers
- **Storage**: TrueNAS Scale — primary NAS providing SMB/NFS shares, dataset hierarchies, and snapshots
- **Identity**: Samba4 Active Directory Domain Controller — centralized user/group management, DNS, Kerberos authentication
- **PKI**: `step-ca` instance — internal Certificate Authority (root + intermediate) used to issue X.509 certs to Ring 0a / Ring 1 / Ring 2 services. The root CA private key never leaves 1Password (encrypted at rest); only the intermediate CA key lives in the running container.

**Layering invariant for PKI**: Incus and the Samba4 AD DC **must never consume step-ca certificates**. They keep their existing self-signed / internal-trust models so that a step-ca outage cannot cascade into the foundational layer. step-ca is a Ring 0 *peer*, not a Ring 0 dependency for the other foundational components.

**Automation characteristics**: Ring 0 setup is **not fully automated**. Bootstrapping bare-metal hardware, flashing router firmware, and initial OS installation require manual intervention. This is intentional — fully automating Ring 0 would require additional services (PXE boot infrastructure, out-of-band management controllers) that are not yet available in this homelab. The playbooks generate artifacts (RouterOS scripts, autoinstall ISOs) that must be applied manually during initial setup.

### Ring 0a — Continuous Configuration of Ring 0

Ring 0a represents the **day-2 operations** for Ring 0 services. Once the foundational infrastructure is bootstrapped, Ring 0a playbooks handle all ongoing configuration changes:

- Continuous firewall rule management, device/DNS/MAC/IP configuration on the router
- Incus cluster maintenance: client certificate rotation, ISO image updates, OS patching
- TrueNAS dataset creation, ACL management, share configuration
- Identity lifecycle: user/group creation, password management, organizational unit maintenance
- PKI reconciliation: step-ca provisioner (JWK) install, SAN policy + leaf-validity claims, container recovery when the CA has crash-looped on a bad config

**Automation characteristics**: Ring 0a is **fully automated** and designed to be triggered by GitOps workflows. Every playbook is idempotent and can be re-run safely at any time. Changes to inventory files (device lists, firewall rules, dataset definitions, user accounts, CA SAN policy) are applied by running the corresponding playbook.

### Ring 1 — Essential Operations Services

Ring 1 contains services that are essential for day-to-day homelab operations but are built **on top of** Ring 0 infrastructure. These services are either virtualized or containerized — never bare-metal:

- **Kubernetes cluster (k3s)**: Container orchestration for workloads
- **MQTT message brokers**: Event-driven communication backbone
- **Security Token Services**: OAuth/OIDC providers like Authentik for SSO
- **Home Assistant**: Home automation hub

Ring 1 services depend on Ring 0 for compute (VMs on Incus), storage (NFS/SMB mounts from TrueNAS), networking (VLANs and firewall rules from MikroTik), and identity (AD accounts from Samba4).

### Ring 2 — Non-Essential Applications

Ring 2 contains applications that are convenient but not critical. If a Ring 2 service goes down, it is an inconvenience — not an operational failure:

- **Syncthing**: File synchronization across devices
- **Paperless NGX**: Document management and OCR (future)
- **TrueNAS companion apps**: Supplementary storage utilities

Ring 2 services are predominantly containers. They may store data on TrueNAS and authenticate through the identity provider, but their absence does not affect core homelab operation.

## The Layer Inversion Principle

**Services from higher rings may depend on services from lower rings. Services from lower rings MUST NEVER depend on services from higher rings.**

This is the single most important architectural constraint. It ensures:

1. **Ring 0 is self-sufficient**: The foundational layer can operate independently. Router, compute nodes, storage, and identity do not require Kubernetes, containers, or applications to function.
2. **Failure isolation**: If Ring 2 fails, Ring 1 and Ring 0 continue operating. If Ring 1 fails, Ring 0 continues operating.
3. **Recovery ordering**: Disaster recovery proceeds from the inside out — restore Ring 0 first, then Ring 1, then Ring 2.
4. **Predictable dependencies**: An operator can always reason about what a service depends on by looking at its ring number.

### Valid dependency examples

```
Ring 2 (Syncthing) --> Ring 0 (TrueNAS for storage)     OK
Ring 1 (k3s)       --> Ring 0 (Incus VMs, AD identity)  OK
Ring 2 (Paperless) --> Ring 1 (k8s for orchestration)    OK
```

### Invalid dependency examples

```
Ring 0 (Router)    --> Ring 1 (k8s for DNS)              VIOLATION
Ring 0 (TrueNAS)   --> Ring 2 (monitoring app)           VIOLATION
Ring 1 (k3s)       --> Ring 2 (utility container)        VIOLATION
```

## Idempotency

All automation — Ansible playbooks and Terraform modules — must be **as idempotent as possible**:

- Running a playbook twice with the same inventory produces the same end state
- Terraform plans show no changes when infrastructure matches the desired state
- Playbooks check existing state before making changes (e.g., skip AD provisioning if `sam.ldb` exists, skip ISO import if volume already matches)
- Destructive operations (deleting orphaned firewall rules, removing identity objects) require explicit confirmation flags like `-e delete_confirmed=true`

This principle ensures operators can safely re-run automation at any time without fear of breaking existing infrastructure.

### Idempotency under `terraform destroy && terraform apply`

Long-lived secrets and trust anchors (root CA private key + public cert, JWK provisioner key material, AD secrets) live in 1Password and in `configs/envbase/pki/` (public certs only), **not** on the destroyed VMs/containers. After a full destroy + re-apply of an environment, re-running the Ring 0 and Ring 0a playbooks reuses the existing root CA from 1Password, regenerates the intermediate CA inside the fresh container, and restores the JWK provisioner from its 1Password backup. End-user devices keep trusting the same root — no per-device re-import is needed.

## Dual-Repository Security Model

The project uses two repositories to separate public samples from production secrets:

- **`configs/`** — Public sample configurations committed to the main repository. These contain realistic structure but use test values and example data.
- **`configs.private/`** — Production configurations in a separate private repository, mounted as a Git submodule. Contains actual IP addresses, passwords references, vault item names, and host-specific details.

No production secrets are ever committed to the public repository. All sensitive values are resolved at runtime from 1Password vaults.

## Further Reading

- [Architecture Overview](02-architecture.md) — Infrastructure components and automation structure
- [Environment Setup](03-environment-setup.md) — Preparing the Ansible control host
- [Ring 0 Setup](04-ring0-setup.md) — Bootstrap procedures for foundational infrastructure
- [Ring 0a Automated](05-ring0a-automated.md) — Continuous configuration playbooks
