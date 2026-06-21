# Ring 0a — Continuous Configuration (Automated)

Ring 0a playbooks handle **ongoing, day-2 operations** for Ring 0 infrastructure. Unlike Ring 0 setup playbooks (which are semi-automated), Ring 0a playbooks are **fully automated, idempotent**, and designed to be triggered by GitOps workflows.

The workflow is simple: update the inventory/configuration, then run the corresponding playbook. The playbook compares the desired state from inventory against the current state of the target system and applies only the necessary changes.

> **Prerequisites**: Ring 0 infrastructure must be set up first. See [Ring 0 Setup](04-ring0-setup.md).

## Overview

| Playbook | Target | Purpose |
|----------|--------|---------|
| `networking-mikrotik-continuous-configure-all.yaml` | MikroTik router | Apply full router config (VLANs, DHCP, DNS, firewall) |
| `networking-mikrotik-continuous-cleanup.yaml` | MikroTik router | Remove orphaned entries no longer in inventory |
| `host-incus-update.yaml` | Incus compute nodes | Certificate rotation, UFW, OS updates |
| `host-incus-import-iso.yaml` | Incus compute nodes | Import/update ISO images in Incus storage |
| `identity-lifecycle.yaml` | Samba4 AD DC | User/group/OU lifecycle management |
| `storage-truenas-configure.yaml` | TrueNAS Scale | Datasets, ACLs, shares, services |
| `pki-stepca-configure.yaml` | step-ca container | JWK provisioner, SAN policy, leaf-duration claims; self-heals crashed containers |

---

## 1. Continuous Router Configuration

### Applying Configuration

The main continuous configuration playbook connects to the MikroTik router via SSH (using the `community.routeros` collection) and idempotently configures all network resources:

```bash
eval $(./scripts/op-session.sh 2h prod)

ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0a/networking-mikrotik-continuous-configure-all.yaml
```

#### What Gets Configured

- **VLAN interfaces**: Creates VLAN interfaces on the bridge for each defined network segment
- **IP addresses**: Assigns IP addresses to VLAN and bridge interfaces
- **DHCP servers**: Creates DHCP server instances, address pools, and network definitions per VLAN/LAN
- **Static DHCP leases**: Creates per-device static DHCP leases with IP and MAC binding
- **DNS static entries**: Creates DNS A records for each device
- **Device groups**: Creates address lists grouping devices (e.g., "Kids", "IoT") for firewall rules
- **Firewall filter rules**: Applies inbound and outbound firewall rules, organized by named groups with start/end markers
- **Firewall NAT rules**: Applies NAT rules (masquerade, port forwards)
- **Site-to-site VPN**: IPsec VPN configuration (optional, can be enabled in inventory)

#### How It Works

The playbook uses **marker-based rule management**. Each group of firewall rules or resources is bracketed by start/end marker comments in RouterOS. This allows the playbook to:

1. Identify which rules are managed by automation
2. Delete and re-create rule blocks to ensure ordering
3. Leave manually-created rules untouched

### Cleaning Up Orphaned Entries

When devices or rules are removed from inventory, they must be cleaned from the router:

```bash
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0a/networking-mikrotik-continuous-cleanup.yaml
```

This playbook:

- Compares current RouterOS state against inventory definitions
- Identifies orphaned entries (firewall rules, DNS records, DHCP leases, VLANs, DHCP servers, address pools)
- Deletes entries that are managed (have markers) but no longer have matching inventory entries
- Protects WAN/LAN interfaces from accidental deletion

### Configuration Source

All router continuous configuration is driven by inventory under the `mainrouter` group:

- **`configs/envbase/group_vars/mainrouter/networking-foundation.yaml`**:
  - `mainrouterconfig` — Interface and bridge definitions
  - `networks` — LAN and VLAN definitions with DHCP settings
  - `firewall_rules` — Named firewall rule groups with filter and NAT rules
  - Device definitions with MAC addresses, IPs, and group memberships

### Adding a New Device

To add a new device to the network:

1. Add the device entry in the inventory (MAC, IP, hostname, device group)
2. Run the continuous configure playbook — the device gets a static DHCP lease, DNS entry, and is added to the appropriate address list
3. Firewall rules for the device's group apply automatically

### Adding a New Firewall Rule

To add a firewall rule:

1. Add the rule to the appropriate group in `firewall_rules` in the inventory
2. Run the continuous configure playbook — the rule block is re-created with the new rule in the correct position

---

## 2. Continuous Incus Cluster Configuration

### Incus Node Maintenance

The update playbook performs day-2 maintenance on all Incus bare-metal hosts:

```bash
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0a/host-incus-update.yaml
```

#### What Gets Configured

- **Hostname**: Ensures hostname matches inventory
- **Root credentials**: Updates root password and SSH key
- **UFW firewall**: Configures rules (SSH + Incus port allowed, deny inbound, allow outbound)
- **Incus listen address**: Sets the Incus API listen address from the host's physical network adapter IP
- **Server certificate rotation**: Validates the Incus server TLS certificate, rotates if expiring within 180 days or SANs don't match
- **Client certificate management**: Deploys trusted client certificates, removes orphaned certificates, manages project-level access restrictions
- **OS updates**: Runs apt update/upgrade on the hosts

### ISO Image Management

Import or update ISO images (e.g., TrueNAS installer, Ubuntu) into Incus storage volumes:

```bash
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0a/host-incus-import-iso.yaml
```

This playbook:

1. Validates that ISO images are defined in inventory (`iso_images` list)
2. Checks that the Incus client is available on the control host
3. Verifies each host is registered as an Incus remote
4. Imports each ISO into the appropriate storage pool and project using `incus storage volume import`
5. Handles re-imports by deleting existing volumes if the ISO has changed

### Client Certificate Workflow

To add a new client certificate for remote Incus access:

1. Generate the certificate: `./scripts/manage-incus-client-certs.sh generate <name>`
2. Save the public cert to the configs repo
3. Add the certificate reference in the `incus_trusted_clients` section of the inventory
4. Run the Incus update playbook — the certificate is deployed to all Incus nodes with the specified project access

See [Incus Client Certificates](incus-host/incus-client-certificates.md) for the detailed certificate management guide.

### Configuration Source

- **`configs/envbase/group_vars/incus_scope/host-incus-cluster.yaml`**: Incus daemon config, trusted client definitions, ISO images list
- **Environment overlay**: Host IPs, certificate file paths

---

## 3. Continuous TrueNAS Configuration

The TrueNAS configuration playbook manages ongoing storage configuration:

```bash
eval $(./scripts/op-session.sh 2h prod)

ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0a/storage-truenas-configure.yaml
```

### What Gets Configured

- **HDD standby/sleep settings**: Configures power management for HDDs
- **Dataset hierarchies**: Creates datasets recursively with child inheritance (compression, ACL type, record size, quota)
- **Dataset properties**: Sets compression algorithm, ACL type (NFSv4), record size, share type
- **NFSv4 ACLs**: Applies fine-grained access control based on AD groups and users (read, write, execute permissions)
- **SMB shares**: Creates and configures Windows-compatible file shares
- **NFS shares**: Creates and configures Linux-compatible exports
- **Service management**: Ensures CIFS and NFS services are running
- **Quota validation**: Validates that dataset quotas are within pool capacity

### How ACLs Work

The playbook builds NFSv4 ACLs from inventory-defined group and user permissions:

1. Each dataset can define `acl_groups` and `acl_users` with permission levels (read, write, execute)
2. The playbook constructs ACL entries from these definitions
3. ACLs are applied via `midclt call filesystem.setacl` API

This ties directly into the AD domain — groups and users referenced in ACLs must exist in the Samba4 AD DC (managed by the identity lifecycle playbook).

### Adding a New Dataset

To add a new dataset:

1. Add the dataset definition in the inventory under `datasets` with desired properties (compression, ACL type, quotas, ACL groups/users)
2. Child datasets can be nested under parent datasets for inheritance
3. Run the playbook — the dataset is created with all properties and ACLs applied

### Configuration Source

- **`configs/envbase/group_vars/truenas/storage-truenas-configuration.yaml`**: Services, storage pools, dataset definitions with ACLs and share configs
- **Environment overlay**: Pool names, host-specific settings

---

## 4. Continuous Identity Configuration

The identity lifecycle playbook manages the full lifecycle of objects in the Samba4 Active Directory:

```bash
eval $(./scripts/op-session.sh 2h prod)

ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0a/identity-lifecycle.yaml
```

### What Gets Configured

- **Groups**: Creates AD security groups defined in inventory
- **Organizational Units (OUs)**: Creates OUs for organizing users
- **Users**: Creates users within OUs with:
  - Random initial password (generated on creation)
  - Password resolution from 1Password vault (if configured)
  - User attributes (given name, surname, display name)
  - Group memberships
- **User updates**: Updates existing user attributes and group memberships when inventory changes
- **Orphan detection**: Identifies groups, OUs, and users that exist in AD but are not defined in inventory

### Creating vs. Deleting

The playbook is **safe by default** — it creates and updates objects but does **not** delete orphaned objects unless explicitly confirmed:

```bash
# Dry run — shows what would be deleted
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0a/identity-lifecycle.yaml

# Actually delete orphaned objects
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0a/identity-lifecycle.yaml \
    -e delete_confirmed=true
```

Built-in system groups, OUs, and users (Administrator, Domain Admins, etc.) are **protected** and will never be deleted regardless of the `delete_confirmed` flag.

### Adding a New User

To add a new user:

1. Add the user definition under the appropriate OU in `identity_organizational_units` (in `configs/envbase/group_vars/identityprovider/identity-configuration.yaml`)
2. Specify the user's groups, attributes, and optionally a 1Password vault reference for the password
3. Run the lifecycle playbook — the user is created with a generated password (or resolved from 1Password) and added to the specified groups

### Adding a New Group

To add a new group:

1. Add the group name to `identity_groups` in the inventory
2. Run the lifecycle playbook — the group is created in AD
3. Assign users to the group in their user definitions

### Configuration Source

- **`configs/envbase/group_vars/identityprovider/identity-configuration.yaml`**: Group definitions, OU structure with nested user definitions
- **`configs/envbase/group_vars/all/secrets-vault.yaml`** (example): Password vault references for `vault_identity_user_passwords`
- **Environment overlay**: Actual vault item names and user-specific overrides

---

## 5. Continuous PKI / step-ca Configuration

After Ring 0 bootstraps the Root + Intermediate CA, the step-ca container is running but has no provisioners and no SAN policy. The Ring 0a playbook reconciles the runtime authority configuration to match inventory:

```bash
eval $(./scripts/op-session.sh 1h test)

ansible-playbook \
    -i configs/envbase/ \
    -i configs/envtest/inventory/ \
    playbooks/ring0a/pki-stepca-configure.yaml
```

### What Gets Configured

- **JWK provisioner**: Installs (or restores) a JWK provisioner named by `step_ca_jwk_provisioner_name`. If `ca.json` has no JWK material and the 1Password item `Step CA JWK Controller <env_id>` has `jwkpub` / `jwkpriv` document attachments from a prior run, the playbook restores them so the existing JWK password keeps working after `terraform destroy`. Otherwise it generates a fresh EC P-256 JWK pair inside the container and uploads both halves to 1Password as backup.
- **SAN policy**: Pushes `authority.policy.x509.allow.dns` from `step_ca_san_policy.dns.allow` (computed in [configs/envbase/group_vars/all/pki-stepca.yaml](../configs/envbase/group_vars/all/pki-stepca.yaml) from `step_ca_san_policy_service_subdomains`). Reminder: step-ca rejects `**`, leading-dot, or non-leading wildcards — only `*.<labels>` form, one wildcard per rule, and the rule's label count must match the requested name's label count.
- **Leaf-duration claims**: Reconciles `authority.claims.{min,default,max}TLSCertDuration` from `step_ca_leaf_validity_days`. Go's duration syntax has no `d` unit, so the playbook multiplies by 24 and renders `<N>h0m0s`. Lets you bump the maximum leaf lifetime without re-bootstrapping the CA.
- **Container repair mode**: If the container is stopped (typically because the previous `ca.json` was invalid and step-ca crash-looped on startup), the playbook temporarily overrides `oci.entrypoint` with `sleep infinity`, starts the container so its `$STEPPATH` volume is mounted and `incus file pull/push` can see `ca.json`, applies the corrected config, then unsets the entrypoint override and starts the container with the real entrypoint. Re-running Ring 0a is the standard recovery path after a bad SAN-policy push.
- **Verification**: Waits for the `/health` endpoint to return 200 and asserts the JWK provisioner is advertised on `/provisioners`.

### Adjusting the SAN Policy

To allow a new service subdomain (e.g. `mqtt.<localdomain>` and `*.mqtt.<localdomain>`):

1. Extend `step_ca_san_policy_service_subdomains` in the environment overlay:

    ```yaml
    # configs/envtest/inventory/group_vars/all/pki-stepca.yaml
    step_ca_san_policy_service_subdomains: "{{ step_ca_san_policy_service_subdomains + ['mqtt'] }}"
    ```

2. Re-run `pki-stepca-configure.yaml` — the new rule is merged into `ca.json` and step-ca is restarted.

### Bumping Leaf Validity

Set `step_ca_leaf_validity_days` (e.g. to `90` for short-lived leaves or `397` for browser-tolerated yearly leaves) in the environment overlay and re-run the playbook. Newly-issued certs honour the new cap; existing certs remain valid until their own `notAfter`.

### Configuration Source

- **`configs/envbase/group_vars/all/pki-stepca.yaml`**: Base PKI defaults (hierarchy, key types, 1P item names, JWK provisioner, SAN policy template, claims).
- **Environment overlay** (e.g. `configs/envtest/inventory/group_vars/all/pki-stepca.yaml`): `step_ca_env_id`, `step_ca_hostname`, `step_ca_target_remote`, `step_ca_san_policy_service_subdomains`, `step_ca_leaf_validity_days`.

---

## GitOps Integration

All Ring 0a playbooks are designed for GitOps-style workflows:

1. **Change inventory** (add device, change firewall rule, add user, create dataset)
2. **Commit and push** to the configuration repository
3. **Trigger the playbook** (manually or via CI/CD pipeline)
4. **Playbook applies** only the changes needed to reach the desired state

Because all playbooks are idempotent, they can be run on a schedule (e.g., every hour) as a reconciliation loop, or triggered on-demand after configuration changes.

### Recommended Run Order

When applying multiple Ring 0a changes simultaneously:

```bash
# 1. Network first (other services may depend on DNS/DHCP)
ansible-playbook ... playbooks/ring0a/networking-mikrotik-continuous-configure-all.yaml

# 2. Identity second (ACLs depend on users/groups existing)
ansible-playbook ... playbooks/ring0a/identity-lifecycle.yaml

# 3. Storage third (references AD groups from identity)
ansible-playbook ... playbooks/ring0a/storage-truenas-configure.yaml

# 4. Incus maintenance (independent, can run anytime)
ansible-playbook ... playbooks/ring0a/host-incus-update.yaml
ansible-playbook ... playbooks/ring0a/host-incus-import-iso.yaml

# 5. PKI reconciliation (Ring 1 cert issuance depends on this)
ansible-playbook ... playbooks/ring0a/pki-stepca-configure.yaml

# 6. Optional: cleanup orphaned router entries
ansible-playbook ... playbooks/ring0a/networking-mikrotik-continuous-cleanup.yaml
```

## Further Reading

- [Principles & Ring Model](01-principles.md) — Why Ring 0a is fully automated and idempotent
- [Ring 0 Setup](04-ring0-setup.md) — Initial infrastructure bootstrap (prerequisite)
- [Incus Client Certificates](incus-host/incus-client-certificates.md) — Certificate management details
- [Ring 1 Services](06-ring1-services.md) — Services that build on Ring 0 and Ring 0a
