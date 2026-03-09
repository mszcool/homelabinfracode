# Ring 2 — Application Services

Ring 2 contains non-essential applications. If a Ring 2 service is unavailable, it causes inconvenience but does not disrupt core homelab operations. These are predominantly containers deployed on top of Ring 0 (and optionally Ring 1) infrastructure.

Ring 2 respects the [layer inversion principle](01-principles.md): these services may depend on Ring 0 and Ring 1, but no lower ring depends on Ring 2.

## Current Implementation

### Syncthing — File Synchronization

Syncthing provides peer-to-peer file synchronization across devices. It is deployed as a Docker app on TrueNAS Scale using the built-in Apps system.

#### Deployment

```bash
eval $(./scripts/op-session.sh 2h prod)

ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring2/apps-truenas-syncthing.yaml
```

#### What the Playbook Does

1. **Validates configuration**: Ensures all Syncthing instances have unique ports (web UI and listen ports)
2. **Checks TrueNAS Apps system**: Verifies Docker/Apps is enabled on the target TrueNAS host
3. **Deploys instances**: Creates each Syncthing app instance via `midclt` API with:
   - Configurable CPU cores and memory limits
   - Web UI port and Syncthing listen port
   - Host path mounts for data directories (pointing to TrueNAS datasets)
4. **Post-deployment notice**: Displays a reminder that admin passwords must be set manually through the Syncthing web UI after deployment

#### Multiple Instances

The playbook supports deploying multiple Syncthing instances on the same TrueNAS host. Each instance must have unique port numbers:

```yaml
# Example inventory structure (in group_vars/truenas/)
syncthing_instances:
  instance1:
    app_name: syncthing-personal
    web_port: 8384
    listen_port: 22000
    host_paths:
      - /mnt/data/syncthing/personal
  instance2:
    app_name: syncthing-family
    web_port: 8385
    listen_port: 22001
    host_paths:
      - /mnt/data/syncthing/family
```

#### Configuration Source

- **`configs/envbase/group_vars/truenas/apps-syncthing-configuration.yaml`**: Syncthing app defaults (catalog app name, train, default CPU/memory limits, default ports)
- **Environment overlay**: Actual instance definitions, host paths, port assignments

#### Dependencies

- **Ring 0 (TrueNAS)**: Hosts the Docker apps system and provides storage datasets
- **Ring 0 (Networking)**: MikroTik router provides DNS and firewall rules for Syncthing ports
- **Ring 0 (Identity)**: TrueNAS datasets used by Syncthing may have AD-based ACLs

---

## Planned Services

### Paperless NGX — Document Management

- **Purpose**: OCR-based document management and archival system
- **Deployment**: Container (on TrueNAS Docker apps or k3s)
- **Dependencies**: Ring 0 (TrueNAS for document storage, AD for user auth), optionally Ring 1 (k3s for orchestration)
- **Status**: Planned

### Additional TrueNAS Apps

TrueNAS Scale's built-in Docker apps system is the primary deployment platform for Ring 2 services. Future apps may include:

- **Media management** (Jellyfin, Plex)
- **Backup utilities** (Duplicati, Restic frontend)
- **Monitoring dashboards** (Grafana, Prometheus)

These are complementary to the storage infrastructure but not essential — their absence does not cause data loss or operational disruption.

---

## Ring 2 Design Guidelines

When implementing new Ring 2 services:

1. **Prefer TrueNAS Docker apps** for storage-adjacent services — simplifies deployment and data access
2. **Use k3s** (Ring 1) for more complex services requiring orchestration, scaling, or multi-container compositions
3. **Define configuration in inventory** under the appropriate group variables
4. **Create playbooks in `playbooks/ring2/`** following the existing Syncthing pattern
5. **All playbooks must be idempotent**: Safe to re-run at any time
6. **No lower-ring dependencies**: Ring 0 and Ring 1 must not depend on any Ring 2 service being available

## Further Reading

- [Principles & Ring Model](01-principles.md) — Ring dependency rules and what makes a service Ring 2
- [Ring 0a Automated](05-ring0a-automated.md) — TrueNAS dataset configuration that Ring 2 apps consume
- [Ring 1 Services](06-ring1-services.md) — Operations services that may host Ring 2 containers
