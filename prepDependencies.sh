#!/bin/bash
#
# Prepare Ansible dependencies for homelabinfracode
#
# This script installs all required Ansible collections and applies
# any necessary fixes for known issues.
#
# Usage:
#   ./prepDependencies.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Preparing Ansible Dependencies${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if ansible-galaxy is available
if ! command -v ansible-galaxy &> /dev/null; then
    echo -e "${RED}ERROR: ansible-galaxy not found. Please install Ansible first.${NC}"
    exit 1
fi

# Install Ansible collections from requirements file
echo -e "${YELLOW}Step 1: Installing Ansible collections...${NC}"
if [[ -f "${SCRIPT_DIR}/ansible-requirements.yaml" ]]; then
    ansible-galaxy collection install -r "${SCRIPT_DIR}/ansible-requirements.yaml" --force
    echo -e "${GREEN}Collections installed successfully.${NC}"
else
    echo -e "${RED}ERROR: ansible-requirements.yaml not found in ${SCRIPT_DIR}${NC}"
    exit 1
fi

echo ""

# Apply fixes for known collection issues
echo -e "${YELLOW}Step 2: Applying collection fixes...${NC}"

# Fix for arensb.truenas v1.14.x
if [[ -f "${SCRIPT_DIR}/scripts/dependency-fix-arensb-1.14.sh" ]]; then
    echo "Applying arensb.truenas fix..."
    bash "${SCRIPT_DIR}/scripts/dependency-fix-arensb-1.14.sh"
else
    echo -e "${YELLOW}WARNING: arensb fix script not found, skipping...${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}  Dependencies prepared successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "You can now run playbooks, for example:"
echo "  ansible-playbook -i configs.private/ring0/truenas-configure-inventory.yaml \\"
echo "                   playbooks/ring0a/truenas-configure.yaml --ask-become"
