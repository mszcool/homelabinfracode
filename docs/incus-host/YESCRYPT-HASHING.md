# Yescrypt Password Hashing for Ubuntu 24.04

> **Context**: This is a reference document for password hashing on Ubuntu 24.04 VMs provisioned via Terraform on Incus. For the full VM provisioning workflow, see [Ring 0 Setup](../04-ring0-setup.md). For Terraform details, see [Architecture Overview](../02-architecture.md).

## The Issue

Ubuntu 24.04 uses **yescrypt** as the default password hashing algorithm, not SHA-512 (even though SHA-512 is a valid crypt format).

When you try to authenticate with a user account, the system compares:
- **Your entered password** → hashed with **yescrypt** algorithm
- **Against the stored hash** in `/etc/shadow`

If the stored hash was created with SHA-512, the comparison will fail because yescrypt and SHA-512 are different algorithms.

## How to Identify This Issue

Check the PAM configuration on the target system:
```bash
incus exec samba4-addc -- cat /etc/pam.d/common-password | grep pam_unix
```

Look for `yescrypt` in the output. If you see:
```
password [success=1 default=ignore] pam_unix.so obscure yescrypt
```

Then the system expects **yescrypt** hashes. If you see `sha512`, then use SHA-512.

## Correct Hashing Methods for Ubuntu 24.04

### 1. Using mkpasswd (Recommended)
```bash
mkpasswd -m yescrypt
# You'll be prompted to enter password twice
# Output will look like: $y$j9T$QoxxlrhWpPrL.RHUrBXtL.$yxOB1Yw6VIcfnmsVdhNWeclhHz6cIR6RxrMqD.Dozh4
```

### 2. Using Python passlib
```bash
python3 << 'EOF'
from passlib.hash import yescrypt
import getpass
pwd = getpass.getpass("Enter password: ")
print(yescrypt.hash(pwd))
EOF
```

### 3. Using Python crypt module (slower)
```bash
python3 << 'EOF'
import crypt
import getpass
pwd = getpass.getpass("Enter password: ")
print(crypt.crypt(pwd, crypt.METHOD_YESCRYPT))
EOF
```

## Hash Format Reference

| Algorithm | Format Prefix | Example |
|-----------|---------------|---------|
| SHA-512 (old) | `$6$` | `$6$brpMjp/zxiQpJg5q$Dm...` |
| **Yescrypt (new)** | **`$y$`** | **`$y$j9T$Qoxxlrh...$yx...`** |

## Using with Terraform

Once you have a yescrypt hash:

```bash
# Set environment variable
export TF_VAR_root_password='$y$j9T$QoxxlrhWpPrL.RHUrBXtL.$yxOB1Yw6VIcfnmsVdhNWeclhHz6cIR6RxrMqD.Dozh4'

# Deploy
terraform apply --var-file="../configs.private/envprod/ring0.tfvars"
```

## Troubleshooting

### "Password auth doesn't work but SSH key does"
This usually means cloud-init created the user successfully (SSH key worked) but the password hash format is wrong:
```bash
# Check what hash is actually in the system
incus exec samba4-addc -- grep yourdomainadmin /etc/shadow

# If it starts with $6$, you used SHA-512 instead of yescrypt
# If it starts with $y$, the hash is in the right format
```

### "Hash looks right but still doesn't work"
```bash
# Check cloud-init logs
incus exec samba4-addc -- tail -50 /var/log/cloud-init.log | grep -i "user\|passwd"

# Manually test with a yescrypt hash
NEWHASH=$(mkpasswd -m yescrypt)
incus exec samba4-addc -- usermod --password "$NEWHASH" yourdomainadmin

# Try logging in
incus exec samba4-addc -- su - yourdomainadmin
# Enter your password
```

### "Which hash format should I use?"
- **Always use yescrypt** (`$y$`) for Ubuntu 24.04
- Check `/etc/pam.d/common-password` on your target to confirm
- If your organization uses older Ubuntu versions alongside 24.04, check with your sysadmin team about standardizing on one format

## References

- [Yescrypt Algorithm](https://password-hashing.info/argon2id)
- [Debian Login Defs](https://manpages.debian.org/bookworm/login/login.defs.5.en.html)
- [PAM Unix Module](https://manpages.debian.org/bookworm/libpam-modules/pam_unix.so.8.en.html)
- mkpasswd man page: `man mkpasswd`
