#!/bin/bash

# Incus VM Management Script
# This script provides easy commands for managing the Incus-based VMs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INCUS_DIR="${SCRIPT_DIR}/incus"

print_usage() {
    echo "Usage: $0 {init|plan|apply|destroy|status|clean}"
    echo ""
    echo "Commands:"
    echo "  init     - Initialize Terraform"
    echo "  plan     - Show planned changes"
    echo "  apply    - Apply changes"
    echo "  destroy  - Destroy all resources"
    echo "  status   - Show current state"
    echo "  clean    - Clean Terraform cache"
    echo ""
}

check_incus() {
    if ! command -v incus &> /dev/null; then
        echo "Error: Incus not found. Please install Incus first."
        exit 1
    fi
    
    if ! incus info &> /dev/null; then
        echo "Error: Cannot connect to Incus. Please check your Incus installation."
        exit 1
    fi
}

case "$1" in
    init)
        echo "Initializing Terraform for Incus..."
        cd "$INCUS_DIR"
        terraform init
        ;;
    plan)
        echo "Planning Terraform changes for Incus..."
        cd "$INCUS_DIR"
        terraform plan
        ;;
    apply)
        echo "Applying Terraform changes for Incus..."
        check_incus
        cd "$INCUS_DIR"
        terraform apply
        ;;
    destroy)
        echo "Destroying Incus resources..."
        cd "$INCUS_DIR"
        terraform destroy
        ;;
    status)
        echo "Current Terraform state for Incus:"
        cd "$INCUS_DIR"
        terraform show
        echo ""
        echo "Incus instances:"
        incus list
        ;;
    clean)
        echo "Cleaning Terraform cache..."
        cd "$INCUS_DIR"
        rm -rf .terraform .terraform.lock.hcl terraform.tfstate.backup
        echo "Cache cleaned."
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
