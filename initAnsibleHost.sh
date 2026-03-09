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
COLLECTIONS_PATH="${HOME}/.ansible/collections"

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

# Install Ansible and pylibssh via pip
echo -e "${YELLOW}Step 0: Installing Ansible and pylibssh via pip...${NC}"
if ! command -v pip3 &> /dev/null; then
    echo -e "${RED}ERROR: pip3 not found. Please install python3-pip first.${NC}"
    exit 1
fi
pip3 install --quiet ansible ansible-pylibssh netaddr
echo -e "${GREEN}Ansible and pylibssh installed successfully.${NC}"
echo ""

# Check if ansible-galaxy is available
if ! command -v ansible-galaxy &> /dev/null; then
    echo -e "${RED}ERROR: ansible-galaxy not found. Please install Ansible first.${NC}"
    exit 1
fi

# Install Ansible collections from requirements file
echo -e "${YELLOW}Step 1: Installing Ansible collections to ${COLLECTIONS_PATH}...${NC}"
if [[ -f "${SCRIPT_DIR}/ansible-requirements.yaml" ]]; then
    ansible-galaxy collection install -r "${SCRIPT_DIR}/ansible-requirements.yaml" -p "${COLLECTIONS_PATH}"
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

# Verify critical collections are present
echo -e "${YELLOW}Step 3: Verifying installed collections...${NC}"
REQUIRED_COLLECTIONS=(
    "community.routeros"
    "community.general"
    "ansible.netcommon"
    "arensb.truenas"
)
ALL_OK=true
for col in "${REQUIRED_COLLECTIONS[@]}"; do
    COL_PATH="${COLLECTIONS_PATH}/ansible_collections/${col//\.//}"
    if [[ -d "${COL_PATH}" ]]; then
        echo -e "  ${GREEN}✓${NC} ${col}"
    else
        echo -e "  ${RED}✗${NC} ${col} — not found at ${COL_PATH}"
        ALL_OK=false
    fi
done

if [[ "${ALL_OK}" = false ]]; then
    echo ""
    echo -e "${RED}ERROR: Some collections failed to install.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}  Dependencies prepared successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "You can now run playbooks, for example:"
echo "  ansible-playbook -i configs.private/ring0/truenas-configure-inventory.yaml \\"
echo "                   playbooks/ring0a/truenas-configure.yaml --ask-become"
