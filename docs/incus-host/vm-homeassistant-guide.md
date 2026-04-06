# Home Assistant OS VM on Incus — Deployment Guide

> **Context**: This guide covers deploying Home Assistant Operating System (HAOS) as a KVM virtual machine on an Incus-based virtualization host. HAOS is an appliance image — it manages its own OS, updates, add-ons, and container runtime internally.
>
> **Note on paths**: This document uses the directory-based inventory structure. Adapt `-i configs/envbase/ -i configs.private/envlocaldev/inventory/` to your environment (e.g., `-i configs/envbase/ -i configs.private/envprod/inventory/` for production).

## Overview

Home Assistant OS runs as a full virtual machine booted from a pre-built QCOW2 appliance image. Unlike standard VMs provisioned from cloud images, HAOS:

- Has **no cloud-init** support — initial setup happens via the web UI
- Includes the **QEMU guest agent** but **not the Incus agent** — Terraform/Incus cannot wait for agent readiness
- Requires **UEFI boot** with **Secure Boot disabled**
- Manages its own Docker/container runtime internally for add-ons and integrations

## Prerequisites

1. **Incus Host Setup**: A configured Incus cluster with at least one available remote
2. **Storage Pool**: An Incus storage pool (e.g., `incus-instances`) with sufficient space
3. **Network Bridge**: A bridged network (`phys-br`) so HAOS gets a LAN IP address
4. **QCOW2 Image Downloaded**: The HAOS QCOW2 image must be downloaded and decompressed locally before import

## Deployment Workflow

### Step 1: Download the HAOS QCOW2 Image

Download the KVM/Proxmox QCOW2 image from the [Home Assistant OS releases](https://github.com/home-assistant/operating-system/releases) page and decompress it:

```bash
# Download the compressed image
curl -fSL -o ~/iso/haos_ova-17.1.qcow2.xz \
  https://github.com/home-assistant/operating-system/releases/download/17.1/haos_ova-17.1.qcow2.xz

# Decompress (produces haos_ova-17.1.qcow2)
xz -d ~/iso/haos_ova-17.1.qcow2.xz
```

> **Tip**: The `~/iso/` directory matches the `operator_home_dir` convention used by inventory variables. Adjust if your setup differs.

### Step 2: Import the QCOW2 Image into Incus

Use the Ansible playbook to import the decompressed QCOW2 file as an Incus VM image:

```bash
# Import the image to all Incus remotes in the inventory
ansible-playbook playbooks/ring0a/host-incus-import-qcow2.yaml \
  -i configs/envbase/ -i configs/envtest/inventory
```

The playbook will:
1. Validate the local QCOW2 file exists
2. Check if the image alias (`haos-17.1`) already exists on each Incus remote (idempotent — skips if present)
3. Generate the required `metadata.yaml` / `metadata.tar.gz` (Incus requires a metadata tarball alongside the disk image)
4. Import the image via `incus image import metadata.tar.gz <qcow2-file>` with the configured alias

**Inventory configuration** (in `configs/envtest/inventory/group_vars/incus_scope/host-incus-cluster.yaml`):

```yaml
qcow2_images:
  - name: "haos-17.1"
    project: "default"
    source_local: "{{ operator_home_dir }}/iso/haos_ova-17.1.qcow2"
    source_url: "https://github.com/home-assistant/operating-system/releases/download/17.1/haos_ova-17.1.qcow2.xz"
```

To verify the import succeeded:

```bash
incus image list <remote>: --project=default | grep haos
```

### Step 3: Deploy the VM with Terraform

The Home Assistant VM is defined in `ring1.tfvars`. Apply it with Terraform:

```bash
cd terraform/

# Select the ring1 workspace
terraform workspace select ring1

# Plan (review changes)
terraform plan -var-file=../configs/envtest/ring1.tfvars

# Apply
terraform apply -var-file=../configs/envtest/ring1.tfvars
```

**Key Terraform configuration** (in `configs/envtest/ring1.tfvars`):

```hcl
"home-assistant" = {
  target_remote           = "incus.peladin.mszlocal"
  incus_profile           = "default"
  storage_pool            = "incus-instances"
  type                    = "virtual-machine"
  image                   = "haos-17.1"          # Must match the imported image alias
  cpu_cores               = 2
  memory_gb               = 4
  system_disk_gb          = 256
  network_bridge          = "phys-br"
  mac_address             = "00:16:3e:92:00:07"
  enable_boot_autostart   = true
  wait_for_network        = false                 # HAOS has no Incus agent
  # No cloud-init, SSH key, or root password — HAOS is an appliance
  root_username           = "admin"
  root_password           = ""
  ssh_public_key          = ""
  data_disks              = []
}
```

Terraform will:
1. Create a KVM virtual machine referencing the `haos-17.1` image
2. Allocate 4 GB RAM, 2 vCPU, and a 256 GB root disk
3. Attach the VM to the `phys-br` bridge with the specified MAC address
4. Boot with UEFI firmware and Secure Boot disabled
5. Skip waiting for the Incus agent (since HAOS doesn't include one)

### Step 4: Access the Home Assistant Web UI

After the VM boots (allow 2–5 minutes for first boot):

1. **Find the VM's IP address**:
   ```bash
   # Via Incus (may show if QEMU guest agent responds)
   incus list --project=default | grep home-assistant

   # Or check your DHCP server / router for the assigned IP
   # The MAC address 00:16:3e:92:00:07 can help identify the lease
   ```

2. **Open the web UI** at:
   ```
   http://<vm-ip>:8123/
   ```
   Or try:
   ```
   http://homeassistant.local:8123/
   ```

3. **Complete the onboarding wizard**: Create your user account, set location, and configure initial integrations.

## Resource Requirements

| Resource | Minimum | Recommended | This Config |
|----------|---------|-------------|-------------|
| CPU      | 2 vCPU  | 2+ vCPU     | 2 vCPU      |
| Memory   | 2 GB    | 4+ GB       | 4 GB        |
| Disk     | 32 GB   | 64+ GB      | 256 GB      |

> **Note**: The generous 256 GB disk allocation accommodates add-on storage (media, databases, recorder history), backups, and long-term growth. HAOS manages disk space internally.

## Updating HAOS

Home Assistant OS updates are managed **from within the Home Assistant UI** — not via Incus or Terraform:

1. Go to **Settings** → **System** → **Updates**
2. Apply available updates (OS, Core, Supervisor, add-ons)

To update to a **new major HAOS release** that requires a new QCOW2 image:

1. Download and decompress the new QCOW2 image
2. Update the inventory entry (`name`, `source_local`, `source_url`)
3. Re-run the Ansible import playbook
4. Update `image` in `ring1.tfvars` to match the new alias
5. Run `terraform apply` (this will recreate the VM — **back up first**)

## Troubleshooting

### VM Won't Start

```bash
# Check VM logs
incus info home-assistant --show-log --project=default

# Verify the image was imported
incus image list <remote>: --project=default | grep haos

# Check VM configuration
incus config show home-assistant --project=default
```

### Cannot Reach Web UI

1. **Check VM is running**:
   ```bash
   incus list --project=default | grep home-assistant
   ```

2. **Check network connectivity**: Ensure the VM's bridge network has DHCP and the VM obtained an IP.

3. **Allow time for first boot**: HAOS performs initial setup on first boot which can take several minutes.

4. **Console access** (for debugging boot issues):
   ```bash
   incus console home-assistant --project=default
   ```
   Press `Ctrl+a` then `q` to exit the console.

### Image Import Fails

```bash
# Verify the QCOW2 file is valid and decompressed
file ~/iso/haos_ova-17.1.qcow2
# Expected: QEMU QCOW2 Image (v3), ...

# Check file size (should be ~1-2 GB decompressed)
ls -lh ~/iso/haos_ova-17.1.qcow2

# Manual import for debugging — requires a metadata tarball:
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/metadata.yaml" <<EOF
architecture: x86_64
creation_date: $(date +%s)
properties:
  description: haos-17.1 VM image
  os: Linux
  release: haos-17.1
EOF
tar -czf "$TMPDIR/metadata.tar.gz" -C "$TMPDIR" metadata.yaml
incus image import "$TMPDIR/metadata.tar.gz" ~/iso/haos_ova-17.1.qcow2 <remote>: \
  --alias haos-17.1 --project=default
rm -rf "$TMPDIR"
```

## Security Considerations

- HAOS exposes port **8123** (HTTP) on its LAN IP — consider placing it behind a reverse proxy with TLS for production use
- The onboarding wizard is only available once — complete it promptly after first boot
- Enable **multi-factor authentication** in the Home Assistant user profile
- Keep HAOS and all add-ons updated via the built-in update mechanism
- If using Authentik (also deployed in ring1), consider configuring Home Assistant's [OpenID Connect integration](https://www.home-assistant.io/integrations/openid_connect/) for SSO

## Integration with Existing Infrastructure

This deployment integrates with the homelab infrastructure:

- **MQTT**: The `mosquitto-broker` container (also in ring1) provides MQTT messaging for IoT devices. Configure the [MQTT integration](https://www.home-assistant.io/integrations/mqtt/) in Home Assistant to connect to the broker's IP.
- **Authentik**: The Authentik identity provider (also in ring1) can provide SSO for the Home Assistant web UI.
- **Network**: HAOS sits on the same `phys-br` bridged network as other ring1 services, enabling direct LAN communication.
