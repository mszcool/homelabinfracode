# Incus Trusted Client Certificates

This directory contains **public certificates only** for Incus client authentication.

## Important Security Notes

- ✅ **SAFE**: Public certificates (.crt files) - OK to commit to Git
- ❌ **NEVER**: Private keys (.key files) - Must stay in password manager

## File Naming Convention

Certificate files should be named: `<client-name>.crt`

Example:
- `workstation-admin-mszcool.crt`
- `ci-pipeline-production.crt`
- `dev-team-alice.crt`

## How to Add a New Certificate

1. Generate certificate on client machine:
   ```bash
   ./scripts/manage-incus-client-certs.sh generate <client-name>
   ```

2. Backup private key to password manager:
   ```bash
   ./scripts/manage-incus-client-certs.sh backup
   ```

3. Extract public certificate:
   ```bash
   ./scripts/manage-incus-client-certs.sh extract
   ```

4. Save public certificate to this directory:
   ```bash
   # Copy the certificate content to:
   configs.private/infra-bootstrap/incus/trusted-client-certs/<client-name>.crt
   ```

5. Add entry to `host-incus-cluster.yaml` inventory:
   ```yaml
   incus_trusted_clients:
     - name: "<client-name>"
       description: "Description of this client"
       certificate_file: "incus/trusted-client-certs/<client-name>.crt"
       restricted: true|false
       projects:
         - "project1"
         - "project2"
   ```

6. Deploy to servers:
   ```bash
   ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
     playbooks/ring0a/host-incus-update.yaml
   ```

## Certificate Files

These are placeholder certificates. Replace with your actual certificates.
