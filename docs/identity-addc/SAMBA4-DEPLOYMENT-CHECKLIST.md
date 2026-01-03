# Samba 4 AD DC - Deployment Checklist & Getting Started

## Pre-Deployment Checklist

### Prerequisites Verification
- [ ] Terraform installed and working (`terraform version`)
- [ ] Ansible installed (`ansible --version`)
- [ ] SSH key configured for root access to Incus hosts
- [ ] Incus cluster has `prodlayer0` project
- [ ] `production` profile exists in Incus
- [ ] `phys-br` network bridge configured
- [ ] `incus-instances` storage pool available
- [ ] Mikrotik router has DHCP server enabled
- [ ] DNS forwarder IP known (usually router IP like 10.0.0.1)

### Documentation Review
- [ ] Read [SAMBA4-IMPLEMENTATION-SUMMARY.md](./SAMBA4-IMPLEMENTATION-SUMMARY.md) (10 min)
- [ ] Review [README-SAMBA4-ADDC.md](./README-SAMBA4-ADDC.md) Quick Start section (5 min)
- [ ] Scan [SAMBA4-ADDC-EXAMPLES.md](./SAMBA4-ADDC-EXAMPLES.md) for your scenario (10 min)

## Configuration Phase (15-20 minutes)

### 1. Customize Ansible Inventory
```bash
# Copy to your own version (optional)
cp configs.private/ring0/samba4-addc-inventory.yaml \
   configs.private/ring0/samba4-addc-inventory.yaml.bak

# Edit the inventory
vi configs.private/ring0/samba4-addc-inventory.yaml
```

**MUST Customize:**
- [ ] `hostname`: Your preferred DC hostname (e.g., `dc1`)
- [ ] `samba4_addc.realm`: Uppercase domain (e.g., `MSZLOCAL`)
- [ ] `samba4_addc.domain`: NetBIOS name (e.g., `MSZLOCAL`)
- [ ] `samba4_addc.dns_domain`: Lowercase domain (e.g., `mszlocal`)
- [ ] `samba4_addc.ip_address`: Desired static IP (e.g., `10.0.0.10`)
- [ ] `samba4_addc.dns_forwarders[0]`: Your router IP (e.g., `10.0.0.1`)

**SHOULD Customize:**
- [ ] `samba4_addc.ntp_servers`: If you have specific NTP servers
- [ ] `enable_group_policy`: Set to `true` if you need Group Policy

### 2. Prepare Environment Variables
```bash
# Create a script for easy setup
cat > /tmp/samba4-env.sh << 'EOF'
#!/bin/bash
export SAMBA4_ADMIN_PASSWORD="MySecurePassword123!"
export SAMBA4_DNS_FORWARDER_1="10.0.0.1"
# Optional:
# export SAMBA4_DNS_FORWARDER_2="8.8.8.8"

echo "Environment variables set:"
echo "  SAMBA4_ADMIN_PASSWORD: [hidden for security]"
echo "  SAMBA4_DNS_FORWARDER_1: $SAMBA4_DNS_FORWARDER_1"
EOF

chmod +x /tmp/samba4-env.sh
source /tmp/samba4-env.sh
```

**Password Requirements:**
- [ ] Minimum 8 characters
- [ ] At least one UPPERCASE letter
- [ ] At least one number
- [ ] At least one special character (!@#$%^&*)

### 3. Verify Terraform Configuration
```bash
# Check current Terraform variables
grep -A20 '"samba4-addc"' configs.private/ring0/ring0.tfvars

# Terraform config should have:
# - mac_address: 00:16:3e:11:00:10
# - image: ubuntu:24.04
# - cpu_cores: 2
# - memory_gb: 4
# - system_disk_gb: 64
```

- [ ] ring0.tfvars contains samba4-addc VM definition
- [ ] MAC address is unique (00:16:3e:11:00:10)
- [ ] All required fields are present

## Deployment Phase (45-90 minutes)

### Phase 1: Terraform VM Provisioning (10-15 minutes)

```bash
# Navigate to Terraform directory
cd terraform

# Verify the plan
terraform plan -var-file=../configs.private/ring0/ring0.tfvars | grep samba4-addc

# Check the output includes:
# - incus_instance.vm[\"samba4-addc\"] will be created
# - Correct CPU, memory, disk sizes
# - Correct MAC address
```

- [ ] Terraform plan reviewed and verified

```bash
# Apply Terraform configuration
terraform apply -var-file=../configs.private/ring0/ring0.tfvars
```

When prompted: `Do you want to perform these actions?` → Type: `yes`

- [ ] Terraform apply completed successfully
- [ ] samba4-addc VM created

```bash
# Verify VM is running
incus list --remote incus.aoostar.mszlocal | grep samba4-addc
```

- [ ] VM shows as RUNNING in Incus

### Phase 2: Network Configuration (5 minutes)

**On your Mikrotik Router:**

```mikrotik
# Add DHCP Reservation
/ip dhcp-server lease
add address=10.0.0.10 \
    mac-address=00:16:3e:11:00:10 \
    comment="Samba4 AD DC" \
    always-broadcast=yes
```

Or via Mikrotik Web UI:
1. Go to: `IP → DHCP Server → Leases`
2. Click: `Add New`
3. MAC Address: `00:16:3e:11:00:10`
4. Address: `10.0.0.10` (matching your inventory IP)
5. Server: `default-dhcp`
6. Click: `OK`

- [ ] DHCP reservation added in router
- [ ] VM has obtained correct IP: `incus info samba4-addc --remote incus.aoostar.mszlocal | grep "eth0"`

### Phase 3: Ansible Configuration (20-30 minutes)

```bash
# Verify environment variables are set
echo $SAMBA4_ADMIN_PASSWORD
echo $SAMBA4_DNS_FORWARDER_1
```

- [ ] Environment variables confirmed

```bash
# Check ansible connectivity to the host
ansible -i configs.private/ring0/samba4-addc-inventory.yaml \
        samba4-addc -m ping

# Should show: "pong" response
```

- [ ] Ansible can reach the host

```bash
# Run the Samba setup playbook
cd /home/mszcool/src/personal/homelabinfracode

ansible-playbook -i configs.private/ring0/samba4-addc-inventory.yaml \
                  playbooks/ring0/samba4-addc-setup.yaml
```

Expected output progression:
1. "Pre-flight validation" ✓
2. "System Preparation" ✓
3. "Pre-provisioning Cleanup" ✓
4. "Samba Provisioning" ✓
5. "Post-provisioning Configuration" ✓
6. "Service Configuration" ✓
7. "DNS Verification" ✓

- [ ] Playbook completed with green "ok" messages
- [ ] No red "failed" or "error" messages

## Post-Deployment Verification (10-15 minutes)

### Step 1: SSH to the AD DC
```bash
ssh root@10.0.0.10
# or
ssh root@dc1.mszlocal  # if DNS is working
```

- [ ] SSH connection successful
- [ ] Prompt shows hostname: `dc1@...`

### Step 2: Verify Samba Service
```bash
systemctl status samba
```

Expected output:
- `Active: active (running)` ✓
- No error messages

- [ ] Samba service is running

### Step 3: Verify Samba Version
```bash
samba --version
```

Should show version 4.x.x

- [ ] Samba version 4.x confirmed

### Step 4: Test DNS Resolution
```bash
# Test LDAP SRV record
host -t SRV _ldap._tcp.mszlocal.

# Expected output:
# _ldap._tcp.mszlocal has SRV record 0 100 389 dc1.mszlocal.
```

- [ ] LDAP SRV record found

```bash
# Test Kerberos SRV record
host -t SRV _kerberos._udp.mszlocal.

# Expected output:
# _kerberos._udp.mszlocal has SRV record 0 100 88 dc1.mszlocal.
```

- [ ] Kerberos SRV record found

```bash
# Test A record
host -t A dc1.mszlocal.

# Expected output:
# dc1.mszlocal has address 10.0.0.10
```

- [ ] A record resolves correctly

### Step 5: Test Kerberos Authentication
```bash
# Request Kerberos ticket
kinit administrator@MSZLOCAL

# When prompted, enter the admin password
# (The one from SAMBA4_ADMIN_PASSWORD environment variable)
```

- [ ] Ticket requested successfully (no errors)

```bash
# List cached tickets
klist

# Expected output showing:
# Ticket cache: FILE:/tmp/krb5cc_0
# Default principal: administrator@MSZLOCAL
# Valid starting ... Service principal ...
```

- [ ] Kerberos ticket is valid

```bash
# Test SMB client
smbclient -L localhost -N

# Should show shares like:
# Sharename       Type      Comment
# ---------       ----      -------
# netlogon        Disk
# sysvol          Disk
```

- [ ] SMB shares accessible

### Step 6: Verify LDAP
```bash
# Test LDAP connectivity
ldapsearch -H ldap://localhost -x -b "" -s base

# Should show LDAP root DSE information
```

- [ ] LDAP responds correctly

## Common Issues & Quick Fixes

### Issue: Ansible connection fails
```bash
# Solution: Check SSH key
ssh-add ~/.ssh/id_ed25519

# Solution: Check host is reachable
ping 10.0.0.10
```

### Issue: DNS not resolving
```bash
# Solution: Check Samba is running
systemctl restart samba
sleep 10

# Solution: Check port 53 is listening
netstat -tlnp | grep :53
```

### Issue: Kerberos ticket fails
```bash
# Solution: Check NTP sync
ntpstat

# Solution: Restart NTP
systemctl restart ntp
sleep 5
kinit administrator@MSZLOCAL
```

### Issue: LDAP bind fails
```bash
# Solution: Check LDAP service
netstat -tlnp | grep 389

# Solution: Restart Samba
systemctl restart samba
sleep 10
```

## Post-Deployment Tasks

### Immediate (Day 1)
- [ ] Change administrator password: `samba-tool user setpassword administrator`
- [ ] Create first user account: `samba-tool user create firstname.lastname`
- [ ] Test domain join on another machine
- [ ] Verify all domain users can authenticate
- [ ] Test file share access

### Short-term (Week 1)
- [ ] Set password expiration policy
- [ ] Create security groups
- [ ] Configure Group Policy (if enabled)
- [ ] Set up backup strategy
- [ ] Document administrator procedures

### Ongoing
- [ ] Monitor logs regularly: `tail -f /var/log/samba/log.*`
- [ ] Verify NTP status: `ntpstat`
- [ ] Check disk usage: `df -h`
- [ ] Monitor DNS queries: `tcpdump -i eth0 port 53`
- [ ] Regular backups of `/var/lib/samba/private/`

## Troubleshooting Resources

If you encounter issues, refer to:

1. **Quick Troubleshooting**: [SAMBA4-ADDC-QUICKREF.md](./SAMBA4-ADDC-QUICKREF.md#troubleshooting)
2. **Detailed Guide**: [README-SAMBA4-ADDC.md](./README-SAMBA4-ADDC.md#troubleshooting)
3. **Example Configs**: [SAMBA4-ADDC-EXAMPLES.md](./SAMBA4-ADDC-EXAMPLES.md#troubleshooting-by-scenario)
4. **Official Samba**: [Samba AD DC Troubleshooting Wiki](https://wiki.samba.org/index.php/Samba_AD_DC_Troubleshooting)

## Key Commands Reference

### For Domain Management
```bash
# List domain users
samba-tool user list

# List groups
samba-tool group list

# Create new user
samba-tool user create john.smith

# Get domain information
samba-tool domain info mszlocal
```

### For Network Verification
```bash
# Test DNS
host -t SRV _ldap._tcp.mszlocal.
dig @10.0.0.10 dc1.mszlocal.

# Test connectivity
kinit administrator@MSZLOCAL
klist

# Test SMB
smbclient -L localhost -N
```

### For Troubleshooting
```bash
# Check service
systemctl status samba

# View logs
journalctl -u samba -n 100 -f

# Test LDAP
ldapsearch -H ldap://localhost -x

# Check NTP
ntpstat

# Monitor DNS
tcpdump -i eth0 port 53
```

## Next Steps After Successful Deployment

1. **Set Password Policies**
   ```bash
   samba-tool domain passwordsettings set --min-pwd-length=12
   samba-tool domain passwordsettings set --complexity=on
   ```

2. **Create Admin Users**
   ```bash
   samba-tool group add "Domain Admins"
   samba-tool user create admin.user --given-name=Admin --surname=User
   samba-tool group addmembers "Domain Admins" admin.user
   ```

3. **Enable Group Policy** (if not already enabled)
   - Edit `/etc/samba/smb.conf`
   - Add `group policy control = yes` in `[global]` section
   - Restart Samba

4. **Join First Domain Member**
   ```bash
   # On a domain member machine:
   net ads join -U administrator
   net ads testjoin
   ```

5. **Set Up Backup**
   ```bash
   tar -czf samba-backup-$(date +%Y%m%d).tar.gz \
     /var/lib/samba/private/ /etc/samba/smb.conf /etc/krb5.conf
   ```

## Support Channels

- **Documentation**: Read [README-SAMBA4-ADDC.md](./README-SAMBA4-ADDC.md)
- **Examples**: Review [SAMBA4-ADDC-EXAMPLES.md](./SAMBA4-ADDC-EXAMPLES.md)
- **Official Wiki**: https://wiki.samba.org/
- **Forum**: Samba mailing lists

## Completion Verification

Once all checkboxes are complete, you have successfully:

✅ Provisioned a Samba 4 Active Directory Domain Controller
✅ Configured DNS and Kerberos authentication
✅ Verified core functionality
✅ Enabled domain member integration

**Congratulations! Your AD DC is ready for production use.**

---

**Document Version**: 1.0
**Last Updated**: January 3, 2026
**Status**: Complete and Ready for Deployment
