# Ring 0 — Initial Infrastructure Setup

Ring 0 contains the foundational infrastructure that must be in place before any higher-ring services can operate. The setup is **semi-automated**: playbooks generate configuration artifacts that are then applied manually to the target hardware. This manual step is necessary because the hardware is not yet provisioned with any management agent or OS at this stage.

> **Prerequisites**: Complete the [Environment Setup](03-environment-setup.md) before proceeding.

## Setup Order

Ring 0 components must be set up in a specific sequence because of inter-dependencies:

```
1. MikroTik Router     ──→ Networking foundation (DHCP, DNS, VLANs, firewall)
2. Incus Compute Nodes ──→ Virtualization platform (needs network from step 1)
3. TrueNAS Scale       ──→ Storage (runs as VM on Incus from step 2)
4. Samba4 AD DC        ──→ Identity (runs as VM on Incus, may use TrueNAS DNS)
```

---

## 1. MikroTik Router Setup

The router is the first component because all other devices depend on network connectivity. The Ansible playbook generates RouterOS scripts in **two phases** that must be executed manually.

### What the Playbook Does

`playbooks/ring0/networking-mikrotik.yaml` generates:

- **Phase 1 script** (`.rsc`): Basic router configuration — hostname, timezone, user accounts (root + automation) with passwords and SSH keys, WAN DHCP client, LAN bridge with static IP, and temporary basic firewall rules
- **Phase 2 script** (`.rsc`): SSL certificate installation (self-signed CA + server cert) and complete firewall rule setup with connection tracking
- **SSL certificates**: Self-signed root CA and server certificate generated locally
- **SSH config**: OpenSSL configuration file with Subject Alternative Names for the router

### Step 1a: Generate Router Configuration Scripts

```bash
# Start a 1Password session
eval $(./scripts/op-session.sh 2h prod)

# Generate the router bootstrap scripts
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0/networking-mikrotik.yaml
```

The playbook runs entirely on **localhost** (connection: local) and produces output files in the configured output directory.

### Step 1b: Apply Phase 1 via Winbox

Phase 1 must be applied through MikroTik's **Winbox** application because the router has no SSH access yet:

1. Connect to the router via Winbox (default IP or MAC address)
2. Open the terminal in Winbox
3. Paste or import the generated Phase 1 `.rsc` script
4. The script configures basic networking, creates users, and sets up SSH access

After Phase 1, the router has:
- A configured LAN bridge with a static IP
- SSH access enabled for the automation user
- A temporary basic firewall

### Step 1c: Apply Phase 2 via SSH

Phase 2 is applied via SSH (now available after Phase 1):

1. Upload the generated SSL certificate files to the router
2. SSH into the router using the automation user created in Phase 1
3. Import and run the Phase 2 `.rsc` script
4. The script installs SSL certificates, enables HTTPS management, and sets up the complete firewall

After Phase 2, the router is fully configured with:
- SSL-secured management interfaces
- Complete firewall with connection tracking
- Ready for Ring 0a continuous configuration

### Configuration Source

Router configuration is defined in the inventory under the `mainrouter` group variables:

- **`configs/envbase/group_vars/mainrouter/networking-foundation.yaml`**: Router interfaces, bridge config, network definitions (LAN + VLANs), DHCP settings, firewall rule groups
- **Environment overlay** (`configs.private/envprod/inventory/`): Actual IP addresses, passwords (via 1Password vault references), SSH keys

---

## 2. Incus Compute Node Setup

Incus nodes are bare-metal Ubuntu servers that host all VMs and containers. The playbook generates a bootable ISO image with Ubuntu autoinstall configuration that sets up the OS and Incus automatically.

### What the Playbook Does

`playbooks/ring0/host-incus-image-unified.yaml` generates a **single unified ISO** containing autoinstall configurations for multiple server hardware types (e.g., single-disk, dual-disk):

- Downloads the base Ubuntu Server ISO
- Generates per-server-type autoinstall YAML (disk partitioning, LVM, user accounts, packages)
- Generates Incus preseed files (networks, storage pools, projects, profiles)
- Generates Incus production profiles and first-boot setup scripts
- Creates a GRUB boot menu for selecting the server type at install time
- Packages everything into a single bootable ISO

### Step 2a: Generate the Unified ISO

```bash
# Generate the unified autoinstall ISO
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0/host-incus-image-unified.yaml
```

The output ISO is written to `~/iso/ubuntu-unified-autoinstall.iso`.

### Step 2b: Install Ubuntu on Compute Nodes

1. Write the ISO to a USB drive or mount via IPMI/BMC
2. Boot the server from the ISO
3. Select the appropriate server configuration from the GRUB menu (e.g., "AUTOINSTALL - MSZ_SINGLE_DISK_SERVER")
4. Wait for automatic installation to complete
5. The server reboots with Ubuntu + Incus fully configured

### What Gets Configured Automatically

The autoinstall and first-boot scripts configure:

- **Disk layout**: EFI + boot + LVM root volume group
- **User account**: Admin user with SSH key and yescrypt password hash
- **Incus daemon**: Initialized with preseed configuration
- **Incus networks**: `phys-br` (macvlan to physical network) and `iso-nat` (internal NAT)
- **Incus storage pools**: LVM-backed pools for images and instances
- **Incus projects**: `prodlayer0` (with PCIe passthrough) and `prodlayer1` (application VMs)
- **Incus profiles**: Default profiles with appropriate networking for each project
- **Firewall (UFW)**: SSH and Incus port allowed, deny inbound, allow outbound

### Multi-ISO Alternative

For environments where a single ISO is not practical, there is also:

```bash
# Generate separate ISOs per server type
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0/host-incus-image-multiiso.yaml
```

See [Unified ISO Generation](incus-host/README-unified-iso.md) for details on the ISO structure and boot process.

### Configuration Source

Incus configuration is defined in the `incus_scope` group variables:

- **`configs/envbase/group_vars/incus_scope/host-incus-cluster.yaml`**: ISO source URL, LVM volume group, Incus daemon config (port, storage pools, disk sizes), project limits, trusted client certificates, ISO images list
- **`playbooks/ring0/projects/*.yaml`**: Incus project definitions (prodlayer0, prodlayer1) with resource limits and device access rules
- **Environment overlay**: Actual host IPs, hardware-specific config names, passwords

---

## 3. TrueNAS Scale Setup

TrueNAS runs as a VM on Incus with PCIe/SATA controller passthrough for direct disk access. Setup involves two phases: provisioning the VM (Terraform) and performing fundamental TrueNAS configuration (Ansible).

### Step 3a: Discover PCI-to-Disk Mappings

Before creating the TrueNAS VM, identify which PCI controllers are connected to which physical disks:

```bash
# Run the disk-to-PCI mapping utility on the target Incus host
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0/storage-vm-incus-truenas-find-disk-pci.yaml
```

This outputs a table of device names, PCI addresses, and ATA ports. Use the PCI address for the SATA controller in the Terraform configuration.

### Step 3b: Provision the TrueNAS VM with Terraform

```bash
cd terraform

# Start 1Password session
eval $(./scripts/op-session.sh 2h prod)

# Select the ring0 workspace
terraform workspace select ring0

# Review the plan
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"

# Create the VM
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
```

The Terraform `ring0.tfvars` defines the TrueNAS VM with:
- CPU cores, memory, system disk size
- Target Incus remote and project
- ISO volume for initial installation
- PCIe passthrough for the SATA controller
- Optional data disks
- Root password from 1Password vault

### Step 3c: Install TrueNAS OS

After Terraform creates the VM:

1. Access the VM console via Incus (`incus console <vm-name> --project=prodlayer0`)
2. Complete the TrueNAS Scale installation from the mounted ISO
3. Set the initial admin password
4. Reboot into the installed system

### Step 3d: Fundamental TrueNAS Configuration

After TrueNAS is running, apply the foundational configuration:

```bash
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0/storage-truenas-scale-fundamental-config.yaml
```

This playbook configures:
- Hostname, timezone, keyboard layout
- Admin user SSH keys and password
- DNS pointing to the AD DC
- Two-factor authentication enablement
- Active Directory domain join (LDAP integration)
- Data storage pool creation
- Docker/Apps system enablement (for Ring 2 apps)
- Root account lockdown, text console disable

### Configuration Source

TrueNAS configuration is defined in:

- **`configs/envbase/group_vars/truenas/storage-truenas-setup.yaml`**: Localization, 2FA, AD join settings, admin credentials
- **`configs/envbase/group_vars/truenas/storage-truenas-configuration.yaml`**: Services, snapshots, scrub schedules, storage pools, HDD sleep
- **Environment overlay**: Actual TrueNAS hostname, IP, AD DC address, passwords

See [TrueNAS VM on Incus](incus-host/vm-incus-truenas-guide.md) for the complete deployment guide including PCIe passthrough details.

---

## 4. Samba4 Active Directory Domain Controller Setup

The Samba4 AD DC provides centralized identity (users, groups), DNS, and Kerberos authentication for all homelab services.

### Step 4a: Provision the AD DC VM with Terraform

The AD DC VM is defined in the same `ring0.tfvars` as TrueNAS:

```bash
cd terraform

# Start 1Password session (if not already active)
eval $(./scripts/op-session.sh 2h prod)

# Select the ring0 workspace
terraform workspace select ring0

# Plan and apply (this creates all Ring 0 VMs including the AD DC)
terraform plan -var-file="../configs.private/envprod/ring0.tfvars"
terraform apply -var-file="../configs.private/envprod/ring0.tfvars"
```

The VM is created with cloud-init that configures the initial user account and SSH key.

### Step 4b: Provision the Samba4 AD Domain

After the VM is running with a base Ubuntu installation:

```bash
# Start 1Password session
eval $(./scripts/op-session.sh 2h prod)

# Run the Samba4 AD DC setup playbook
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/ring0/identity-samba4-addc-setup.yaml
```

This playbook performs 6 automated steps:

1. **System preparation**: Set hostname, timezone, install Samba4 packages, configure NTP
2. **Pre-provisioning cleanup**: Remove conflicting Kerberos and smb.conf files
3. **AD domain provisioning**: Run `samba-tool domain provision` (skipped if `sam.ldb` already exists for idempotency)
4. **Post-provisioning configuration**: Configure Kerberos realm, DNS resolver, DNS forwarders, smb.conf settings
5. **Service setup**: Create and enable systemd unit for Samba daemon
6. **DNS verification**: Validate that SRV records, A records, and LDAP records resolve correctly

### Post-Setup Verification

After the playbook completes, verify the domain:

```bash
# Test Kerberos authentication
kinit administrator@YOUR.DOMAIN

# Test DNS resolution
host -t SRV _ldap._tcp.your.domain
host -t SRV _kerberos._tcp.your.domain

# Test LDAP
samba-tool user list
samba-tool group list
```

### Configuration Source

Samba4 configuration is defined in:

- **`configs/envbase/group_vars/identityprovider/identity-samba4-addc.yaml`**: Samba4 packages, paths, AD configuration (realm, domain, DNS, Kerberos), NTP settings
- **`configs/envbase/group_vars/identityprovider/identity-configuration.yaml`**: Identity group definitions (used by Ring 0a lifecycle playbook)
- **Environment overlay**: Actual admin password (from 1Password), DNS forwarders, IP addresses

See [Samba4 AD DC Guide](identity-addc/INDEX.md) for comprehensive documentation including examples, quick reference, and troubleshooting.

---

## After Ring 0 Setup

Once all four Ring 0 components are operational:

1. **Verify connectivity**: All devices can reach the router, compute nodes are reachable, TrueNAS shares are accessible, AD authentication works
2. **Proceed to Ring 0a**: Set up continuous configuration — see [Ring 0a — Continuous Configuration](05-ring0a-automated.md)
3. **Bootstrap all hosts**: Run the base playbooks for OS-level setup across all managed hosts:

```bash
# Bootstrap standard packages on all hosts
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/all-base/bootstrap-machines.yaml

# Safe upgrade of all hosts (one at a time)
ansible-playbook \
    -i configs/envbase/ \
    -i configs.private/envprod/inventory/ \
    playbooks/all-base/upgrade-machines.yaml
```

## Further Reading

- [Principles & Ring Model](01-principles.md) — Why Ring 0 setup is semi-automated
- [Architecture Overview](02-architecture.md) — How components relate to each other
- [Ring 0a — Continuous Configuration](05-ring0a-automated.md) — Day-2 operations for Ring 0 services
- [Unified ISO Generation](incus-host/README-unified-iso.md) — ISO structure and boot process details
- [TrueNAS VM Guide](incus-host/vm-incus-truenas-guide.md) — PCIe passthrough and VM management
- [Samba4 AD DC Guide](identity-addc/INDEX.md) — Complete identity setup documentation
- [Terraform Architecture](terraform/INDEX.md) — Terraform module design and usage
