# Samba 4 Active Directory Domain Controller Documentation

This directory contains comprehensive documentation for deploying and managing a Samba 4 based Active Directory Domain Controller on your homelab infrastructure.

## Quick Navigation

### 🚀 **Getting Started**
Start here if you're new to this setup:
1. [SAMBA4-IMPLEMENTATION-SUMMARY.md](./SAMBA4-IMPLEMENTATION-SUMMARY.md) - Overview of what was implemented (10 min read)
2. [SAMBA4-DEPLOYMENT-CHECKLIST.md](./SAMBA4-DEPLOYMENT-CHECKLIST.md) - Step-by-step deployment guide with checklist

### 📖 **Comprehensive Guides**
Detailed documentation for specific topics:
- [README-SAMBA4-ADDC.md](./README-SAMBA4-ADDC.md) - Full deployment and operations guide
  - Architecture overview
  - Detailed setup instructions
  - Post-deployment verification
  - Troubleshooting guide
  - Administrative tasks

### ⚡ **Quick References**
Fast lookups when you need specific information:
- [SAMBA4-ADDC-QUICKREF.md](./SAMBA4-ADDC-QUICKREF.md) - Handy quick reference with:
  - Deployment checklist
  - Key commands
  - Configuration values
  - Quick troubleshooting

### 📋 **Examples & Scenarios**
Real-world configurations for different use cases:
- [SAMBA4-ADDC-EXAMPLES.md](./SAMBA4-ADDC-EXAMPLES.md) - 6 example configurations:
  1. Default configuration (mszlocal domain)
  2. Production domain setup
  3. High-capacity configuration
  4. Multi-site deployment
  5. Development/test setup
  6. Custom network configuration

## File Organization

```
docs/identity-addc/
├── INDEX.md                            (this file)
├── SAMBA4-IMPLEMENTATION-SUMMARY.md    (overview & architecture)
├── SAMBA4-DEPLOYMENT-CHECKLIST.md      (step-by-step guide)
├── README-SAMBA4-ADDC.md               (comprehensive guide)
├── SAMBA4-ADDC-QUICKREF.md             (quick reference)
└── SAMBA4-ADDC-EXAMPLES.md             (example configurations)
```

## Implementation Files

These files are used for actual deployment:

- **Configuration**: 
  - `configs.private/ring0/ring0.tfvars` - Terraform VM definition
  - `configs.private/ring0/samba4-addc-inventory.yaml` - Ansible inventory

- **Automation**:
  - `playbooks/ring0/samba4-addc-setup.yaml` - Monolithic deployment playbook

## Quick Start

### For First-Time Setup
1. Read [SAMBA4-IMPLEMENTATION-SUMMARY.md](./SAMBA4-IMPLEMENTATION-SUMMARY.md) to understand what will be deployed
2. Follow [SAMBA4-DEPLOYMENT-CHECKLIST.md](./SAMBA4-DEPLOYMENT-CHECKLIST.md) step-by-step
3. Reference [README-SAMBA4-ADDC.md](./README-SAMBA4-ADDC.md) for detailed explanations

### For Troubleshooting
1. Check [SAMBA4-ADDC-QUICKREF.md](./SAMBA4-ADDC-QUICKREF.md#troubleshooting)
2. Review [README-SAMBA4-ADDC.md](./README-SAMBA4-ADDC.md#troubleshooting)
3. Check [SAMBA4-ADDC-EXAMPLES.md](./SAMBA4-ADDC-EXAMPLES.md#troubleshooting-by-scenario)

### For Custom Configuration
1. Review your scenario in [SAMBA4-ADDC-EXAMPLES.md](./SAMBA4-ADDC-EXAMPLES.md)
2. Customize [configs.private/ring0/samba4-addc-inventory.yaml](../../configs.private/ring0/samba4-addc-inventory.yaml)
3. Adjust [configs.private/ring0/ring0.tfvars](../../configs.private/ring0/ring0.tfvars) if needed
4. Run deployment as documented in the checklist

## Key Concepts

### What Gets Deployed
- **VM**: Incus virtual machine running Ubuntu 24.04 LTS
- **Samba 4**: Active Directory Domain Controller
- **DNS**: Internal DNS with forwarders to your Mikrotik router
- **Kerberos**: Authentication system with NTP synchronization
- **LDAP**: Directory service for user/group management

### Key Files in the Setup
- `ring0.tfvars` - Defines the AD DC VM in Terraform
- `samba4-addc-inventory.yaml` - Ansible configuration with domain parameters
- `samba4-addc-setup.yaml` - Main playbook that automates everything

### Important Addresses & Parameters
- **MAC Address**: `00:16:3e:11:00:10` - Used for DHCP reservation
- **IP Address**: `10.0.0.10` (configurable, must match DHCP reservation)
- **Domain**: `mszlocal` (customizable in inventory)
- **Realm**: `MSZLOCAL` (must be uppercase domain)
- **DNS Forwarder**: `10.0.0.1` (your Mikrotik router)

## Environment Variables Required

```bash
export SAMBA4_ADMIN_PASSWORD="YourSecurePassword123!"  # Min 8 chars, uppercase, number, special char
export SAMBA4_DNS_FORWARDER_1="10.0.0.1"               # Your router IP
export SAMBA4_DNS_FORWARDER_2="8.8.8.8"                # Optional: secondary forwarder
```

## Next Steps After Deployment

Once the AD DC is running:

1. **Change Administrator Password**
   ```bash
   samba-tool user setpassword administrator --newpassword='NewPassword123!'
   ```

2. **Create Domain Users**
   ```bash
   samba-tool user create john.smith
   ```

3. **Set Password Policies**
   ```bash
   samba-tool domain passwordsettings set --min-pwd-length=12 --complexity=on
   ```

4. **Join Domain Members**
   - Configure other machines to join the domain
   - Set their DNS to point to the AD DC

5. **Set Up Backups**
   - Backup the AD database regularly
   - Store off-site

## Troubleshooting Quick Links

| Issue | Reference |
|-------|-----------|
| DNS not resolving | [README Troubleshooting](./README-SAMBA4-ADDC.md#troubleshooting) |
| Kerberos authentication fails | [QUICKREF Troubleshooting](./SAMBA4-ADDC-QUICKREF.md#troubleshooting) |
| Playbook fails | [Checklist - Issues & Fixes](./SAMBA4-DEPLOYMENT-CHECKLIST.md#common-issues--quick-fixes) |
| Specific scenario help | [EXAMPLES Troubleshooting](./SAMBA4-ADDC-EXAMPLES.md#troubleshooting-by-scenario) |

## Official Resources

- [Samba Wiki - AD DC Setup](https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller)
- [Samba Tool Reference](https://manpages.ubuntu.com/manpages/focal/man8/samba-tool.8.html)
- [Active Directory Naming FAQ](https://wiki.samba.org/index.php/Active_Directory_Naming_FAQ)
- [Kerberos Configuration](https://web.mit.edu/kerberos/krb5-latest/doc/user/user_config/index.html)

## Document Status

- **Created**: January 2026
- **Implementation**: Complete and ready for deployment
- **Tested**: Follows official Samba documentation
- **Updated**: Documentation consolidated to `docs/identity-addc/`

## Need Help?

1. **Quick answers**: Check [SAMBA4-ADDC-QUICKREF.md](./SAMBA4-ADDC-QUICKREF.md)
2. **Detailed help**: Review [README-SAMBA4-ADDC.md](./README-SAMBA4-ADDC.md)
3. **Step-by-step**: Follow [SAMBA4-DEPLOYMENT-CHECKLIST.md](./SAMBA4-DEPLOYMENT-CHECKLIST.md)
4. **Examples**: Look up your scenario in [SAMBA4-ADDC-EXAMPLES.md](./SAMBA4-ADDC-EXAMPLES.md)
5. **Official**: Check [Samba Wiki](https://wiki.samba.org/)
