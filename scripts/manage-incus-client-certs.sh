#!/bin/bash
#
# Incus Client Certificate Management Helper
# 
# This script helps you:
# 1. Generate new client certificates
# 2. Extract public certificates for Git storage
# 3. Configure Incus remotes with proper authentication
# 4. Self-heal a stale server-certificate pin after the server rotates its cert
#    (e.g. following an IP/hostname change such as the UniFi VLAN re-IP). See the
#    self-heal note in add_incus_remote() and docs/incus-host/incus-client-certificates.md.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----------------------------------------------------------------------------
# Environment conventions
# ----------------------------------------------------------------------------
# Incus client configuration environment. Selects where the client key pair
# (client.crt/client.key) and configured remotes live. Overridable via -e/--env:
#   default  -> $HOME/.config/incus (the incus CLI default)
#   <name>   -> $HOME/incus/<name>  (matches the INCUS_CONF convention)
INCUS_ENV="default"
CLIENT_CERT_DIR="$HOME/.config/incus"

# Environment repo root for storing PUBLIC client certificates consumed by the
# playbooks/ring0a/host-incus-update.yaml playbook (e.g. configs.private/incus or
# configs/incus). Public certs are written under <repo-root>/trusted-client-certs/
# where the playbook looks for them based on the inventory. Set via -r/--repo-root.
REPO_ROOT=""
TRUSTED_CERTS_SUBDIR="trusted-client-certs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

generate_client_certificate() {
    local client_name="$1"
    
    if [ -z "$client_name" ]; then
        print_error "Client name is required"
        exit 1
    fi
    
    print_header "Generating Client Certificate: $client_name"
    
    # Create incus config directory if it doesn't exist
    mkdir -p "$CLIENT_CERT_DIR"
    
    # Check if certificate already exists
    if [ -f "$CLIENT_CERT_DIR/client.crt" ]; then
        print_warning "Certificate already exists at $CLIENT_CERT_DIR/client.crt"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Aborted"
            exit 0
        fi
    fi
    
    # Generate certificate
    print_success "Generating new certificate pair..."
    openssl req -x509 -newkey rsa:4096 -keyout "$CLIENT_CERT_DIR/client.key" \
        -out "$CLIENT_CERT_DIR/client.crt" -days 3650 -nodes \
        -subj "/CN=$client_name/O=Incus Client"
    
    # Set proper permissions
    chmod 600 "$CLIENT_CERT_DIR/client.key"
    chmod 644 "$CLIENT_CERT_DIR/client.crt"
    
    print_success "Certificate generated successfully!"
    echo
    print_warning "IMPORTANT: Store the private key securely in your password manager!"
    echo "  Private key: $CLIENT_CERT_DIR/client.key (KEEP SECRET!)"
    echo "  Public cert: $CLIENT_CERT_DIR/client.crt (add to Git)"
    echo
}

extract_public_certificate() {
    local client_name="$1"

    print_header "Extract Public Certificate"

    if [ ! -f "$CLIENT_CERT_DIR/client.crt" ]; then
        print_error "No certificate found at $CLIENT_CERT_DIR/client.crt"
        print_warning "Run: $0 generate <client-name> first"
        exit 1
    fi

    # When no repo root is given, keep the original behavior (print to stdout so it
    # can be redirected or copied manually).
    if [ -z "$REPO_ROOT" ]; then
        print_success "Public certificate content:"
        echo "---"
        cat "$CLIENT_CERT_DIR/client.crt"
        echo "---"
        echo
        print_warning "No --repo-root given: copy the certificate content into"
        print_warning "  <env-root>/$TRUSTED_CERTS_SUBDIR/<client-name>.crt (e.g. configs.private/incus/...)"
        return 0
    fi

    # Derive the client name from the certificate CN when not supplied explicitly.
    if [ -z "$client_name" ]; then
        client_name="$(openssl x509 -in "$CLIENT_CERT_DIR/client.crt" -noout -subject -nameopt multiline 2>/dev/null \
            | awk -F' = ' '/commonName/ {print $2; exit}')"
    fi

    if [ -z "$client_name" ]; then
        print_error "Could not determine client name (no argument and no CN in certificate)"
        print_warning "Usage: $0 --repo-root <path> extract <client-name>"
        exit 1
    fi

    local dest_dir="$REPO_ROOT/$TRUSTED_CERTS_SUBDIR"
    local dest_file="$dest_dir/$client_name.crt"

    mkdir -p "$dest_dir"
    cp "$CLIENT_CERT_DIR/client.crt" "$dest_file"
    chmod 644 "$dest_file"

    print_success "Public certificate saved for the host-incus-update.yaml playbook:"
    echo "  $dest_file"
    echo
    print_warning "Next steps:"
    echo "  1. Reference it under incus_trusted_clients in the inventory group_vars, e.g.:"
    echo "       certificate_file: \"incus/$TRUSTED_CERTS_SUBDIR/$client_name.crt\""
    echo "  2. Deploy with: ansible-playbook -i <envbase> -i <env> playbooks/ring0a/host-incus-update.yaml"
}

add_incus_remote() {
    local remote_name="$1"
    local server_ip="$2"
    local server_port="${3:-8443}"
    
    if [ -z "$remote_name" ] || [ -z "$server_ip" ]; then
        print_error "Usage: $0 add-remote <remote-name> <server-ip> [port]"
        exit 1
    fi
    
    print_header "Adding Incus Remote: $remote_name"
    
    # Check if certificate exists
    if [ ! -f "$CLIENT_CERT_DIR/client.crt" ] || [ ! -f "$CLIENT_CERT_DIR/client.key" ]; then
        print_error "Client certificate not found"
        print_warning "Run: $0 generate <client-name> first"
        exit 1
    fi
    
    print_success "Adding remote $remote_name at $server_ip:$server_port"

    # Self-heal a stale server-certificate pin (e.g. after a server cert rotation).
    #
    # Incus trusts a TLS remote by PINNING the server's self-signed certificate
    # under $INCUS_CONF/servercerts/<remote>.crt. When the server rotates that
    # cert -- which playbooks/ring0a/host-incus-update.yaml does automatically
    # whenever the node's IP or hostname changes (e.g. after the UniFi VLAN
    # re-IP) -- the pinned copy no longer matches and every request fails with:
    #   tls: failed to verify certificate: x509: certificate signed by unknown
    #   authority (... parent certificate cannot sign this kind of certificate ...)
    #
    # `incus remote add` refuses to modify an existing remote, so a plain re-run
    # would leave the stale pin in place. Remove the remote first so the add below
    # re-pins the server's CURRENT certificate via --accept-certificate.
    if incus remote list --format csv 2>/dev/null | cut -d, -f1 | sed 's/ (current)$//' | grep -qx "$remote_name"; then
        # Incus cannot remove the currently-selected ("current") remote, so the
        # re-pin would fail mid-way. Validate and stop with actionable guidance.
        local current_remote
        current_remote="$(incus remote get-default 2>/dev/null || true)"
        if [ "$current_remote" = "$remote_name" ]; then
            print_error "Remote $remote_name is the current remote and cannot be removed to re-pin its certificate."
            print_warning "Switch to another remote first, then re-run this command:"
            echo "  incus remote switch local   # or any other configured remote"
            echo "  $0 --env $INCUS_ENV add-remote $remote_name $server_ip $server_port"
            exit 1
        fi
        print_warning "Remote $remote_name already exists -- removing it first to re-pin the current server certificate (self-heal after a cert rotation)."
        incus remote remove "$remote_name" 2>/dev/null || true
    fi

    # Add the remote (re-pins the server's current self-signed certificate).
    incus remote add "$remote_name" "https://$server_ip:$server_port" \
        --accept-certificate --auth-type tls

    print_success "Remote added successfully!"
    echo
    print_warning "Make sure the server admin has added your certificate to the trust store:"
    echo "  ansible-playbook -i configs/envbase/ -i <env>/inventory/ \\"
    echo "    playbooks/ring0a/host-incus-update.yaml"
    echo
    
    # Test the connection
    print_success "Testing connection..."
    if incus remote switch "$remote_name" 2>/dev/null; then
        print_success "Successfully connected to $remote_name"
        echo
        echo "Available projects:"
        incus project list || print_warning "Could not list projects - check certificate permissions"
    else
        print_error "Failed to connect to $remote_name"
        print_warning "The certificate might not be trusted yet on the server"
    fi
}

list_remotes() {
    print_header "Configured Incus Remotes"
    incus remote list
}

list_environments() {
    local base="$HOME/incus"

    print_header "Available Incus Environments"
    echo "Base directory: $base"
    echo "Default (incus CLI): $HOME/.config/incus"
    echo

    if [ ! -d "$base" ]; then
        print_warning "No environment directory found at $base"
        print_warning "Create one with: $0 --env <name> generate <client-name>"
        return 0
    fi

    local found=0
    local dir name marker
    for dir in "$base"/*/; do
        [ -d "$dir" ] || continue
        found=1
        name="$(basename "$dir")"
        marker=""
        if [ "${INCUS_CONF:-}" = "${dir%/}" ]; then
            marker=" (active)"
        fi
        if [ -f "${dir}client.crt" ]; then
            echo -e "  ${GREEN}\u25cf${NC} ${name}${marker}"
        else
            echo -e "  ${YELLOW}\u25cb${NC} ${name}${marker}  (no client.crt yet)"
        fi
    done

    if [ "$found" -eq 0 ]; then
        print_warning "No environments found under $base"
    fi
}

activate_environment() {
    local env_name="$1"

    if [ -z "$env_name" ]; then
        print_error "Environment name is required" >&2
        echo "Usage: $0 activate <envname|default>" >&2
        exit 1
    fi

    local env_dir
    if [ "$env_name" = "default" ]; then
        env_dir="$HOME/.config/incus"
    else
        env_dir="$HOME/incus/$env_name"
    fi

    if [ ! -d "$env_dir" ]; then
        print_error "Environment directory not found: $env_dir" >&2
        list_environments >&2
        exit 1
    fi

    # Emit an eval-friendly export on stdout; all guidance goes to stderr so that
    # `eval "$($0 activate <env>)"` only captures the export statement.
    echo "export INCUS_CONF=\"$env_dir\""
    print_success "Incus environment '$env_name' -> $env_dir" >&2
    print_warning "Apply it to your current shell with:" >&2
    echo "  eval \"\$($0 activate $env_name)\"" >&2
}

show_certificate_info() {
    print_header "Current Certificate Information"
    
    if [ ! -f "$CLIENT_CERT_DIR/client.crt" ]; then
        print_error "No certificate found at $CLIENT_CERT_DIR/client.crt"
        exit 1
    fi
    
    echo "Certificate details:"
    openssl x509 -in "$CLIENT_CERT_DIR/client.crt" -text -noout | grep -A 2 "Subject:"
    echo
    echo "Certificate fingerprint:"
    openssl x509 -in "$CLIENT_CERT_DIR/client.crt" -fingerprint -noout
    echo
    
    if [ -f "$CLIENT_CERT_DIR/client.key" ]; then
        print_success "Private key found: $CLIENT_CERT_DIR/client.key"
        print_warning "Remember to back this up in your password manager!"
    else
        print_error "Private key not found at $CLIENT_CERT_DIR/client.key"
    fi
}

backup_certificate_for_password_manager() {
    local backup_dir="$HOME/incus-cert-backup-$(date +%Y%m%d-%H%M%S)"
    
    print_header "Backing up certificate for password manager"
    
    if [ ! -f "$CLIENT_CERT_DIR/client.key" ] || [ ! -f "$CLIENT_CERT_DIR/client.crt" ]; then
        print_error "Certificate files not found"
        exit 1
    fi
    
    mkdir -p "$backup_dir"
    cp "$CLIENT_CERT_DIR/client.key" "$backup_dir/"
    cp "$CLIENT_CERT_DIR/client.crt" "$backup_dir/"
    
    print_success "Certificate backed up to: $backup_dir"
    echo
    print_warning "Store these files securely:"
    echo "  1. Import client.key and client.crt into your password manager"
    echo "  2. Delete the backup directory after importing: rm -rf $backup_dir"
    echo "  3. Never commit client.key to version control!"
}

show_usage() {
    cat << EOF
Incus Client Certificate Management Helper

Usage:
  $0 [global-options] <command> [options]

Global options (may appear before or after the command):
  -e, --env <name>          Select the incus client config directory:
                              default  -> \$HOME/.config/incus (incus CLI default)
                              <name>   -> \$HOME/incus/<name>  (INCUS_CONF convention)
  -r, --repo-root <path>    Environment repo root used to store PUBLIC certs for
                            the host-incus-update.yaml playbook. Certs are written
                            to <path>/$TRUSTED_CERTS_SUBDIR/<client-name>.crt
                            (e.g. configs.private/incus or configs/incus).

Commands:
  generate <client-name>              Generate new client certificate pair
  extract [client-name]               Save/print the public certificate. With
                                      --repo-root it is written to the playbook's
                                      $TRUSTED_CERTS_SUBDIR directory; otherwise
                                      printed to stdout.
  add-remote <name> <ip/dns> [port]   Add Incus remote with authentication.
                                      Self-heals a stale server-cert pin: if the
                                      remote already exists it is removed and
                                      re-added so the CURRENT server certificate
                                      is re-pinned (needed after a cert rotation).
  list-remotes                        List configured remotes
  list-envs                           List incus environments under \$HOME/incus
  activate <envname|default>          Print an eval-able INCUS_CONF export for an
                                      environment (\$HOME/incus/<envname>)
  info                                Show current certificate information
  backup                              Backup certificate for password manager
  help                                Show this help message

Examples:
  # Generate a certificate in the default (\$HOME/.config/incus) config dir
  $0 generate workstation-admin-mszcool

  # Generate a certificate in the ring1 environment (\$HOME/incus/ring1)
  $0 --env ring1 generate workstation-admin-mszcool

  # Save the public cert into the prod repo env for the playbook
  $0 --repo-root configs.private/incus extract workstation-admin-mszcool

  # Save the public cert for the test/base env
  $0 --repo-root configs/incus extract dev-workstation1

  # Add a remote using the ring1 client config
  $0 --env ring1 add-remote incus-aoostar 10.10.0.20 8443

  # List the environments available under \$HOME/incus
  $0 list-envs

  # Activate the ring1 environment in the current shell
  eval "\$($0 activate ring1)"

Workflow:
  1. Generate certificate:        $0 [--env <name>] generate <client-name>
  2. Backup to password manager:  $0 [--env <name>] backup
  3. Store public cert for the playbook:
       $0 [--env <name>] --repo-root <configs[.private]/incus> extract <client-name>
  4. Add cert reference under incus_trusted_clients in the inventory group_vars
  5. Run the playbook: playbooks/ring0a/host-incus-update.yaml
  6. Add remote: $0 [--env <name>] add-remote <name> <ip> [port]

EOF
}

# ----------------------------------------------------------------------------
# Parse global options (may appear anywhere) and collect positional arguments
# ----------------------------------------------------------------------------
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        -e|--env)
            [ -z "${2:-}" ] && { print_error "Option $1 requires a value"; exit 1; }
            INCUS_ENV="$2"
            shift 2
            ;;
        -r|--repo-root)
            [ -z "${2:-}" ] && { print_error "Option $1 requires a value"; exit 1; }
            REPO_ROOT="${2%/}"
            shift 2
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}"

# Resolve the incus client config directory from the environment convention and
# make the incus CLI read/write it (remotes and the client key pair live here).
if [ "$INCUS_ENV" != "default" ]; then
    CLIENT_CERT_DIR="$HOME/incus/$INCUS_ENV"
fi
export INCUS_CONF="$CLIENT_CERT_DIR"

# Main script logic
case "${1:-help}" in
    generate)
        generate_client_certificate "$2"
        ;;
    extract)
        extract_public_certificate "$2"
        ;;
    add-remote)
        add_incus_remote "$2" "$3" "${4:-8443}"
        ;;
    list-remotes)
        list_remotes
        ;;
    list-envs|list)
        list_environments
        ;;
    activate)
        activate_environment "$2"
        ;;
    info)
        show_certificate_info
        ;;
    backup)
        backup_certificate_for_password_manager
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        print_error "Unknown command: $1"
        echo
        show_usage
        exit 1
        ;;
esac
