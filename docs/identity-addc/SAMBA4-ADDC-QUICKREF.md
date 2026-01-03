# Samba 4 AD DC - Quick Reference

## Deployment Checklist

- [ ] Customize `configs.private/ring0/samba4-addc-inventory.yaml` with your environment
- [ ] Set environment variables: `SAMBA4_ADMIN_PASSWORD`, `SAMBA4_DNS_FORWARDER_1`
- [ ] Run Terraform: `terraform apply -var-file=../configs.private/ring0/ring0.tfvars`
- [ ] Configure DHCP reservation in Mikrotik for MAC `00:16:3e:11:00:10`
- [ ] Run Ansible: `ansible-playbook -i configs.private/ring0/samba4-addc-inventory.yaml playbooks/ring0/samba4-addc-setup.yaml`
- [ ] Verify DNS: `host -t SRV _ldap._tcp.mszlocal.`
- [ ] Test auth: `kinit administrator`

## Configuration Values

| Parameter | Default | Notes |
|-----------|---------|-------|
| Hostname | `dc1` | Max 15 characters |
| Realm | `MSZLOCAL` | Uppercase, must match DNS domain |
| Domain | `MSZLOCAL` | NetBIOS domain, max 15 chars, no dots |
| IP Address | `10.0.0.10` | Must match DHCP reservation |
| MAC Address | `00:16:3e:11:00:10` | For DHCP reservation |
| CPU Cores | `2` | Minimum recommended |
| Memory | `4GB` | Minimum recommended |
| Disk | `64GB` | Minimum recommended |

## Key Commands

### Terraform
```bash
# View plan
terraform plan -var-file=../configs.private/ring0/ring0.tfvars

# Apply changes
terraform apply -var-file=../configs.private/ring0/ring0.tfvars

# Destroy VM
terraform destroy -var-file=../configs.private/ring0/ring0.tfvars
```

### Ansible
```bash
# Run full setup
ansible-playbook -i configs.private/ring0/samba4-addc-inventory.yaml playbooks/ring0/samba4-addc-setup.yaml

# Run only package installation
ansible-playbook -i configs.private/ring0/samba4-addc-inventory.yaml -e "samba4_update_system=true" playbooks/ring0/samba4-addc-setup.yaml

# Use verbose output
ansible-playbook -vv -i configs.private/ring0/samba4-addc-inventory.yaml playbooks/ring0/samba4-addc-setup.yaml
```

### Samba Tools
```bash
# Domain information
samba-tool domain info mszlocal

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
host -t SRV _ldap._tcp.mszlocal.

# Test Kerberos SRV record
host -t SRV _kerberos._udp.mszlocal.

# Test A record
host -t A dc1.mszlocal.

# Test reverse lookup
host -t PTR 10.0.0.10

# Full DNS validation
dig @10.0.0.10 -t SRV _ldap._tcp.mszlocal.
```

### Kerberos Testing
```bash
# Request ticket for administrator
kinit administrator@MSZLOCAL

# List cached tickets
klist

# Destroy tickets
kdestroy

# Test with verbose output
kinit -v administrator@MSZLOCAL
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

## Environment Variables

```bash
# Required
export SAMBA4_ADMIN_PASSWORD="Passw0rd123!"
export SAMBA4_DNS_FORWARDER_1="10.0.0.1"

# Optional
export SAMBA4_DNS_FORWARDER_2="1.1.1.1"
```

## Files Created/Modified

### New Files
- `configs.private/ring0/samba4-addc-inventory.yaml` - Ansible inventory
- `playbooks/ring0/samba4-addc-setup.yaml` - Main setup playbook
- `docs/identity-addc/README-SAMBA4-ADDC.md` - Full documentation
- `docs/identity-addc/SAMBA4-ADDC-QUICKREF.md` - Quick reference
- `docs/identity-addc/SAMBA4-ADDC-EXAMPLES.md` - Example configurations
- `docs/identity-addc/SAMBA4-DEPLOYMENT-CHECKLIST.md` - Deployment checklist

### Modified Files
- `configs.private/ring0/ring0.tfvars` - Added samba4-addc VM definition

## Ansible Inventory Customization

Edit `configs.private/ring0/samba4-addc-inventory.yaml`:

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
dig @10.0.0.10 dc1.mszlocal.
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

- [Main README](./README-SAMBA4-ADDC.md) - Comprehensive guide
- [Terraform Module](../../terraform/modules/vm/README.md) - VM module documentation
- [Samba Official Wiki](https://wiki.samba.org/index.php/Samba_Wiki) - Official documentation
