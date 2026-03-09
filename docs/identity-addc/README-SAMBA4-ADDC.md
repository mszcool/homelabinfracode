# Samba4 Active Directory Domain Controller — Setup Guide

> **Context**: This is the comprehensive deployment and operations guide for the Samba4 AD DC. For the master setup workflow, see [Ring 0 Setup — Samba4 AD DC](../04-ring0-setup.md#4-samba4-active-directory-domain-controller-setup). For ongoing identity management, see [Ring 0a — Identity Configuration](../05-ring0a-automated.md#4-continuous-identity-configuration).
>
> **Path conventions**: This document uses the current directory-based inventory model (`configs/envbase/` + `configs.private/envprod/inventory/`). Secrets are managed via 1Password. See [Architecture](../02-architecture.md) for the full inventory model.

## Overview

This guide provides complete automation for deploying a Samba 4 based Active Directory Domain Controller (ADDC) in an Incus virtual machine within your Ring0 infrastructure. The setup is fully automated using Terraform for VM provisioning and Ansible for Samba 4 configuration.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Ring0 Infrastructure                    │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌───────────────────────┐      ┌──────────────────────┐   │
│  │   Mikrotik Router     │      │   Incus Cluster      │   │
│  │  (DNS Forwarder)      │◄────►│  (compute hosts)     │   │
│  │   10.0.0.1            │      │                      │   │
│  └───────────────────────┘      │  ┌────────────────┐  │   │
│                                 │  │ Samba4 AD DC   │  │   │
│                                 │  │ 10.0.0.10      │  │   │
│                                 │  │ MAC:           │  │   │
│                                 │  │ 00:16:3e:11:.. │  │   │
│                                 │  └────────────────┘  │   │
│                                 │                      │   │
│                                 └──────────────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Terraform Infrastructure**: 
   - Existing Incus cluster with configured remotes
   - Ring0 Terraform workspace in `/home/mszcool/src/personal/homelabinfracode/terraform`

2. **Ansible Environment**:
   - Ansible 2.9+ installed locally
   - SSH connectivity to the target Incus host
   - SSH key configured for authentication

3. **Network Requirements**:
   - Static IP assignment via router DHCP reservation using MAC address `00:16:3e:11:00:10`
   - DNS forwarder accessible (typically your Mikrotik router at `10.0.0.1`)
   - Adequate network connectivity and bandwidth

4. **Incus Configuration**:
   - Incus cluster with `prodlayer0` project
   - `production` profile available
   - `phys-br` network bridge configured
   - `incus-instances` storage pool available

## Quick Start

### Step 1: Customize the Configuration

Edit the group variables for the identity provider:

```bash
vi configs/envbase/group_vars/identityprovider/vars.yaml
```

Key customization points:
- `hostname`: Change from `dc1` to your preferred hostname (max 15 characters)
- `samba4_addc.realm`: Change `YOURLAB.LOCAL` to your DNS domain in uppercase
- `samba4_addc.domain`: Change `YOURLAB.LOCAL` to your NetBIOS domain (15 chars max, no dots)
- `samba4_addc.dns_domain`: Change `yourlab.local` to your DNS domain
- `samba4_addc.ip_address`: Set to the static IP you'll assign in your router
- `samba4_addc.dns_forwarders`: Update with your router's IP address

### Step 2: Start 1Password Session

Secrets (admin password, DNS forwarders) are resolved from 1Password at runtime:

```bash
eval $(./scripts/op-session.sh 2h prod)
```

See [Environment Setup](../03-environment-setup.md) for 1Password configuration details.

### Step 3: Provision the VM with Terraform

Navigate to your Terraform workspace and apply the configuration:

```bash
cd terraform

# Initialize Terraform (if not already done)
terraform init

# Review the Terraform plan
terraform plan -var-file=../configs.private/envprod/ring0.tfvars

# Apply the configuration to create the VM
terraform apply -var-file=../configs.private/envprod/ring0.tfvars
```

Terraform will:
- Create the `samba4-addc` virtual machine
- Allocate 2 CPU cores and 4GB memory
- Attach a 64GB system disk
- Configure the network interface with MAC address `00:16:3e:11:00:10`
- Set boot autostart

Wait for the VM to be created and running, then note the VM's IP address.

### Step 4: Configure Static IP in Your Router

Before running Ansible, ensure your router has a DHCP reservation for the AD DC:

**Mikrotik Configuration Example:**
```
IP → DHCP Server → Leases
- Add new DHCP reservation
- MAC Address: 00:16:3e:11:00:10
- Address: 10.0.0.10 (or your chosen static IP)
- Server: default-dhcp
```

Verify the VM has obtained the correct IP:
```bash
incus info samba4-addc --remote incus.aoostar.yourlab.local
```

### Step 5: Run the Ansible Playbook

Once the VM is running and has the correct static IP, configure Samba4:

```bash
# Run the identity setup playbook with directory-based inventory
ansible-playbook \
  -i configs/envbase/ -i configs.private/envprod/inventory/ \
  playbooks/ring0/identity-samba4-addc-setup.yaml
```

The playbook will:
1. **System Preparation**: Update packages, set hostname, configure /etc/hosts
2. **Install Packages**: Install Samba 4, Kerberos, BIND DNS, and dependencies
3. **Configure NTP**: Set up time synchronization with external servers
4. **Provision AD**: Run `samba-tool domain provision` to create the AD forest
5. **Post-Configuration**: Set up Kerberos, DNS resolver, and service startup
6. **Verification**: Test DNS SRV records and connectivity

## Deployment Components

### File Structure

```
configs/envbase/
├── group_vars/
│   └── identityprovider/       # Samba4 AD DC group variables
configs.private/envprod/
├── ring0.tfvars                    # Terraform VM definition
└── inventory/                      # Host-to-group assignments

playbooks/ring0/
└── identity-samba4-addc-setup.yaml  # Initial AD DC setup playbook

playbooks/ring0a/
└── identity-lifecycle.yaml          # Ongoing identity management
```

### Configuration Parameters

#### Samba 4 AD DC Variables
- **realm**: Kerberos realm (uppercase DNS domain)
- **domain**: NetBIOS domain name (15 chars max, no dots)
- **dns_domain**: DNS domain name (lowercase)
- **admin_password**: Domain administrator password (from environment variable)
- **server_role**: `dc` for domain controller
- **dns_backend**: `SAMBA_INTERNAL` or `BIND9_DLZ`
- **enable_ntp**: Enable NTP for time synchronization
- **enable_group_policy**: Enable Group Policy support (optional)

#### Network Configuration
- **ip_address**: Static IP address (must match router DHCP reservation)
- **netmask**: Subnet mask (default: 255.255.255.0)
- **gateway**: Default gateway (usually router IP)
- **dns_forwarders**: List of upstream DNS servers

#### System Configuration
- **hostname**: Short hostname (max 15 characters)
- **filesystem**: Filesystem type (ext4)
- **ntp_servers**: List of NTP servers for time sync

## Post-Deployment Verification

### 1. Check Service Status

```bash
# SSH to the AD DC
ssh root@10.0.0.10

# Verify Samba service is running
systemctl status samba

# Check Samba version
samba --version

# Verify BIND DNS is running (if BIND9_DLZ backend)
systemctl status bind9
```

### 2. Test DNS Resolution

```bash
# Query DNS SRV records
host -t SRV _ldap._tcp.yourlab.local.
host -t SRV _kerberos._udp.yourlab.local.

# Query A record
host -t A dc1.yourlab.local.

# Query reverse DNS (if configured)
host -t PTR 10.0.0.10
```

### 3. Test Kerberos Authentication

```bash
# Request Kerberos ticket
kinit administrator@YOURLAB.LOCAL

# List cached tickets
klist

# Test with smbclient
smbclient -L localhost -N
```

### 4. Verify LDAP and Domain

```bash
# Check LDAP configuration
ldapsearch -H ldap://localhost -x -b "DC=yourlab.local,DC=dc" -s base

# List domain users
samba-tool user list

# List domain groups
samba-tool group list
```

### 5. Monitor Logs

```bash
# Samba logs
tail -f /var/log/samba/log.*

# DNS logs (if using BIND)
tail -f /var/log/syslog | grep named

# Kerberos logs
tail -f /var/log/auth.log | grep krb5
```

## Domain Member Configuration

Once the AD DC is operational, configure domain members:

### On a Domain Member

```bash
# Install required packages
apt-get install samba winbind krb5-user

# Join the domain
net ads join -U administrator

# Verify domain membership
net ads testjoin

# Set DNS to point to AD DC
# Edit /etc/resolv.conf:
# nameserver 10.0.0.10
# search yourlab.local
```

## Backup and Recovery

### Backup Critical Data

```bash
# Backup Samba database
tar -czf samba-backup-$(date +%Y%m%d).tar.gz \
  /var/lib/samba/private/ \
  /var/lib/samba/state/ \
  /etc/samba/smb.conf \
  /etc/krb5.conf

# Backup to external location
scp samba-backup-*.tar.gz backup-server:/backups/
```

### Restore from Backup

```bash
# Stop Samba service
systemctl stop samba

# Extract backup
tar -xzf samba-backup-YYYYMMDD.tar.gz -C /

# Restart Samba
systemctl start samba

# Verify restoration
samba-tool domain info $(hostname -d)
```

## Troubleshooting

### DNS Not Resolving

```bash
# Check DNS configuration
cat /etc/resolv.conf

# Verify Samba DNS service
systemctl status samba
netstat -tlnp | grep :53

# Check for errors
journalctl -u samba -n 50 --no-pager
```

### Kerberos Issues

```bash
# Check Kerberos configuration
cat /etc/krb5.conf

# Test Kerberos
kinit -v administrator@YOURLAB.LOCAL

# Check ticket cache
klist -a
```

### LDAP Connectivity

```bash
# Test LDAP with ldapsearch
ldapsearch -H ldap://localhost -x -b "DC=yourlab.local,DC=dc" -s base

# Check LDAP service
netstat -tlnp | grep 389
```

### Time Synchronization

```bash
# Check NTP status
ntpstat

# View NTP peers
ntpq -p

# Manually synchronize if needed
ntpdate -u 10.0.0.1
```

## Administrative Tasks

### Change Administrator Password

```bash
samba-tool user setpassword administrator --newpassword='NewPassword123!'
```

### Create New User

```bash
samba-tool user create testuser
# Follow prompts for password
```

### Enable Group Policy

Edit `/etc/samba/smb.conf` and add to `[global]` section:

```ini
[global]
    # ... existing configuration ...
    group policy control = yes
```

Then restart Samba:

```bash
systemctl restart samba
```

### Create Reverse DNS Zone

```bash
samba-tool dns zonecreate 10.0.0.10 0.0.10.in-addr.arpa -U administrator

# Add reverse record for DC
samba-tool dns add 10.0.0.10 0.0.10.in-addr.arpa 10 PTR dc1.yourlab.local. -U administrator
```

## Security Considerations

1. **Strong Passwords**: Use complex passwords meeting Microsoft requirements
2. **Network Security**: Restrict AD access via firewall rules
3. **Time Synchronization**: Critical for Kerberos - monitor NTP status
4. **Backups**: Regular backups of AD database and configuration
5. **User Permissions**: Follow principle of least privilege
6. **Audit Logging**: Enable audit logging for compliance
7. **TLS/LDAPS**: Consider enabling LDAPS for encrypted communications

## Integration with Existing Infrastructure

### Update DHCP Configuration

Ensure your DHCP server has a static reservation:

```
IP Address: 10.0.0.10
MAC Address: 00:16:3e:11:00:10
Server: Set AD DC as the primary DNS server
```

### Update Firewall Rules

Allow the following ports from domain members to the AD DC:

- **53** (TCP/UDP): DNS
- **88** (TCP/UDP): Kerberos
- **135** (TCP): RPC Endpoint Mapper
- **139** (TCP): NetBIOS Session Service
- **389** (TCP/UDP): LDAP
- **445** (TCP): SMB
- **464** (TCP/UDP): Kerberos Password Change
- **3268** (TCP): LDAP Global Catalog

### Ansible Playbook Structure

The main playbook (`identity-samba4-addc-setup.yaml`) includes all setup steps in a single, easy-to-follow structure with clear sections for each phase of the deployment.

## Additional Resources

- [Samba Wiki - Setting up Samba as an AD DC](https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller)
- [Samba Tool Documentation](https://manpages.ubuntu.com/manpages/focal/man8/samba-tool.8.html)
- [Kerberos Configuration](https://web.mit.edu/kerberos/krb5-latest/doc/user/user_config/index.html)
- [Active Directory Naming FAQ](https://wiki.samba.org/index.php/Active_Directory_Naming_FAQ)

## License

This configuration is part of the homelab infrastructure-as-code project. See the main repository LICENSE file for details.

## Support

For issues or questions:
1. Check the [Samba AD DC Troubleshooting](https://wiki.samba.org/index.php/Samba_AD_DC_Troubleshooting) page
2. Review Samba logs: `journalctl -u samba -n 100`
3. Check domain status: `samba-tool domain info $(hostname -d)`
