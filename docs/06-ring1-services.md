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
- **Deployment**: VM on Incus (HAOS image)
- **Dependencies**: Ring 0 (networking, compute, **step-ca for TLS**), Ring 1 (MQTT broker, MariaDB recorder)
- **Playbook**: `playbooks/ring1/apps-homeassistant-configure.yaml`

The HA configure playbook deploys `configuration.yaml`, MQTT entities, automations, the MariaDB recorder DSN, and (when enabled) a TLS cert issued by step-ca. It renders a `homeassistant:` block with `internal_url` (and optionally `external_url`) so HA does not surface "Invalid local network URL" once HTTPS is on.

Minimal env override to enable HTTPS via step-ca for the HA UI (envtest example):

```yaml
# configs/envtest/inventory/group_vars/home_assistant/apps-homeassistant-configuration.yaml
ha_tls_enabled:      true
ha_tls_issuer:       "stepca"      # or "selfsigned"
ha_tls_validity_days: 365          # must be ≤ step_ca_leaf_validity_days
ha_tls_cert_filename: "ha-stepca.crt"
ha_tls_key_filename:  "ha-stepca.key"

# Each entry must satisfy the step-ca SAN policy (see Ring 0a section 5).
# First entry becomes the cert CN.
ssl_cert_names:
  - "test-homeassistant.local"
  - "test.homeassistant.{{ localdomain }}"

# Optional: pin the HA internal URL to a specific SAN (defaults to ssl_cert_names[0]).
ha_internal_url: "https://test.homeassistant.{{ localdomain }}:8123"
```

Re-running the playbook after changing `ssl_cert_names` or `ha_tls_validity_days` triggers re-issuance via the shared `tasks/pki/issue-cert-stepca.yaml` primitive (described below).

---

## Shared Primitives — `playbooks/tasks/pki/`

Two reusable task includes give Ring 1 / Ring 2 service playbooks a uniform contract for obtaining an X.509 leaf certificate without duplicating crypto code.

### Contract (inputs / outputs, both primitives)

| Variable | Direction | Meaning |
|----------|-----------|---------|
| `pki_cert_dir` | in | Controller directory where cert + key live (e.g. `{{ playbook_dir }}/.../ssl`) |
| `pki_cert_filename` | in | Filename for the leaf cert (e.g. `ha-stepca.crt`) |
| `pki_key_filename` | in | Filename for the private key (e.g. `ha-stepca.key`) |
| `pki_cert_cn` | in | CN for the certificate subject (also a SAN) |
| `pki_cert_sans` | in | List of DNS SANs (CN is added automatically if missing) |
| `pki_cert_validity_days` | in | Requested leaf lifetime in days |
| `pki_cert_key_size` | in | RSA key size in bits (e.g. `2048`, `4096`) |
| `pki_cert_changed` | out | `true` when a new cert was written this run, `false` when an existing cert was reused |

### `tasks/pki/issue-cert-selfsigned.yaml`

Generates an RSA key + self-signed cert entirely on the controller via `community.crypto`. Idempotent: reuses the existing cert when it has matching SANs and ≥ 1/3 of its requested lifetime remaining. Use for local-only services or as a fallback when step-ca is unavailable.

### `tasks/pki/issue-cert-stepca.yaml`

Generates the RSA key + CSR on the controller, then pushes the CSR + JWK provisioner password into the step-ca container and runs `step ca sign` to obtain the leaf. Pulls the signed cert back to the controller, sets `0644`, and cleans the container scratch directory.

Idempotency probe skips issuance when **all** of the following hold:

- Cert and key files exist on the controller and were not regenerated this run.
- DNS SAN set on the existing cert (sorted) matches the desired SAN set.
- Issuer CN contains `step_ca_intermediate_cn`.
- Validity remaining > `pki_cert_validity_days / 3` days.

Requires Ring 0 step-ca bootstrap and Ring 0a `pki-stepca-configure.yaml` to have completed at least once (so the JWK provisioner exists). The primitive uses `step_ca_url`, `step_ca_steppath`, `step_ca_jwk_provisioner_name`, and `step_ca_target_remote` from inventory.

### Usage in a service playbook

```yaml
- name: Issue TLS cert for my-service
  ansible.builtin.include_tasks: "{{ playbook_dir }}/../tasks/pki/issue-cert-stepca.yaml"
  vars:
    pki_cert_dir:           "{{ playbook_dir }}/../../configs/envtest/inventory/my_service_files/ssl"
    pki_cert_filename:      "myservice.crt"
    pki_key_filename:       "myservice.key"
    pki_cert_cn:            "myservice.{{ localdomain }}"
    pki_cert_sans:          ["myservice.{{ localdomain }}"]
    pki_cert_validity_days: 90
    pki_cert_key_size:      2048
```

Swap the include path to `issue-cert-selfsigned.yaml` to fall back without changing any other variables.

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
