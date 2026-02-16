#!/bin/bash
#
# Fix for arensb.truenas collection v1.14.x
#
# The arensb.truenas collection v1.14.4 has a broken action plugin with invalid
# Python syntax (uses "import ..modules.mail" which is not valid Python).
# This script removes the broken action plugin so the module falls back to
# using the module directly, which works correctly.
#
# Issue: plugins/action/filesystem.py has invalid relative import syntax
# Fix: Remove the broken action plugin file
#
# This fix should be applied after installing the collection via ansible-galaxy.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Applying fix for arensb.truenas collection v1.14.x...${NC}"

# Find the collection path
COLLECTION_PATHS=(
    "${HOME}/.ansible/collections/ansible_collections/arensb/truenas"
    "/usr/share/ansible/collections/ansible_collections/arensb/truenas"
    "./collections/ansible_collections/arensb/truenas"
)

COLLECTION_PATH=""
for path in "${COLLECTION_PATHS[@]}"; do
    if [[ -d "$path" ]]; then
        COLLECTION_PATH="$path"
        break
    fi
done

if [[ -z "$COLLECTION_PATH" ]]; then
    echo -e "${RED}ERROR: arensb.truenas collection not found.${NC}"
    echo "Please install it first with: ansible-galaxy collection install arensb.truenas"
    exit 1
fi

echo "Found collection at: ${COLLECTION_PATH}"

# Check collection version
if [[ -f "${COLLECTION_PATH}/MANIFEST.json" ]]; then
    VERSION=$(grep -o '"version": "[^"]*"' "${COLLECTION_PATH}/MANIFEST.json" | cut -d'"' -f4)
    echo "Collection version: ${VERSION}"
fi

# The broken file to remove
BROKEN_FILE="${COLLECTION_PATH}/plugins/action/filesystem.py"

if [[ -f "$BROKEN_FILE" ]]; then
    echo -e "${YELLOW}Removing broken action plugin: ${BROKEN_FILE}${NC}"
    rm -f "$BROKEN_FILE"
    echo -e "${GREEN}Fix applied successfully!${NC}"
else
    echo -e "${GREEN}Broken file not found - fix may already be applied or not needed.${NC}"
fi

# Verify the module file exists (this is what will be used instead)
MODULE_FILE="${COLLECTION_PATH}/plugins/modules/filesystem.py"
if [[ -f "$MODULE_FILE" ]]; then
    echo -e "${GREEN}Module file exists: ${MODULE_FILE}${NC}"
else
    echo -e "${RED}WARNING: Module file not found at ${MODULE_FILE}${NC}"
fi

echo ""
echo -e "${GREEN}arensb.truenas collection fix complete.${NC}"
