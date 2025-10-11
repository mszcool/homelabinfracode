#!/bin/bash
#
# Incus Client Certificate Management Helper
# 
# This script helps you:
# 1. Generate new client certificates
# 2. Extract public certificates for Git storage
# 3. Configure Incus remotes with proper authentication
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_CERT_DIR="$HOME/.config/incus"

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
    print_header "Extract Public Certificate"
    
    if [ ! -f "$CLIENT_CERT_DIR/client.crt" ]; then
        print_error "No certificate found at $CLIENT_CERT_DIR/client.crt"
        print_warning "Run: $0 generate <client-name> first"
        exit 1
    fi
    
    print_success "Public certificate content:"
    echo "---"
    cat "$CLIENT_CERT_DIR/client.crt"
    echo "---"
    echo
    print_warning "Copy this certificate content to your incus-trusted-clients.yaml file"
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
    
    # Add the remote
    incus remote add "$remote_name" "$server_ip:$server_port" \
        --accept-certificate --protocol simplestreams || true
    
    print_success "Remote added successfully!"
    echo
    print_warning "Make sure the server admin has added your certificate to the trust store:"
    echo "  ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \\"
    echo "    playbooks/ring0a/host-incus-manage-trusted-clients.yaml"
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
  $0 <command> [options]

Commands:
  generate <client-name>              Generate new client certificate pair
  extract                             Extract public certificate for Git storage
  add-remote <name> <ip> [port]       Add Incus remote with authentication
  list-remotes                        List configured remotes
  info                                Show current certificate information
  backup                              Backup certificate for password manager
  help                                Show this help message

Examples:
  # Generate a new certificate
  $0 generate workstation-admin-mszcool

  # Extract public cert to add to incus-trusted-clients.yaml
  $0 extract

  # Add remote server
  $0 add-remote incus-aoostar 10.10.0.20 8443

  # Backup certificate for password manager
  $0 backup

Workflow:
  1. Generate certificate: $0 generate <client-name>
  2. Backup to password manager: $0 backup
  3. Extract public cert: $0 extract
  4. Add public cert to configs.private/infra-bootstrap/incus-trusted-clients.yaml
  5. Run Ansible playbook to deploy to servers
  6. Add remote: $0 add-remote <name> <ip> [port]

EOF
}

# Main script logic
case "${1:-help}" in
    generate)
        generate_client_certificate "$2"
        ;;
    extract)
        extract_public_certificate
        ;;
    add-remote)
        add_incus_remote "$2" "$3" "${4:-8443}"
        ;;
    list-remotes)
        list_remotes
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
