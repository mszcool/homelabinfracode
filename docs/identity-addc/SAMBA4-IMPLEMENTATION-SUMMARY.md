# Samba4 Active Directory Domain Controller — Implementation Summary

> **Context**: This is a reference document for the Samba4 AD DC subsystem. For the master setup workflow, see [Ring 0 Setup — Samba4 AD DC](../04-ring0-setup.md#4-samba4-active-directory-domain-controller-setup). For ongoing identity management, see [Ring 0a — Identity Configuration](../05-ring0a-automated.md#4-continuous-identity-configuration).
>
> **Path conventions**: This document may reference legacy paths. The current layout uses directory-based inventory (`configs/envbase/` + `configs.private/envprod/inventory/`) and environment-specific tfvars (`configs.private/envprod/ring0.tfvars` or `configs/envtest/ring0.tfvars`). See [Architecture](../02-architecture.md) for the full inventory model.

## Overview

A fully-automated solution for deploying a Samba4 Active Directory Domain Controller in an Incus virtual machine. This solution combines Terraform for infrastructure provisioning and Ansible for application configuration.

## Key Files

### Configuration

1. **Terraform VM definition** — `configs.private/envprod/ring0.tfvars` (or `configs/envtest/ring0.tfvars`)
   - `samba4-addc` VM definition
   - 2 CPU cores, 4GB memory, 64GB disk
   - Static MAC address: `00:16:3e:11:00:10`
   - Uses Ubuntu 24.04 image

2. **Ansible inventory** — Directory-based at `configs/envbase/` + `configs.private/envprod/inventory/`
   - AD DC host assigned to the `identityprovider` group
   - Group variables in `configs/envbase/group_vars/identityprovider/`
   - Parameterized realm, domain, DNS settings
   - Secrets resolved via 1Password (`community.general.onepassword`)

### Playbooks

3. **`playbooks/ring0/identity-samba4-addc-setup.yaml`** — Initial AD DC setup (Ring 0)
   - All-in-one playbook for complete AD DC setup
   - 6-step deployment process:
     1. System preparation
     2. Package installation
     3. Pre-provisioning cleanup
     4. Samba AD provisioning
     5. Post-provisioning configuration
     6. Service verification
   - Comprehensive validation and error handling

4. **`playbooks/ring0a/identity-lifecycle.yaml`** — Ongoing identity management (Ring 0a)
   - Users, groups, OUs lifecycle management
   - Idempotent, safe to run repeatedly

### Documentation

See [INDEX.md](./INDEX.md) for the full documentation map:

- [README-SAMBA4-ADDC.md](./README-SAMBA4-ADDC.md) — Comprehensive deployment and operations guide
- [SAMBA4-ADDC-QUICKREF.md](./SAMBA4-ADDC-QUICKREF.md) — Quick reference for experienced users
- [SAMBA4-ADDC-EXAMPLES.md](./SAMBA4-ADDC-EXAMPLES.md) — 6 example configurations
- [SAMBA4-DEPLOYMENT-CHECKLIST.md](./SAMBA4-DEPLOYMENT-CHECKLIST.md) — Step-by-step deployment checklist

## Key Features

### Automated Deployment
- Terraform VM provisioning with Incus
- Ubuntu 24.04 LTS base image
- Static MAC address for fixed IP assignment
- Automated package installation and configuration
- Non-interactive Samba provisioning

### Configuration Management
- Inventory-driven configuration (directory-based inventory model)
- Secrets managed via 1Password (`community.general.onepassword`)
- Fully customizable realm, domain, and DNS settings
- DNS forwarder configuration for MikroTik integration
- NTP configuration for time synchronization

### Network Integration
- Static IP assignment via MAC address reservation
- DNS forwarder support (points to MikroTik/upstream DNS)
- DNS SRV record creation and verification
- Reverse DNS zone setup (optional)
- Network interface configuration

### Security
- Password complexity validation
- 1Password-managed secrets (no plaintext in config files)
- Kerberos realm and certificate setup
- LDAPS support capability
- Firewall guidance included

### Verification and Monitoring
- DNS resolution testing
- Kerberos authentication validation
- Service health checks
- Detailed health status output
- Troubleshooting guidance

## Deployment Process

### 1. Customization (15 minutes)
```bash
# Edit group variables for the identityprovider group
vi configs/envbase/group_vars/identityprovider/vars.yaml
```

### 2. Start 1Password session (5 minutes)
```bash
eval $(./scripts/op-session.sh 2h prod)
```

### 3. VM Provisioning (10-15 minutes)
```bash
cd terraform
terraform apply -var-file=../configs.private/envprod/ring0.tfvars
```

### 4. Network Configuration (5 minutes)
- Add DHCP reservation in Mikrotik for MAC `00:16:3e:11:00:10`

### 5. Ansible Configuration (20-30 minutes)
```bash
ansible-playbook \
  -i configs/envbase/ -i configs.private/envprod/inventory/ \
  playbooks/ring0/identity-samba4-addc-setup.yaml
```

### 6. Verification (10 minutes)
```bash
# Test DNS
host -t SRV _ldap._tcp.yourlab.local.

# Test Kerberos
kinit administrator
```

**Total Time: ~60-90 minutes**

## Architecture Benefits

### Terraform Benefits
- Infrastructure as code
- Version control friendly
- Reproducible deployments
- Easily extendable for multiple DCs
- Integrated with existing Incus infrastructure

### Ansible Benefits
- Agentless configuration management
- Idempotent operations
- Detailed logging and verification
- Easy to extend and customize

### Combined Benefits
- Complete infrastructure and application automation
- Dual-repo model (public structure + private secrets)
- Audit trail of all changes
- Easy rollback and recovery
- Scalable to multiple DCs and sites

## Customization Points

### Easy Customizations
- Domain name and realm (3 places in inventory)
- Admin password (environment variable)
- DNS forwarders (list in inventory)
- NTP servers (list in inventory)
- Static IP address
- Hostname

### Advanced Customizations
- Enable Group Policy
- Configure BIND9 DNS backend
- Add reverse DNS zones
- Enable LDAPS
- Configure additional NICs
- Add data disks for Sysvol backups

### Scaling Options
1. **Additional DCs**: Repeat deployment with different IP/MAC
2. **Multi-site**: Configure site-specific subnets
3. **Failover**: Set up DC replication
4. **Load balancing**: Deploy multiple DCs with DNS round-robin

## Integration with Existing Infrastructure

### Terraform Module Compatibility
- Uses existing `vm` module without modifications
- Compatible with Incus provider
- Integrates with Ring 0 project structure
- Follows environment-based tfvars organization

### Ansible Integration
- Consistent with existing playbook structure
- Uses directory-based inventory model
- Follows ring naming conventions
- Compatible with existing group_vars hierarchy

### Network Integration
- Works with existing MikroTik DHCP
- Uses existing network bridges
- Compatible with current DNS setup
- No changes to router configuration (except DHCP reservation)

## Security Considerations

### Built-in Security Features
1. **Authentication**: Kerberos, LDAP, Active Directory
2. **Authorization**: Group Policy capable
3. **Encryption**: Kerberos ticket encryption, optional LDAPS
4. **Audit Logging**: Samba audit logs available
5. **Time Sync**: NTP for Kerberos accuracy

### Recommended Additional Steps
1. Set strong password policies
2. Enable Group Policy
3. Configure firewall rules
4. Regular backups
5. Monitor logs regularly
6. Restrict AD access to authorized networks
7. Use LDAPS in production

## Files Summary

| File | Purpose | Type |
|------|---------|------|
| `configs.private/envprod/ring0.tfvars` | VM definition | Config |
| `configs/envbase/group_vars/identityprovider/` | Samba4 variables | Config |
| `playbooks/ring0/identity-samba4-addc-setup.yaml` | Initial setup playbook | Automation |
| `playbooks/ring0a/identity-lifecycle.yaml` | Ongoing identity management | Automation |
| `README-SAMBA4-ADDC.md` | Full documentation | Docs |
| `SAMBA4-ADDC-QUICKREF.md` | Quick reference | Docs |
| `SAMBA4-ADDC-EXAMPLES.md` | Example configs | Docs |

## Next Steps

1. **Review** the [master setup guide](../04-ring0-setup.md#4-samba4-active-directory-domain-controller-setup)
2. **Customize** group variables in `configs/envbase/group_vars/identityprovider/`
3. **Deploy** the VM with Terraform
4. **Configure** the AD DC with Ansible
5. **Verify** DNS and Kerberos functionality
6. **Manage users/groups** via [Ring 0a identity lifecycle](../05-ring0a-automated.md#4-continuous-identity-configuration)

## Troubleshooting Resources

- [Full Troubleshooting Guide](./README-SAMBA4-ADDC.md#troubleshooting)
- [Quick Reference Troubleshooting](./SAMBA4-ADDC-QUICKREF.md#troubleshooting)
- [Example Configurations](./SAMBA4-ADDC-EXAMPLES.md#troubleshooting-by-scenario)
- [Samba Official Wiki](https://wiki.samba.org/index.php/Samba_AD_DC_Troubleshooting)

## Support & Documentation

- **Quick Start**: 5-10 minutes to understand deployment
- **Full Documentation**: 30+ minutes for complete understanding
- **Examples**: 6 detailed scenarios covering different use cases
- **Quick Reference**: Cheat sheet for common operations

## Implementation Highlights

- **Fully Automated**: No manual steps required after customization
- **Production Ready**: Follows Samba best practices
- **Secure**: 1Password-managed secrets, Kerberos authentication
- **Scalable**: Foundation for multi-DC deployments
- **Infrastructure as Code**: Terraform + Ansible, dual-repo model
- **Idempotent**: Safe to re-run playbooks without side effects
