# Environment Setup

This document explains how to prepare an Ansible control host (the machine from which you run playbooks and Terraform deployments) with all required dependencies.

## Prerequisites

The control host must be a Linux machine (Ubuntu/Debian recommended) with:

- **Python 3.12+** with pip
- **Git** (to clone the repository and the private config submodule)
- **A Python virtual environment** at `~/pythonvenv/default/` (used by `ansible.cfg`)
- **1Password CLI** (`op`) installed for secrets resolution
- **Terraform 1.5+** installed for VM provisioning
- **Incus client** installed for remote Incus management

## Step 1: Create the Python Virtual Environment

Ansible is configured (in `ansible.cfg`) to use a Python interpreter at `~/pythonvenv/default/bin/python3`:

```bash
python3 -m venv ~/pythonvenv/default
source ~/pythonvenv/default/bin/activate
```

All subsequent steps should be run with this virtual environment active.

## Step 2: Clone the Repository

```bash
git clone https://github.com/mszcool/homelabinfracode.git
cd homelabinfracode

# Initialize the private config submodule (if you have access)
git submodule update --init --recursive
```

## Step 3: Install Ansible and Dependencies

Run the bootstrap script which installs Ansible, required pip packages, and all Galaxy collections:

```bash
./initAnsibleHost.sh
```

This script performs:

1. **pip install**: `ansible`, `ansible-pylibssh`, `netaddr`
2. **Galaxy collections**: Installs from `ansible-requirements.yaml` to `~/.ansible/collections`
3. **Collection fixes**: Applies patches for known issues (e.g., `arensb.truenas` v1.14.x)
4. **Verification**: Checks that all required collections are present

### Required Ansible Collections

| Collection | Version | Purpose |
|------------|---------|---------|
| `community.general` | >= 10.5.0 | 1Password lookup, general utilities |
| `community.routeros` | >= 3.16.0 | MikroTik RouterOS API and CLI |
| `ansible.netcommon` | >= 8.0.0 | Network device connectivity (SSH to router) |
| `arensb.truenas` | >= 0.1.0 | TrueNAS Scale API modules |
| `pfsensible.core` | >= 0.6.1 | pfSense management (optional/future) |

## Step 4: Install Localhost Packages

Install OS-level packages required by playbooks that run tasks on the control host (ISO generation, SSH connectivity):

```bash
ansible-playbook -i localhost, playbooks/prepare-localhost.yaml
```

This installs:

| Package | Used By | Purpose |
|---------|---------|---------|
| `whois` | ISO generation playbooks | `mkpasswd` utility for yescrypt password hashing |
| `xorriso` | ISO generation playbooks | ISO 9660 filesystem manipulation |
| `isolinux` | ISO generation playbooks | ISO boot loader |
| `p7zip-full` | ISO generation playbooks | 7z archive extraction (Ubuntu ISO) |
| `genisoimage` | ISO generation playbooks | ISO image creation |
| `python3-paramiko` | RouterOS playbooks | SSH library for router communication |

## Step 5: Install Terraform

```bash
# Download and install Terraform (or use your package manager)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Initialize the Terraform workspace
cd terraform
terraform init
```

## Step 6: Install and Configure the Incus Client

The Incus client is needed for remote management of Incus nodes and for Terraform's Incus provider:

```bash
# Install the Incus client (Ubuntu)
sudo apt install incus-client

# Generate client certificates (first time only)
./scripts/manage-incus-client-certs.sh generate my-workstation

# Add remote Incus servers
./scripts/manage-incus-client-certs.sh add-remote <remote-name> <ip-address> [port]
```

After generating certificates:
1. **Back up the private key** to your password manager: `./scripts/manage-incus-client-certs.sh backup`
2. **Save the public cert** for Git: `./scripts/manage-incus-client-certs.sh extract > configs.private/.../trusted-client-certs/my-workstation.crt`
3. **Deploy the cert to Incus nodes** using the Ring 0a playbook (see [Ring 0a documentation](05-ring0a-automated.md))

See [Incus Client Certificates](incus-host/incus-client-certificates.md) for the complete certificate management guide.

## Step 7: Configure 1Password CLI

Install the 1Password CLI and set up service account authentication:

```bash
# Install 1Password CLI (see https://developer.1password.com/docs/cli/get-started)
# Then create a service account token for your environment

# Start a time-limited session before running playbooks or Terraform
eval $(./scripts/op-session.sh 2h prod)   # Production, 2-hour session
eval $(./scripts/op-session.sh 1h test)   # Test, 1-hour session
```

The session script creates a short-lived service account token with `read_items` access to the appropriate vault (`HomeLab-Prod` or `HomeLab-Test`).

## Ansible Configuration Reference

The `ansible.cfg` file configures:

```ini
[defaults]
interpreter_python = ~/pythonvenv/default/bin/python3
inventory = ./configs/envbase/,./configs/envtest/inventory/
collections_path = ~/.ansible/collections:~/pythonvenv/default/lib/python3.12/site-packages
```

- **Default inventory**: Points to the test environment. Override with `-i` for production.
- **Python interpreter**: Uses the virtual environment Python.
- **Collections path**: Searches both Galaxy install directory and pip site-packages.

## Validation

After setup, validate that everything works:

```bash
# Validate inventory structure
./scripts/validate-inventory.sh test
./scripts/validate-inventory.sh production  # if configs.private is available

# Validate playbook syntax
./scripts/validate-playbooks.sh test
./scripts/validate-playbooks.sh production

# Verify Terraform can initialize
cd terraform && terraform init && terraform validate
```

## Summary Checklist

- [ ] Python 3.12+ virtual environment at `~/pythonvenv/default/`
- [ ] Repository cloned with submodules (`git submodule update --init`)
- [ ] `./initAnsibleHost.sh` completed successfully
- [ ] `ansible-playbook -i localhost, playbooks/prepare-localhost.yaml` completed
- [ ] Terraform installed and `terraform init` successful
- [ ] Incus client installed and configured with remotes
- [ ] 1Password CLI installed and session creation works
- [ ] Inventory validation passes
- [ ] Playbook syntax validation passes

## Further Reading

- [Principles & Ring Model](01-principles.md) — Why the project is structured this way
- [Architecture Overview](02-architecture.md) — Detailed automation and infrastructure architecture
- [Ring 0 Setup](04-ring0-setup.md) — Next steps after environment setup
