# Samba4 Active Directory Domain Controller — Reference

> **Start here**: For the high-level setup workflow, see [Ring 0 Setup — Samba4 AD DC](../04-ring0-setup.md#4-samba4-active-directory-domain-controller-setup). For ongoing identity management (users, groups, OUs), see [Ring 0a — Identity Configuration](../05-ring0a-automated.md#4-continuous-identity-configuration). This directory contains detailed reference material for the Samba4 AD DC subsystem.

## Quick Navigation

### Getting Started
1. [Ring 0 Setup — Samba4 AD DC](../04-ring0-setup.md#4-samba4-active-directory-domain-controller-setup) — Master setup workflow (start here)
2. [SAMBA4-IMPLEMENTATION-SUMMARY.md](./SAMBA4-IMPLEMENTATION-SUMMARY.md) — Overview of the implementation
3. [SAMBA4-DEPLOYMENT-CHECKLIST.md](./SAMBA4-DEPLOYMENT-CHECKLIST.md) — Detailed step-by-step checklist

### Comprehensive Guides
- [README-SAMBA4-ADDC.md](./README-SAMBA4-ADDC.md) — Full deployment and operations guide (architecture, verification, troubleshooting, admin tasks)

### Quick References
- [SAMBA4-ADDC-QUICKREF.md](./SAMBA4-ADDC-QUICKREF.md) — Key commands, configuration values, troubleshooting

### Examples and Scenarios
- [SAMBA4-ADDC-EXAMPLES.md](./SAMBA4-ADDC-EXAMPLES.md) — 6 example configurations (default, production, high-capacity, multi-site, dev/test, custom network)

## File Organization

```
docs/identity-addc/
├── INDEX.md                            (this file — navigation hub)
├── SAMBA4-IMPLEMENTATION-SUMMARY.md    (overview and architecture)
├── SAMBA4-DEPLOYMENT-CHECKLIST.md      (step-by-step deployment guide)
├── README-SAMBA4-ADDC.md               (comprehensive guide)
├── SAMBA4-ADDC-QUICKREF.md             (quick reference)
└── SAMBA4-ADDC-EXAMPLES.md             (example configurations)
```

## Implementation Files

These are the actual files used for deployment:

- **Terraform VM definition**: `configs.private/envprod/ring0.tfvars` (or `configs/envtest/ring0.tfvars` for testing)
- **Ansible inventory**: Directory-based at `configs/envbase/` + `configs.private/envprod/inventory/`
- **Group variables**: `configs/envbase/group_vars/identityprovider/` (Samba4 config and identity definitions)
- **Initial setup playbook** (Ring 0): `playbooks/ring0/identity-samba4-addc-setup.yaml`
- **Lifecycle playbook** (Ring 0a): `playbooks/ring0a/identity-lifecycle.yaml`

## Secrets Management

All sensitive data (admin passwords, DNS forwarders) is managed through **1Password** using the `community.general.onepassword` lookup plugin. Before running playbooks, start a session:

```bash
eval $(./scripts/op-session.sh 2h prod)
```

See [Environment Setup](../03-environment-setup.md) and [Architecture — Secrets Management](../02-architecture.md) for details.

## Next Steps After Initial Deployment

Once the AD DC is running (via Ring 0 setup):

1. **Manage users and groups** via the Ring 0a identity lifecycle playbook — see [Ring 0a — Identity Configuration](../05-ring0a-automated.md#4-continuous-identity-configuration)
2. **Join domain members** (TrueNAS, other services) — configure their DNS to point to the AD DC
3. **Verify DNS and Kerberos** — see [SAMBA4-ADDC-QUICKREF.md](./SAMBA4-ADDC-QUICKREF.md)

## Troubleshooting Quick Links

| Issue | Reference |
|-------|-----------|
| DNS not resolving | [README Troubleshooting](./README-SAMBA4-ADDC.md#troubleshooting) |
| Kerberos authentication fails | [QUICKREF Troubleshooting](./SAMBA4-ADDC-QUICKREF.md#troubleshooting) |
| Playbook fails | [Checklist — Issues and Fixes](./SAMBA4-DEPLOYMENT-CHECKLIST.md#common-issues--quick-fixes) |
| Specific scenario help | [EXAMPLES Troubleshooting](./SAMBA4-ADDC-EXAMPLES.md#troubleshooting-by-scenario) |

## Official Resources

- [Samba Wiki — AD DC Setup](https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller)
- [Samba Tool Reference](https://manpages.ubuntu.com/manpages/focal/man8/samba-tool.8.html)
- [Active Directory Naming FAQ](https://wiki.samba.org/index.php/Active_Directory_Naming_FAQ)
- [Kerberos Configuration](https://web.mit.edu/kerberos/krb5-latest/doc/user/user_config/index.html)
