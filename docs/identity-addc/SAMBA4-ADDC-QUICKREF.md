# Samba4 AD DC — Quick Reference

> **Context**: This is a quick-reference card for the Samba4 AD DC subsystem. For the master setup workflow, see [Ring 0 Setup](../04-ring0-setup.md#4-samba4-active-directory-domain-controller-setup). For the full navigation index, see [INDEX.md](./INDEX.md).
>
> **Path conventions**: Uses directory-based inventory (`configs/envbase/` + `configs.private/envprod/inventory/`). Secrets via 1Password. See [Architecture](../02-architecture.md) for details.

## Deployment Checklist

- [ ] Customize group variables in `configs/envbase/group_vars/identityprovider/`
- [ ] Start 1Password session: `eval $(./scripts/op-session.sh 2h prod)`
- [ ] Run Terraform: `terraform apply -var-file=../configs.private/envprod/ring0.tfvars`
- [ ] Configure DHCP reservation in MikroTik for MAC `00:16:3e:11:00:10`
- [ ] Run Ansible: `ansible-playbook -i configs/envbase/ -i configs.private/envprod/inventory/ playbooks/ring0/identity-samba4-addc-setup.yaml`
- [ ] Verify DNS: `host -t SRV _ldap._tcp.yourlab.local.`
- [ ] Test auth: `kinit administrator`

## Configuration Values

| Parameter | Default | Notes |
|-----------|---------|-------|
| Hostname | `dc1` | Max 15 characters |
| Realm | `YOURLAB.LOCAL` | Uppercase, must match DNS domain |
| Domain | `YOURLAB.LOCAL` | NetBIOS domain, max 15 chars, no dots |
| IP Address | `10.0.0.10` | Must match DHCP reservation |
| MAC Address | `00:16:3e:11:00:10` | For DHCP reservation |
| CPU Cores | `2` | Minimum recommended |
| Memory | `4GB` | Minimum recommended |
| Disk | `64GB` | Minimum recommended |

## Key Commands

### Terraform
```bash
# View plan
terraform plan -var-file=../configs.private/envprod/ring0.tfvars

# Apply changes
terraform apply -var-file=../configs.private/envprod/ring0.tfvars

# Destroy VM
terraform destroy -var-file=../configs.private/envprod/ring0.tfvars
```

### Ansible
```bash
# Start 1Password session first
eval $(./scripts/op-session.sh 2h prod)

# Run full setup (Ring 0 — initial)
ansible-playbook \
  -i configs/envbase/ -i configs.private/envprod/inventory/ \
  playbooks/ring0/identity-samba4-addc-setup.yaml

# Run identity lifecycle (Ring 0a — ongoing)
ansible-playbook \
  -i configs/envbase/ -i configs.private/envprod/inventory/ \
  playbooks/ring0a/identity-lifecycle.yaml

# Run with verbose output
ansible-playbook -vv \
  -i configs/envbase/ -i configs.private/envprod/inventory/ \
  playbooks/ring0/identity-samba4-addc-setup.yaml
```

### Samba Tools
```bash
# Domain information
samba-tool domain info yourlab.local

# List users
samba-tool user list

# List groups
samba-tool group list

# Create user
samba-tool user create username

# Change password
samba-tool user setpassword administrator --newpassword='NewPass123!'

# Check domain join
samba-tool domain join --help
```

### DNS Verification
```bash
# Test LDAP SRV record
host -t SRV _ldap._tcp.yourlab.local.

# Test Kerberos SRV record
host -t SRV _kerberos._udp.yourlab.local.

# Test A record
host -t A dc1.yourlab.local.

# Test reverse lookup
host -t PTR 10.0.0.10

# Full DNS validation
dig @10.0.0.10 -t SRV _ldap._tcp.yourlab.local.
```

### Kerberos Testing
```bash
# Request ticket for administrator
kinit administrator@YOURLAB.LOCAL

# List cached tickets
klist

# Destroy tickets
kdestroy

# Test with verbose output
kinit -v administrator@YOURLAB.LOCAL
```

### Service Management
```bash
# Check service status
systemctl status samba

# Restart service
systemctl restart samba

# View logs
journalctl -u samba -n 100 -f

# View NTP status
ntpstat
```

## Secrets Management

All sensitive data is managed through **1Password** using the `community.general.onepassword` lookup plugin:

```bash
# Start a 1Password session before running playbooks
eval $(./scripts/op-session.sh 2h prod)
```

Secrets (admin passwords, DNS forwarders) are resolved at runtime from 1Password vaults. See [Environment Setup](../03-environment-setup.md) for details.

## Files Created/Modified

### Configuration
- `configs.private/envprod/ring0.tfvars` — Terraform VM definition
- `configs/envbase/group_vars/identityprovider/` — Ansible group variables

### Playbooks
- `playbooks/ring0/identity-samba4-addc-setup.yaml` — Initial AD DC setup
- `playbooks/ring0a/identity-lifecycle.yaml` — Ongoing user/group management

### Documentation
- `docs/identity-addc/` — This directory (see [INDEX.md](./INDEX.md))

## Ansible Inventory Customization

Edit group variables in `configs/envbase/group_vars/identityprovider/vars.yaml`:

```yaml
samba4_addc:
  realm: "YOURDOMAIN.COM"              # Must be uppercase
  domain: "YOURDOMAIN"                 # NetBIOS domain (max 15 chars)
  dns_domain: "yourdomain.com"         # Lowercase
  ip_address: "10.0.0.10"              # Your static IP
  dns_forwarders:
    - "10.0.0.1"                       # Your router/forwarder
```

## Troubleshooting

### Playbook Fails on Package Installation
```bash
# SSH to host and update manually
ssh root@10.0.0.10
apt-get update && apt-get upgrade -y
apt-get install samba samba-dsdb-modules krb5-user bind9 -y
```

### Samba Provision Fails
```bash
# Check if already provisioned
ls -la /var/lib/samba/private/sam.ldb

# If exists, backup and remove to re-provision
cp -r /var/lib/samba/private /var/lib/samba/private.backup
rm -f /var/lib/samba/private/*.ldb /var/lib/samba/private/*.tdb
```

### DNS Not Resolving
```bash
# Verify Samba is running
systemctl status samba

# Check DNS port
netstat -tlnp | grep :53

# Query DNS directly
dig @10.0.0.10 dc1.yourlab.local.
```

### NTP Out of Sync
```bash
# Check NTP status
ntpstat

# Force sync
ntpdate -u 10.0.0.1

# Restart NTP
systemctl restart ntp
```

## Next Steps

1. **Join Domain Members**: Configure additional machines to join the AD domain
2. **Enable Group Policy**: Set `enable_group_policy: true` and restart Samba
3. **Create Users/Groups**: Use `samba-tool user create` and `samba-tool group create`
4. **Configure File Shares**: Add shared folders with AD-based access control
5. **Set Password Policies**: Configure domain-wide password complexity requirements
6. **Backup Strategy**: Implement regular backups of AD database
7. **Monitoring**: Set up logging and monitoring for security auditing

## Related Documentation

- [Ring 0 Setup — Samba4 AD DC](../04-ring0-setup.md#4-samba4-active-directory-domain-controller-setup) — Master setup workflow
- [Ring 0a — Identity Configuration](../05-ring0a-automated.md#4-continuous-identity-configuration) — Ongoing management
- [Full Guide](./README-SAMBA4-ADDC.md) — Comprehensive documentation
- [Terraform Module](../../terraform/modules/vm/README.md) — VM module documentation
- [Samba Official Wiki](https://wiki.samba.org/index.php/Samba_Wiki)
