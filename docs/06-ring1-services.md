# Ring 1 — Essential Operations Services

> **Status**: Ring 1 is under active development. This document outlines the current state and planned services.

Ring 1 contains services that are essential for day-to-day homelab operations. They are built **on top of** Ring 0 infrastructure (compute, storage, networking, identity) and are either virtualized or containerized — never bare metal.

Ring 1 respects the [layer inversion principle](01-principles.md): these services depend on Ring 0, but Ring 0 must never depend on Ring 1. If all Ring 1 services fail, the foundational infrastructure continues operating.

## Current Implementation

### Kubernetes Cluster (k3s)

The only Ring 1 playbook currently implemented deploys a lightweight k3s Kubernetes cluster:

```bash
eval $(./scripts/op-session.sh 2h prod)

# Provision Ring 1 VMs and containers with Terraform
cd terraform
terraform workspace select ring1
terraform plan -var-file="../configs.private/envprod/ring1.tfvars"
terraform apply -var-file="../configs.private/envprod/ring1.tfvars"
cd ..

# Deploy k3s cluster
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring1/create-k8s-cluster.yaml
```

The playbook:

1. **Bootstraps all target hosts** with base packages
2. **Installs k3s on master nodes**: Downloads the k3s installer, configures cluster CIDR and CNI, starts the service
3. **Retrieves cluster credentials**: Extracts the node token and kubeconfig from the master
4. **Installs k3s agents**: Joins agent nodes to the cluster using the master's node token
5. **Copies kubeconfig**: Writes the kubeconfig to the control host for `kubectl` access

#### Configuration

- **Terraform** (`ring1.tfvars`): Defines k3s master and agent VMs (CPU, memory, disk, network)
- **Inventory**: Maps VMs to `k3smaster` and `k3sagents` groups
- **Playbook variables**: `cluster_config`, `k3s_version`, `pod_network_cidr`, `pod_network_plug_in`

#### Force Reinstall

To reinstall k3s on existing nodes:

```bash
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring1/create-k8s-cluster.yaml \
    -e force_install=true
```

## Planned Services

The following Ring 1 services are planned but not yet implemented:

### MQTT Message Broker (Mosquitto)

- **Purpose**: Event-driven messaging backbone for IoT and home automation
- **Deployment**: Docker/OCI container on Incus via Terraform (`docker_containers` in `ring1.tfvars`)
- **Image**: `docker:library/eclipse-mosquitto:2`
- **Dependencies**: Ring 0 (networking, compute)
- **Status**: Defined in `configs.private/envprod/ring1.tfvars`, deployed via `terraform workspace select ring1 && terraform apply`

### Security Token Service (Authentik)

- **Purpose**: OAuth 2.0 / OpenID Connect SSO provider
- **Deployment**: Container on k3s
- **Dependencies**: Ring 0 (identity from Samba4 AD, compute, storage for database)

### Home Assistant

- **Purpose**: Home automation hub
- **Deployment**: VM or container on Incus
- **Dependencies**: Ring 0 (networking, compute), Ring 1 (MQTT broker)

---

## Ring 1 Design Guidelines

When implementing new Ring 1 services:

1. **VMs are provisioned via Terraform** using `ring1.tfvars` — define the VM in the `vms` map, then `terraform workspace select ring1 && terraform apply`
2. **Docker/OCI containers are provisioned via Terraform** using `ring1.tfvars` — define the container in the `docker_containers` map, using the `docker_container` module
3. **Always use the `ring1` workspace** — this ensures state isolation from ring0 (foundational infrastructure) and ring2 (utility services)
4. **Service configuration uses Ansible** — create a playbook in `playbooks/ring1/` that configures the service after VM/container provisioning
5. **Depend only on Ring 0**: Use Incus for compute, TrueNAS for persistent storage, MikroTik for network/DNS, Samba4 for identity
6. **Never create Ring 0 dependencies on Ring 1**: If a Ring 1 service needs DNS, it gets entries from the router (Ring 0), not from a Ring 1 DNS service
7. **All playbooks must be idempotent**: Safe to re-run at any time

## Further Reading

- [Principles & Ring Model](01-principles.md) — Ring dependency rules
- [Ring 0 Setup](04-ring0-setup.md) — Prerequisites for Ring 1
- [Ring 0a Automated](05-ring0a-automated.md) — Continuous config that Ring 1 depends on
- [Ring 2 Services](07-ring2-services.md) — Non-essential apps built on Ring 1
