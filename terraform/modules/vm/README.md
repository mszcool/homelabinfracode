# Incus VM Module

Terraform module for provisioning virtual machines on Incus servers.

> **Master documentation**: See [Ring 0 Setup — Terraform VM Provisioning](../../../docs/04-ring0-setup.md#3-provision-truenas-vm-with-terraform) for the high-level workflow. For architecture details, see the [Terraform docs](../../../docs/terraform/INDEX.md).

---

## Usage

```hcl
module "truenas_vm" {
  source = "./modules/vm"

  instance_name  = "truenas-primary"
  target_remote  = "incus-aoostar"
  incus_project  = "default"
  incus_profile  = "prodlayer0"
  storage_pool   = "incus-instances"

  cpu_cores      = 4
  memory_gb      = 16
  system_disk_gb = 32

  # ISO-based installation (e.g. TrueNAS)
  iso_volume_name = "truenas-25.10.1"
  iso_mounted     = true

  # Or image-based with cloud-init
  # image          = "images:ubuntu/24.04"
  # ssh_public_key = var.ssh_public_key
  # root_password  = var.root_password
}
```

---

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `instance_name` | string | (required) | Name of the VM instance |
| `target_remote` | string | (required) | Incus remote where the VM will be created |
| `incus_project` | string | `"default"` | Incus project name |
| `incus_profile` | string | `"default"` | Incus profile to apply |
| `storage_pool` | string | `"incus-instances"` | Storage pool for instance storage |
| `type` | string | `"virtual-machine"` | Instance type: `container` or `virtual-machine` |
| `image` | string | `""` | Base image (e.g. `images:ubuntu/24.04`). Leave empty for ISO install |
| `cpu_cores` | number | `4` | CPU cores (1-256) |
| `memory_gb` | number | `8` | Memory in GB (1-1024) |
| `system_disk_gb` | number | `64` | Root disk size in GB |
| `network_bridge` | string | `"phys-br"` | Network bridge to attach |
| `mac_address` | string | `""` | Optional MAC address for primary NIC |
| `iso_volume_name` | string | `""` | Pre-imported ISO storage volume name |
| `iso_mounted` | bool | `false` | Whether to mount the ISO device |
| `enable_pcie_passthrough` | bool | `false` | Enable PCIe controller passthrough |
| `pcie_controller` | string | `""` | PCIe PCI address (`0000:XX:YY.Z`) |
| `data_disks` | list(object) | `[]` | Additional data disks to create and attach |
| `enable_boot_autostart` | bool | `false` | Auto-start VM on host boot |
| `root_username` | string | `"admin"` | Privileged user for cloud-init |
| `ssh_public_key` | string | `""` | SSH public key for passwordless access |
| `root_password` | string | `""` | Yescrypt-hashed password (never plaintext) |
| `tags` | map(string) | `{ managed_by = "terraform" }` | Tags for resources |

---

## Outputs

| Output | Description |
|--------|-------------|
| `instance_name` | Name of the created instance |
| `instance_ipv4_address` | IPv4 address of the instance |
| `instance_ipv6_address` | IPv6 address of the instance |
| `instance_status` | Current status of the instance |
| `data_disk_names` | List of data disk volume names |

---

## Cloud-Init and User Configuration

For image-based VMs, the module uses cloud-init to configure the initial user:

```bash
# Generate a yescrypt-hashed password (Ubuntu 24.04 default)
mkpasswd -m yescrypt

# Pass via environment variable (never in tfvars)
export TF_VAR_root_password='$y$j9T$...'
terraform apply -var-file="../configs/envtest/ring0.tfvars"
```

**Important**: Ubuntu 24.04 uses yescrypt hashing by default. Do not use SHA-512.
See [Cloud-Init chpasswd Fix](../../../docs/incus-host/CLOUD-INIT-CHPASSWD-FIX.md) and
[Yescrypt Hashing](../../../docs/incus-host/YESCRYPT-HASHING.md) for details.

---

## ISO Handling

For ISO-based installations (e.g. TrueNAS):

1. Import the ISO via Ansible first (creates an Incus storage volume)
2. Set `iso_volume_name` to the volume name and `iso_mounted = true`
3. After OS installation, set `iso_mounted = false` and re-apply

See [Ring 0 Setup](../../../docs/04-ring0-setup.md#3-provision-truenas-vm-with-terraform) for the full workflow.

---

## PCIe Passthrough

To pass a PCIe controller (e.g. HBA for TrueNAS):

```hcl
enable_pcie_passthrough = true
pcie_controller         = "0000:01:00.0"
```

When PCIe passthrough is enabled, `data_disks` are ignored (the physical controller manages its own disks).

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| ISO not found | Ensure ISO is imported via Ansible before `terraform apply` |
| Cloud-init password not working | Use yescrypt hash, set `root_password = ""` in tfvars, pass via `TF_VAR_root_password` |
| Secure boot errors | Module disables secure boot by default (`security.secureboot = false`) |
| PCIe device not available | Verify PCI address with `lspci` on the host; ensure IOMMU is enabled |
