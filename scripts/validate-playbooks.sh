#!/bin/bash
# Validate Ansible playbooks with syntax-check and list-hosts dry-run.
# Uses the directory-based inventory pattern (base/ + environments/<env>/).
#
# Usage:
#   ./scripts/validate-playbooks.sh [production|test]
#   ./scripts/validate-playbooks.sh          # validates both environments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BASE_DIR="configs/envbase"
# Environment directories (production is in configs.private, test in configs)
declare -A ENV_DIRS=(
  [production]="configs.private/envprod/inventory"
  [test]="configs/envtest/inventory"
)

# All active playbooks (excludes archive/ and tasks/)
PLAYBOOKS=(
  "playbooks/ring0/host-incus-image-multiiso.yaml"
  "playbooks/ring0/host-incus-image-unified.yaml"
  "playbooks/ring0/identity-samba4-addc-setup.yaml"
  "playbooks/ring0/networking-mikrotik.yaml"
  "playbooks/ring0/networking-pi-edge-bridgewifi.yaml"
  "playbooks/ring0/storage-truenas-scale-fundamental-config.yaml"
  "playbooks/ring0/storage-vm-incus-truenas-find-disk-pci.yaml"
  "playbooks/ring0a/host-incus-import-iso.yaml"
  "playbooks/ring0a/host-incus-update.yaml"
  "playbooks/ring0a/identity-lifecycle.yaml"
  "playbooks/ring0a/networking-mikrotik-continuous-cleanup.yaml"
  "playbooks/ring0a/networking-mikrotik-continuous-configure-all.yaml"
  "playbooks/ring0a/storage-truenas-configure.yaml"
)

PASSED=0
FAILED=0
ERRORS=""

validate_playbook() {
  local env="$1"
  local playbook="$2"
  local base_path="${BASE_DIR}/"
  local env_path="${ENV_DIRS[$env]}/"
  local label
  label=$(basename "$playbook")

  # Syntax check
  local syntax_output
  if ! syntax_output=$(ansible-playbook \
    -i "$base_path" \
    -i "$env_path" \
    "$playbook" \
    --syntax-check 2>&1); then
    printf "  %-60s SYNTAX FAIL\n" "$label"
    FAILED=$((FAILED + 1))
    ERRORS="${ERRORS}\n  [${env}] Syntax fail: ${playbook}"
    ERRORS="${ERRORS}\n    ${syntax_output}"
    return
  fi

  # List hosts
  local hosts_output
  if ! hosts_output=$(ansible-playbook \
    -i "$base_path" \
    -i "$env_path" \
    "$playbook" \
    --list-hosts 2>&1); then
    printf "  %-60s HOSTS FAIL\n" "$label"
    FAILED=$((FAILED + 1))
    ERRORS="${ERRORS}\n  [${env}] List-hosts fail: ${playbook}"
    ERRORS="${ERRORS}\n    ${hosts_output}"
    return
  fi

  # Extract host count from "hosts (N):" line
  local host_count
  host_count=$(echo "$hosts_output" | grep -oP 'hosts \(\K[0-9]+' | head -1 || echo "?")

  printf "  %-60s PASS (%d hosts)\n" "$label" "$host_count"
  PASSED=$((PASSED + 1))
}

validate_environment() {
  local env="$1"
  local base_path="${BASE_DIR}/"
  local env_path="${ENV_DIRS[$env]}/"

  echo ""
  echo "=== ${env} environment ==="
  echo ""

  # Verify inventory directories exist
  if [[ ! -d "$base_path" ]]; then
    echo "  ERROR: missing directory: $base_path"
    FAILED=$((FAILED + ${#PLAYBOOKS[@]}))
    return
  fi
  if [[ ! -d "$env_path" ]]; then
    echo "  ERROR: missing directory: $env_path"
    FAILED=$((FAILED + ${#PLAYBOOKS[@]}))
    return
  fi

  for pb in "${PLAYBOOKS[@]}"; do
    if [[ ! -f "$pb" ]]; then
      printf "  %-60s SKIP (not found)\n" "$(basename "$pb")"
      continue
    fi
    validate_playbook "$env" "$pb"
  done
}

# Main
cd "$PROJECT_ROOT"

ENVS=("production" "test")
if [[ $# -gt 0 ]]; then
  ENVS=("$1")
fi

echo "Ansible Playbook Dry-Run Validation"
echo "===================================="

for env in "${ENVS[@]}"; do
  validate_environment "$env"
done

echo ""
echo "===================================="
echo "Results: ${PASSED} passed, ${FAILED} failed"
echo "===================================="

if [[ $FAILED -gt 0 ]]; then
  echo -e "\nFailed validations:${ERRORS}"
  exit 1
else
  echo "All playbook dry-run validations passed."
  exit 0
fi
