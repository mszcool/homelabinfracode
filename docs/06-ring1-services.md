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

#### Marketplace and entity ownership

- The playbook targets Home Assistant Core 2026.11 or newer and does not install or manage HACS. Upgrade/migrate HACS through Home Assistant before running it.
- Install and start the community **Advanced SSH & Web Terminal** app (`a0d7b954_ssh`). Configure its SSH username to match `ansible_user` in the environment's Home Assistant inventory (currently `root`, not the app's default), and add the public key from the vault to `ssh.authorized_keys`. Ensure Ansible has access to the matching private key. Set the app's external SSH port to the inventory's `ansible_port` and connect Ansible to that port.
- Configure the app's `packages` option as `[python3, py3-websockets]` (websockets 12 or later). The Marketplace client runs inside the app using its Supervisor token and the app's `homeassistant_api: true` permission. The official **Terminal & SSH** app (`core_ssh`) lacks this permission, so its token cannot authenticate to the Core API proxy, even if Python is installed. If both apps are present, ensure the inventory port reaches the community app. Marketplace must be enabled and ready.
- **Consent:** the playbook accepts the Marketplace third-party-code warning for the Supervisor user on the administrator's behalf. This acceptance is per user; other users may still see the warning. Only run it when you accept that risk.
- `ha_marketplace_components` lists Marketplace integrations and dashboard cards. Unknown repositories are added as custom repositories; connect GitHub to Marketplace first when custom repositories are needed. The specified release tag is used for a first install only; installed versions are left under Marketplace control. Integration setup flows and credentials still require the manual steps shown by the playbook. Marketplace reconciliation is skipped in Ansible check mode. Check Home Assistant Repairs for any remaining Marketplace restart request, including the first creation of the `www` directory.
- **Connect GitHub before the first run:** without a GitHub connection, Marketplace uses anonymous GitHub API requests (60 per hour per public IP). A fresh install can exceed this and fail with `github_rate_limited`. To start the GitHub sign-in on a fresh instance, open **Settings → Marketplace**, choose **Add from link** (custom repository), and enter an existing repository URL such as Huawei Solar (`https://github.com/wlcrs/huawei_solar`). Complete the GitHub device sign-in when prompted. Huawei Solar is already in the Marketplace catalog, so this only connects GitHub. If Marketplace then says the repository already exists, ignore that message. Then run the playbook.
- Marketplace reconciliation ensures configured repositories and components are present; it does not enforce version pins for existing installations or uninstall components and remove repositories omitted from inventory.
- If an installation fails after Marketplace has marked the component installed, a later run skips reinstalling it. Inspect the Marketplace state and Home Assistant logs and resolve the failure manually; a rerun alone does not guarantee recovery.
- Repository information queries can refresh metadata and clear the Marketplace "new" flag even when the playbook reports no change.
- For an existing MQTT integration, the playbook manages only broker, port, username and password. Protocol, options, subentries and other metadata are retained; unmanaged subentries can therefore still produce entities. It creates a minimal broker entry if none exists.
- Managed MQTT and template entities set `default_entity_id` to their expected ID. This is a creation default, not a rename: existing registry IDs remain unchanged, and an ID already in use may get a suffix. Integration/Riemann sensors and utility meters do not support this option in 2026.11; they continue to use their configured names/keys and existing registry identities. Input booleans use their YAML keys. Discovered and otherwise externally managed entities remain outside this ID policy.

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
