# Incus Remote Client Certificate Management

Complete guide for managing TLS client certificates for secure remote access to Incus servers.

**Last Updated:** October 10, 2025

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Quick Start](#quick-start)
4. [File Structure](#file-structure)
5. [Configuration Reference](#configuration-reference)
6. [Step-by-Step Setup](#step-by-step-setup)
7. [Common Scenarios](#common-scenarios)
8. [Helper Script Usage](#helper-script-usage)
9. [Security Best Practices](#security-best-practices)
10. [Troubleshooting](#troubleshooting)
11. [Maintenance](#maintenance)
12. [Reference](#reference)

---

## Overview

### What This Is

Incus uses TLS client certificates for authentication and authorization. This system allows you to:

- **Store public certificates** in Git (in `configs.private/infra-bootstrap/incus/trusted-client-certs/`)
- **Keep private keys secure** in your password manager (KeePass, 1Password, etc.)
- **Restrict client access** to specific projects (default, production, etc.)
- **Automate certificate deployment** via Ansible

### How It Works

1. Generate a TLS certificate pair on your client machine
2. Store the private key securely in your password manager
3. Save the public certificate as a file in your infrastructure repository
4. Reference the certificate in your Incus inventory configuration
5. Deploy certificates to Incus servers via Ansible
6. Connect remotely using the certificate

### Key Benefits

- ✅ Certificate-based authentication (no passwords)
- ✅ Project-level access control
- ✅ Infrastructure as Code - all config in Git
- ✅ Automated deployment
- ✅ Secure key management

---

## Architecture

### Authentication Flow

```
┌─────────────────────┐                    ┌──────────────────┐
│  Your Client        │                    │  Incus Server    │
│  Workstation        │                    │  (e.g. aoostar)  │
│                     │                    │                  │
│  client.key ────────┼─── TLS Auth ────>  │  Trusted Certs   │
│  (Private - PW Mgr) │                    │  (Public - Git)  │
│                     │                    │                  │
│  client.crt ────────┼────────────────────┼> Projects:       │
│  (Public - Git)     │                    │  - default       │
│                     │                    │  - production    │
└─────────────────────┘                    └──────────────────┘
```

### Components

- **Client Certificate** (`~/.config/incus/client.crt`): Public key for authentication
- **Client Private Key** (`~/.config/incus/client.key`): Private key (never committed to Git)
- **Certificate Files** (`configs.private/.../incus/trusted-client-certs/*.crt`): Public certificates in Git
- **Inventory Config** (`host-incus-cluster.yaml`): References to certificate files with access rules
- **Ansible Tasks** (`host-incus-manage-client-cert-tasks.yaml`): Deployment automation

---

## Quick Start

### 5-Minute Setup

```bash
# 1. Generate certificate
./scripts/manage-incus-client-certs.sh generate my-workstation

# 2. Backup to password manager
./scripts/manage-incus-client-certs.sh backup
# → Import files into KeePass/1Password, then delete backup folder

# 3. Save public cert to file
./scripts/manage-incus-client-certs.sh extract > \
  configs.private/infra-bootstrap/incus/trusted-client-certs/my-workstation.crt

# 4. Add to inventory (edit host-incus-cluster.yaml)
# Add under incus_trusted_clients: section

# 5. Deploy to servers
ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
  playbooks/ring0a/host-incus-update.yaml

# 6. Configure remote
./scripts/manage-incus-client-certs.sh add-remote incus-aoostar 10.10.0.20 8443

# 7. Test
incus remote switch incus-aoostar
incus list
```

---

## File Structure

```
homelabinfracode/
├── configs.private/infra-bootstrap/
│   ├── host-incus-cluster.yaml              # Main inventory (includes cert config)
│   └── incus/
│       └── trusted-client-certs/            # Public certificate files
│           ├── README.md
│           ├── workstation-admin-mszcool.crt
│           └── ci-pipeline-production.crt
│
├── playbooks/
│   ├── ring0a/
│   │   └── host-incus-update.yaml           # Main playbook (auto includes certs)
│   └── tasks/
│       └── host-incus-manage-client-cert-tasks.yaml
│
├── scripts/
│   └── manage-incus-client-certs.sh         # Helper script
│
└── docs/
    └── incus-client-certificates.md         # This file

Client Machine:
~/.config/incus/
├── client.crt                                # Public cert (safe to share)
└── client.key                                # Private key (NEVER share!)

Password Manager:
Incus Certificates/
├── client.crt                                # Backup
└── client.key                                # Backup (CRITICAL - keep secure!)
```

---

## Configuration Reference

### Inventory Configuration

**File:** `configs.private/infra-bootstrap/host-incus-cluster.yaml`

```yaml
all:
  vars:
    # ... other configuration ...
    
    # Trusted client certificates for remote Incus access
    incus_trusted_clients:
      - name: "unique-client-name"              # Required: Unique identifier
        description: "Human readable desc"      # Required: What/who is this client
        certificate_file: "incus/trusted-client-certs/client-name.crt"  # Required: Path to cert file
        restricted: true                        # Optional: Default false (full access)
        projects:                               # Optional: List of allowed projects
          - "default"                           # Empty or omit for all projects
          - "production"
```

### Parameters

| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `name` | Yes | string | Unique identifier for the certificate in Incus |
| `description` | Yes | string | Human-readable description for documentation |
| `certificate_file` | Yes | string | Relative path from `configs.private/infra-bootstrap/` to the certificate file |
| `restricted` | No | boolean | `false` (default) = full admin access; `true` = limited to specified projects |
| `projects` | No | array | List of project names this certificate can access. Empty = all projects (when `restricted: false`) |

### Access Levels

| Scenario | `restricted` | `projects` | Access |
|----------|-------------|-----------|---------|
| Full Admin | `false` | `[]` | All projects, full admin rights |
| Production Only | `true` | `["production"]` | Production project only |
| Developer | `true` | `["default"]` | Default project only |
| Multi-Project | `true` | `["default", "staging"]` | Multiple specified projects |

---

## Step-by-Step Setup

### Prerequisites

- Incus servers are running and accessible
- SSH access to Incus servers
- Ansible installed on your workstation
- Password manager installed (KeePass, 1Password, etc.)

### Step 1: Generate Client Certificate

On your workstation:

```bash
cd /path/to/homelabinfracode
./scripts/manage-incus-client-certs.sh generate workstation-admin-mszcool
```

This creates:
- `~/.config/incus/client.crt` (public certificate)
- `~/.config/incus/client.key` (private key - **keep secret!**)

### Step 2: Backup Private Key

```bash
./scripts/manage-incus-client-certs.sh backup
```

Then:
1. Open your password manager
2. Create entry: "Incus Client Certificates"
3. Attach both `client.key` and `client.crt` from the backup directory
4. Add notes: server IPs, date generated, purpose
5. Delete the backup directory: `rm -rf ~/incus-cert-backup-*`

**⚠️ CRITICAL: Never commit `client.key` to Git!**

### Step 3: Save Public Certificate to File

```bash
./scripts/manage-incus-client-certs.sh extract > \
  configs.private/infra-bootstrap/incus/trusted-client-certs/workstation-admin-mszcool.crt
```

This saves the public certificate as a file in your repository.

### Step 4: Add Certificate to Inventory

Edit `configs.private/infra-bootstrap/host-incus-cluster.yaml`:

```yaml
all:
  vars:
    # ... existing configuration ...
    
    incus_trusted_clients:
      - name: "workstation-admin-mszcool"
        description: "Mario's admin workstation - full access"
        certificate_file: "incus/trusted-client-certs/workstation-admin-mszcool.crt"
        restricted: false
        projects: []
```

For restricted access:

```yaml
      - name: "ci-pipeline-production"
        description: "CI/CD pipeline for production deployments"
        certificate_file: "incus/trusted-client-certs/ci-pipeline-production.crt"
        restricted: true
        projects:
          - "production"
```

### Step 5: Commit to Git

```bash
git add configs.private/infra-bootstrap/host-incus-cluster.yaml
git add configs.private/infra-bootstrap/incus/trusted-client-certs/workstation-admin-mszcool.crt
git commit -m "Add admin workstation certificate for Incus remote access"
git push
```

### Step 6: Deploy Certificates to Servers

```bash
# Deploy to all Incus servers
ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
  playbooks/ring0a/host-incus-update.yaml

# Or deploy to a single server
ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
  playbooks/ring0a/host-incus-update.yaml \
  --limit incus.aoostar.mszlocal
```

Certificate management is automatically included in the update playbook.

### Step 7: Configure Remote on Client

```bash
./scripts/manage-incus-client-certs.sh add-remote incus-aoostar 10.10.0.20 8443
```

Or manually:

```bash
incus remote add incus-aoostar 10.10.0.20:8443 --accept-certificate
```

### Step 8: Test Connection

```bash
# Switch to remote
incus remote switch incus-aoostar

# List available projects
incus project list

# List instances
incus list

# Test on other remotes
incus remote switch incus-peladin
incus list
```

---

## Common Scenarios

### Scenario 1: Admin Workstation (Full Access)

**Use Case:** Your primary workstation needs full admin access to all projects.

**Certificate File:** `workstation-admin-mszcool.crt`

**Configuration:**
```yaml
- name: "workstation-admin-mszcool"
  description: "Mario's admin workstation"
  certificate_file: "incus/trusted-client-certs/workstation-admin-mszcool.crt"
  restricted: false
  projects: []
```

**Access:** All projects, full administrative rights

### Scenario 2: CI/CD Pipeline (Production Only)

**Use Case:** GitHub Actions or similar CI/CD needs to deploy only to production.

**Certificate File:** `github-actions-ci.crt`

**Configuration:**
```yaml
- name: "github-actions-ci"
  description: "GitHub Actions CI/CD pipeline"
  certificate_file: "incus/trusted-client-certs/github-actions-ci.crt"
  restricted: true
  projects:
    - "production"
```

**Access:** Production project only, cannot access other projects

### Scenario 3: Developer Workstation (Development Only)

**Use Case:** Team member needs access to development/default project only.

**Certificate File:** `dev-alice-workstation.crt`

**Configuration:**
```yaml
- name: "dev-alice-workstation"
  description: "Alice's development workstation"
  certificate_file: "incus/trusted-client-certs/dev-alice-workstation.crt"
  restricted: true
  projects:
    - "default"
```

**Access:** Default project only

### Scenario 4: Automation Scripts (Multi-Project)

**Use Case:** Maintenance scripts need access to multiple projects.

**Certificate File:** `automation-scripts.crt`

**Configuration:**
```yaml
- name: "automation-scripts"
  description: "Automation and maintenance scripts"
  certificate_file: "incus/trusted-client-certs/automation-scripts.crt"
  restricted: true
  projects:
    - "default"
    - "staging"
    - "production"
```

**Access:** Multiple specified projects

---

## Helper Script Usage

The `scripts/manage-incus-client-certs.sh` script provides convenient commands for certificate management.

### Available Commands

```bash
# Show help
./scripts/manage-incus-client-certs.sh help

# Generate new certificate
./scripts/manage-incus-client-certs.sh generate <client-name>

# Extract public certificate
./scripts/manage-incus-client-certs.sh extract

# Backup to password manager
./scripts/manage-incus-client-certs.sh backup

# Add Incus remote
./scripts/manage-incus-client-certs.sh add-remote <name> <ip> [port]

# List configured remotes
./scripts/manage-incus-client-certs.sh list-remotes

# Show certificate info
./scripts/manage-incus-client-certs.sh info
```

### Examples

```bash
# Generate certificate for workstation
./scripts/manage-incus-client-certs.sh generate workstation-admin-mszcool

# Backup to password manager
./scripts/manage-incus-client-certs.sh backup
# Follow instructions, then delete backup folder

# Extract and save certificate
./scripts/manage-incus-client-certs.sh extract > \
  configs.private/infra-bootstrap/incus/trusted-client-certs/workstation-admin-mszcool.crt

# Add remote server
./scripts/manage-incus-client-certs.sh add-remote incus-aoostar 10.10.0.20 8443

# Show certificate details
./scripts/manage-incus-client-certs.sh info

# List remotes
./scripts/manage-incus-client-certs.sh list-remotes
```

---

## Security Best Practices

### DO ✅

- **Store private keys in password manager** (KeePass, 1Password)
- **Commit public certificates to Git** (in `incus/trusted-client-certs/` directory)
- **Use `restricted: true`** for non-admin clients
- **Use strong, unique names** for each certificate
- **Regularly audit** trusted certificates on servers
- **Use different certificates** for different purposes (admin vs CI/CD)
- **Set appropriate expiry dates** (default: 10 years)
- **Keep certificate files organized** in the dedicated directory
- **Back up private keys** securely before deployment
- **Test certificate access** after deployment

### DON'T ❌

- **Never commit `client.key`** (private key) to Git
- **Never share private keys** via email/chat
- **Don't use `restricted: false`** for automation/CI/CD
- **Don't reuse certificates** across multiple clients
- **Don't leave unrestricted access** for service accounts
- **Don't mix private keys** with public certificates in the repository
- **Don't skip password manager** backup step
- **Don't ignore certificate expiration** dates

### Security Checklist

Before deployment:
- [ ] Private key backed up in password manager
- [ ] Private key NOT in Git repository
- [ ] Public certificate in `incus/trusted-client-certs/`
- [ ] Used `restricted: true` for non-admin users
- [ ] Tested connection with `incus list`
- [ ] Verified project access with `incus project list`
- [ ] `.gitignore` protects `*.key` files

---

## Troubleshooting

### Problem: "Certificate not trusted"

**Symptom:** `incus list` returns "Certificate not trusted" error

**Solutions:**

1. **Verify certificate is deployed:**
   ```bash
   ssh mszmaster@10.10.0.20
   incus config trust list
   ```

2. **Check certificate fingerprint:**
   ```bash
   openssl x509 -in ~/.config/incus/client.crt -fingerprint -noout -sha256
   ```

3. **Re-deploy certificates:**
   ```bash
   ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
     playbooks/ring0a/host-incus-update.yaml
   ```

### Problem: "Connection refused"

**Symptom:** Cannot connect to remote server

**Solutions:**

1. **Check firewall allows port 8443:**
   ```bash
   ssh mszmaster@10.10.0.20
   sudo ufw status | grep 8443
   ```

2. **Verify Incus is listening:**
   ```bash
   ssh mszmaster@10.10.0.20
   incus config get core.https_address
   ```

3. **Test connectivity:**
   ```bash
   curl -k https://10.10.0.20:8443/
   ```

### Problem: "Permission denied" on projects

**Symptom:** Cannot see expected projects

**Solutions:**

1. **Check certificate restrictions:**
   ```bash
   ssh mszmaster@10.10.0.20
   incus config trust list
   incus config trust show <fingerprint>
   ```

2. **Verify `projects:` list** in `host-incus-cluster.yaml`

3. **Switch to allowed project:**
   ```bash
   incus project list
   incus project switch <project-name>
   ```

### Problem: Certificate file not found

**Symptom:** Ansible fails with "file not found" error

**Solutions:**

1. **Check file path** in inventory is relative to `configs.private/infra-bootstrap/`

2. **Verify file exists:**
   ```bash
   ls -la configs.private/infra-bootstrap/incus/trusted-client-certs/
   ```

3. **Check file permissions:**
   ```bash
   ls -l configs.private/infra-bootstrap/incus/trusted-client-certs/*.crt
   ```

### Problem: Multiple certificates, wrong one used

**Symptom:** Authentication works but with wrong permissions

**Note:** Incus uses a single certificate at `~/.config/incus/client.{crt,key}`. To use multiple certificates:

**Solutions:**

1. **Use different Linux users** (each has own `~/.config/incus/`)

2. **Manual swap:**
   ```bash
   mv ~/.config/incus/client.{crt,key} ~/.config/incus/client-admin.{crt,key}
   cp ~/.config/incus/client-dev.{crt,key} ~/.config/incus/client.{crt,key}
   ```

3. **Use `INCUS_CONF` environment variable:**
   ```bash
   mkdir -p ~/.config/incus-admin ~/.config/incus-dev
   export INCUS_CONF=~/.config/incus-admin
   incus list
   ```

---

## Maintenance

### List All Trusted Certificates

**On server:**
```bash
ssh mszmaster@10.10.0.20
incus config trust list
```

**Via Ansible:**
```bash
ansible -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
  incus -m shell -a "incus config trust list"
```

### Revoke a Certificate

1. **Remove from inventory:**
   Edit `host-incus-cluster.yaml` and remove the certificate entry

2. **Remove from servers manually:**
   ```bash
   ssh mszmaster@10.10.0.20
   incus config trust list
   incus config trust remove <fingerprint>
   ```

3. **Or wait for next deployment** (certificate won't be re-added)

### Rotate a Certificate

1. **Generate new certificate** with the same name
2. **Update certificate file** in `incus/trusted-client-certs/`
3. **Deploy via Ansible:**
   ```bash
   ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
     playbooks/ring0a/host-incus-update.yaml
   ```
4. **Update password manager** with new private key
5. **Test connection**

### Audit Certificates

**Regular audit checklist:**
- [ ] List all trusted certificates on each server
- [ ] Verify each certificate has a known owner
- [ ] Check for expired certificates
- [ ] Confirm project restrictions are appropriate
- [ ] Remove certificates for departed team members
- [ ] Update documentation with current certificate list

---

## Reference

### Environment Variables

| Variable | Description |
|----------|-------------|
| `INCUS_CONF` | Path to client configuration directory (default: `~/.config/incus`) |
| `INCUS_PROJECT` | Name of project to use (overrides configured default) |
| `INCUS_REMOTE` | Name of remote to use (overrides configured default) |

### Client Commands

```bash
# Remote management
incus remote list                    # List configured remotes
incus remote switch <name>           # Switch to remote
incus remote get-default             # Show current remote

# Project management
incus project list                   # List available projects
incus project switch <name>          # Switch to project

# Instance management
incus list                           # List instances in current project
incus info <instance>                # Show instance details

# Certificate info
openssl x509 -in ~/.config/incus/client.crt -text -noout
openssl x509 -in ~/.config/incus/client.crt -fingerprint -noout
```

### Server Commands

```bash
# Trust management
incus config trust list              # List trusted certificates
incus config trust show <fingerprint># Show certificate details
incus config trust remove <fingerprint> # Remove certificate

# Configuration
incus config get core.https_address  # Show Incus listen address
incus config set core.https_address <ip>:<port> # Set listen address
```

### Ansible Commands

```bash
# Deploy certificates (automatic with update)
ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
  playbooks/ring0a/host-incus-update.yaml

# Deploy to single server
ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
  playbooks/ring0a/host-incus-update.yaml \
  --limit incus.aoostar.mszlocal

# Dry run
ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
  playbooks/ring0a/host-incus-update.yaml \
  --check

# Test connectivity
ansible -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
  incus -m ping
```

### File Locations

**Client:**
- Certificates: `~/.config/incus/client.{crt,key}`
- Configuration: `~/.config/incus/config.yml`
- Server certs: `~/.config/incus/servercerts/`

**Repository:**
- Inventory: `configs.private/infra-bootstrap/host-incus-cluster.yaml`
- Certificates: `configs.private/infra-bootstrap/incus/trusted-client-certs/*.crt`
- Tasks: `playbooks/tasks/host-incus-manage-client-cert-tasks.yaml`
- Script: `scripts/manage-incus-client-certs.sh`

**Server:**
- Trust store: `/var/lib/incus/` (managed by Incus)

---

## Additional Resources

### Official Documentation
- [Incus Authentication](https://linuxcontainers.org/incus/docs/main/authentication/)
- [Incus Projects](https://linuxcontainers.org/incus/docs/main/projects/)
- [Incus Remote API](https://linuxcontainers.org/incus/docs/main/remotes/)
- [Incus Environment Variables](https://linuxcontainers.org/incus/docs/main/environment/)

### Related Files
- Certificate Directory README: `configs.private/infra-bootstrap/incus/trusted-client-certs/README.md`
- Main Playbook: `playbooks/ring0a/host-incus-update.yaml`
- Certificate Tasks: `playbooks/tasks/host-incus-manage-client-cert-tasks.yaml`
- Helper Script: `scripts/manage-incus-client-certs.sh`

---

**Document Version:** 2.0 (Consolidated)  
**Last Updated:** October 10, 2025  
**Maintained By:** Infrastructure Team
