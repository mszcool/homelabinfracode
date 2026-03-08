# Samba4 AD DC — Example Configurations

> **Context**: These are example configurations for different deployment scenarios. For the master setup workflow, see [Ring 0 Setup — Samba4 AD DC](../04-ring0-setup.md#4-samba4-active-directory-domain-controller-setup). For the full navigation index, see [INDEX.md](./INDEX.md).
>
> **Path conventions**: Uses directory-based inventory (`configs/envbase/` + `configs.private/envprod/inventory/`). Secrets via 1Password. See [Architecture](../02-architecture.md).

This file contains example configurations for different deployment scenarios.

## Example 1: Default Configuration (yourlab.local domain)

### Secrets

Admin password and DNS forwarders are resolved from 1Password at runtime:

```bash
eval $(./scripts/op-session.sh 2h prod)
```

### Inventory Customization

Edit `configs/envbase/group_vars/identityprovider/vars.yaml`:
```hcl
"samba4-addc" = {
  target_remote            = "incus.aoostar.yourlab.local"
  incus_project            = "prodlayer0"
  incus_profile            = "production"
  cpu_cores                = 2
  memory_gb                = 4
  system_disk_gb           = 64
  mac_address              = "00:16:3e:11:00:10"
}
```

## Example 2: Production Domain Configuration

For a larger deployment with separate production domain:

### Inventory Customization
```yaml
samba4_addc:
  realm: "CORP.EXAMPLE.COM"
  domain: "CORP"
  dns_domain: "corp.example.com"
  ip_address: "172.20.1.10"
  dns_forwarders:
    - "172.20.0.1"           # Production router
    - "8.8.8.8"              # Public fallback
  
  # Enable additional features for production
  enable_group_policy: true
  enable_ntp: true
  
  # Production NTP servers
  ntp_servers:
    - "time.google.com"
    - "time.cloudflare.com"
    - "time.nist.gov"
```

### DHCP Configuration (Mikrotik)
```
/ip dhcp-server lease
add address=172.20.1.10 \
    mac-address=00:16:3e:11:00:10 \
    comment="Production AD DC"
```

## Example 3: High-Capacity Configuration

For organizations needing more resources:

### Terraform Configuration
```hcl
"samba4-addc-prod" = {
  target_remote            = "incus.peladin.yourlab.local"   # Different host
  incus_project            = "prodlayer1"               # Different project
  incus_profile            = "production"
  cpu_cores                = 4          # Increased
  memory_gb                = 8          # Increased
  system_disk_gb           = 128        # Increased
  mac_address              = "00:16:3e:11:00:11"
  data_disks = [
    {
      name = "sysvol"
      pool = "incus-instances"
      size = 50
    },
    {
      name = "backup"
      pool = "incus-instances"
      size = 100
    }
  ]
}
```

### Inventory Customization
```yaml
samba4_addc:
  realm: "ENTERPRISE.LOCAL"
  domain: "ENTERPRISE"
  dns_domain: "enterprise.local"
  enable_group_policy: true
  
  # Additional admin can add more DNS forwarders for resilience
  dns_forwarders:
    - "10.0.0.1"
    - "10.0.0.2"
    - "8.8.8.8"
    - "8.8.4.4"
```

## Example 4: Multi-Site Deployment

For organizations with multiple geographic locations:

### Site 1 - Primary DC (pdx.example.com)
```yaml
samba4_addc:
  realm: "PDX.EXAMPLE.COM"
  domain: "PDX"
  dns_domain: "pdx.example.com"
  ip_address: "192.168.1.10"
  dns_forwarders:
    - "192.168.1.1"
```

### Site 2 - Secondary DC (sjc.example.com)
After setting up the primary DC, configure a secondary (replica) DC:

```bash
# On secondary DC, join to existing forest:
samba-tool domain join sjc.example.com.dc \
  -U PDX\\administrator \
  --dns-backend=SAMBA_INTERNAL
```

## Example 5: Development/Test Configuration

For testing before production deployment:

### Inventory Customization
```yaml
all:
  hosts:
    samba4-addc-test:
      ansible_host: samba4-addc-test.lab
      ansible_user: root

  vars:
    hostname: "dctest"
    
    samba4_addc:
      realm: "LABTEST"
      domain: "LABTEST"
      dns_domain: "labtest"
      ip_address: "10.10.0.10"
      dns_forwarders:
        - "8.8.8.8"
      
      # Disable some features for testing
      enable_group_policy: false
      enable_ntp: true
      
      # Use test NTP servers
      ntp_servers:
        - "pool.ntp.org"
```

### Terraform Configuration
```hcl
"samba4-addc-test" = {
  target_remote            = "incus.odyssey.yourlab.local"   # Test host
  incus_project            = "test"
  incus_profile            = "default"
  cpu_cores                = 1
  memory_gb                = 2
  system_disk_gb           = 32
  mac_address              = "00:16:3e:11:00:20"
}
```

## Example 6: Custom Network Configuration

For organizations with specific network requirements:

### Inventory Customization
```yaml
samba4_addc:
  # Network configuration
  ip_address: "10.100.50.10"
  netmask: "255.255.255.0"
  gateway: "10.100.50.1"
  
  # Multiple DNS forwarders for different purposes
  dns_forwarders:
    - "10.100.1.1"      # Internal DNS
    - "10.100.1.2"      # Backup internal
    - "8.8.8.8"         # Public fallback
  
  # Reverse DNS zone for the subnet
  reverse_dns_zone: "50.100.10.in-addr.arpa"
  
  # Custom paths
  samba_paths:
    samba_prefix: "/usr/local/samba"
    config_file: "/etc/samba/smb.conf"
    krb5_config: "/etc/krb5.conf"
    private_dir: "/var/lib/samba/private"
```

## Deployment Commands

### Deploy Example 1 (Default)
```bash
# Start 1Password session
eval $(./scripts/op-session.sh 2h prod)

# Provision VM
terraform apply -var-file=../configs.private/envprod/ring0.tfvars

# Configure with Ansible
ansible-playbook \
  -i configs/envbase/ -i configs.private/envprod/inventory/ \
  playbooks/ring0/identity-samba4-addc-setup.yaml
```

### Deploy Example 2 (Production)
```bash
# Start 1Password session
eval $(./scripts/op-session.sh 2h prod)

# Deploy
ansible-playbook \
  -i configs/envbase/ -i configs.private/envprod/inventory/ \
  playbooks/ring0/identity-samba4-addc-setup.yaml
```

## Configuration Best Practices

### DNS Domain Selection
- Use a subdomain: `ad.example.com` instead of `example.com`
- Avoid `.local` (reserved by Avahi)
- Must be lowercase with dots if multiple labels

### Realm and Domain Names
- Realm: Uppercase version of DNS domain
- Domain (NetBIOS): First label of DNS domain, max 15 chars, no dots
- Example: `dc.example.com` → Realm: `DC.EXAMPLE.COM`, Domain: `DC`

### IP Address Planning
- Reserve static IPs for all DCs outside DHCP pool
- Document MAC-to-IP mappings
- Plan for additional DCs (different IPs needed)

### NTP Configuration
- Critical for Kerberos authentication
- Use reliable external servers
- Verify time sync before domain joins

### Firewall Rules
- Restrict AD traffic to authorized networks
- Allow necessary ports (53, 88, 389, 445, etc.)
- Consider using VLANs for AD traffic

### Backup Strategy
- Regular backups of `/var/lib/samba/private/`
- Store off-site
- Test restore procedures regularly
- Keep Terraform state and inventory backups

## Scaling Considerations

### Single DC (Current Setup)
- Adequate for small labs and dev environments
- Single point of failure
- No load distribution

### Multiple DCs
- Recommended for production
- High availability
- Distributed authentication load
- See Samba wiki for DC replication setup

### Planning Additional DCs
```bash
# Join additional DC to existing forest
samba-tool domain join dc2.yourlab.local dc \
  -U YOURLAB.LOCAL\\administrator \
  --dns-backend=SAMBA_INTERNAL
```

## Monitoring and Alerting

### Key Metrics
- Samba service availability
- NTP synchronization status
- DNS response times
- Replication status (for multi-DC)
- Database size growth

### Sample Monitoring Script
```bash
#!/bin/bash
# Check AD DC health

echo "=== Samba Service ==="
systemctl status samba || echo "ALERT: Samba not running"

echo "=== NTP Status ==="
ntpstat || echo "ALERT: NTP not synchronized"

echo "=== DNS Records ==="
host -t SRV _ldap._tcp.yourlab.local. || echo "ALERT: DNS not resolving"

echo "=== LDAP Connectivity ==="
ldapsearch -H ldap://localhost -x -b "" -s base 2>/dev/null || echo "ALERT: LDAP not responding"

echo "=== Time Check ==="
date
```

## Troubleshooting by Scenario

### New Installation Issues
1. Verify network connectivity: `ping 10.0.0.1`
2. Check Samba package installation: `which samba-tool`
3. Verify provisioning completed: `ls /var/lib/samba/private/sam.ldb`
4. Review ansible output for errors

### DNS Issues
1. Verify Samba is listening on port 53: `netstat -tlnp | grep :53`
2. Test direct query: `dig @10.0.0.10 dc1.yourlab.local.`
3. Check DNS forwarders in smb.conf: `grep "dns forwarder" /etc/samba/smb.conf`
4. Review Samba logs: `journalctl -u samba | grep -i dns`

### Authentication Issues
1. Verify Kerberos config: `cat /etc/krb5.conf`
2. Test KDC: `kinit -v administrator@YOURLAB.LOCAL`
3. Check NTP: `ntpstat`
4. Verify LDAP: `ldapsearch -H ldap://localhost -x`

## References

- [Samba AD DC Setup Guide](https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller)
- [Active Directory Naming FAQ](https://wiki.samba.org/index.php/Active_Directory_Naming_FAQ)
- [Joining a Samba DC](https://wiki.samba.org/index.php/Joining_a_Samba_DC_to_an_Existing_Active_Directory)

## Single Playbook Approach

This implementation uses a single playbook (`identity-samba4-addc-setup.yaml`) rather than separate roles. This approach:
- Simplifies deployment and maintenance
- Makes the entire setup process transparent and easy to modify
- Eliminates unnecessary abstraction layers for a single-use automation
- Is easier to understand and debug for team members

If you need to re-run specific setup phases, you can:
1. Directly edit and run portions of the playbook
2. SSH to the host and manually run commands
3. Create additional playbooks as needed for future enhancements
