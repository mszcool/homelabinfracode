#!/bin/bash
# Validate Ansible directory-based inventories (base/ + environments/<env>/)
# Runs ansible-inventory --list using the 2-directory pattern and checks for errors.
#
# Usage:
#   ./scripts/validate-inventory.sh [production|test]
#   ./scripts/validate-inventory.sh          # validates both environments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BASE_DIR="configs/envbase"
# Environment directories (production is in configs.private, test in configs)
declare -A ENV_DIRS=(
  [production]="configs.private/envprod/inventory"
  [test]="configs/envtest/inventory"
)

# Expected groups that should appear in a valid inventory
EXPECTED_GROUPS=(
  "incus"
  "incus_scope"
  "identityprovider"
  "truenas"
  "mainrouter"
  "edge_devices"
)

PASSED=0
FAILED=0
ERRORS=""

validate_environment() {
  local env="$1"
  echo ""
  echo "=== Validating ${env} environment (directory-based) ==="
  echo ""

  local base_path="${BASE_DIR}/"
  local env_path="${ENV_DIRS[$env]}/"

  # Check directories exist
  for d in "$base_path" "$env_path"; do
    if [[ ! -d "$d" ]]; then
      echo "  FAIL: missing directory: $d"
      FAILED=$((FAILED + 1))
      ERRORS="${ERRORS}\n  [${env}] Missing directory: $d"
      return
    fi
  done

  # Check required files exist
  local required_files=(
    "${base_path}hosts.yaml"
    "${env_path}hosts.yaml"
  )
  for f in "${required_files[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "  FAIL: missing file: $f"
      FAILED=$((FAILED + 1))
      ERRORS="${ERRORS}\n  [${env}] Missing: $f"
      return
    fi
  done

  # Check group_vars directories exist
  for d in "${base_path}group_vars/all" "${env_path}group_vars/all"; do
    if [[ ! -d "$d" ]]; then
      echo "  FAIL: missing directory: $d"
      FAILED=$((FAILED + 1))
      ERRORS="${ERRORS}\n  [${env}] Missing directory: $d"
      return
    fi
  done

  # Check group-specific group_vars directories exist
  local group_dirs=("incus_scope" "mainrouter" "identityprovider" "truenas" "edge_devices")
  for gd in "${group_dirs[@]}"; do
    if [[ ! -d "${base_path}group_vars/${gd}" ]]; then
      echo "  FAIL: missing base group_vars/${gd}/"
      FAILED=$((FAILED + 1))
      ERRORS="${ERRORS}\n  [${env}] Missing base group_vars/${gd}/"
    fi
  done

  # Run ansible-inventory with directory-based pattern
  local output_file
  output_file=$(mktemp)
  trap "rm -f '$output_file'" RETURN

  if ansible-inventory \
    -i "$base_path" \
    -i "$env_path" \
    --list > "$output_file" 2>/dev/null; then

    # Check that output contains expected structure
    if grep -q '"all"' "$output_file"; then
      echo "  OK:   inventory loads successfully"
      PASSED=$((PASSED + 1))
    else
      echo "  FAIL: no 'all' group in output"
      FAILED=$((FAILED + 1))
      ERRORS="${ERRORS}\n  [${env}] No 'all' group in inventory output"
      return
    fi

    # Check expected groups are present
    for group in "${EXPECTED_GROUPS[@]}"; do
      if grep -q "\"${group}\"" "$output_file"; then
        echo "  OK:   group '${group}' found"
        PASSED=$((PASSED + 1))
      else
        echo "  FAIL: group '${group}' not found"
        FAILED=$((FAILED + 1))
        ERRORS="${ERRORS}\n  [${env}] Missing group: ${group}"
      fi
    done

    # Check that hosts are present (at least some expected hosts)
    local host_count
    host_count=$(python3 -c "
import sys, json
data = json.load(sys.stdin)
hosts = set()
for group, details in data.items():
    if isinstance(details, dict) and 'hosts' in details:
        hosts.update(details['hosts'])
print(len(hosts))
" < "$output_file" 2>/dev/null || echo "0")

    if [[ "$host_count" -gt 0 ]]; then
      echo "  OK:   ${host_count} hosts found"
      PASSED=$((PASSED + 1))
    else
      echo "  FAIL: no hosts found in inventory"
      FAILED=$((FAILED + 1))
      ERRORS="${ERRORS}\n  [${env}] No hosts found"
    fi

    # Verify key variables are resolvable (spot-check localdomain)
    local var_output
    if var_output=$(ansible-inventory \
      -i "$base_path" \
      -i "$env_path" \
      --host localhost 2>&1); then
      if echo "$var_output" | grep -q '"localdomain"'; then
        echo "  OK:   localhost sees group_vars/all variables"
        PASSED=$((PASSED + 1))
      else
        echo "  WARN: localhost may not see group_vars/all variables"
      fi
      # localhost should also see incus_scope variables (ISO build playbooks need them)
      if echo "$var_output" | grep -q '"incus_root_user"'; then
        echo "  OK:   localhost sees group_vars/incus_scope variables"
        PASSED=$((PASSED + 1))
      else
        echo "  FAIL: localhost missing group_vars/incus_scope variables"
        FAILED=$((FAILED + 1))
        ERRORS="${ERRORS}\n  [${env}] localhost missing incus_scope variables"
      fi
    fi

    # Verify group-specific vars load for hosts in those groups
    # mainrouter host should have networking vars
    local router_host
    router_host=$(python3 -c "
import sys, json
data = json.load(sys.stdin)
mr = data.get('mainrouter', {}).get('hosts', [])
print(mr[0] if mr else '')
" < "$output_file" 2>/dev/null || echo "")
    if [[ -n "$router_host" ]]; then
      local router_vars
      if router_vars=$(ansible-inventory -i "$base_path" -i "$env_path" --host "$router_host" 2>&1); then
        if echo "$router_vars" | grep -q '"router_lan_ip"'; then
          echo "  OK:   mainrouter host gets networking vars"
          PASSED=$((PASSED + 1))
        else
          echo "  FAIL: mainrouter host missing networking vars"
          FAILED=$((FAILED + 1))
          ERRORS="${ERRORS}\n  [${env}] mainrouter host missing networking vars"
        fi
      fi
    fi

    # truenas host should have storage vars
    local truenas_host
    truenas_host=$(python3 -c "
import sys, json
data = json.load(sys.stdin)
tr = data.get('truenas', {}).get('hosts', [])
print(tr[0] if tr else '')
" < "$output_file" 2>/dev/null || echo "")
    if [[ -n "$truenas_host" ]]; then
      local truenas_vars
      if truenas_vars=$(ansible-inventory -i "$base_path" -i "$env_path" --host "$truenas_host" 2>&1); then
        if echo "$truenas_vars" | grep -q '"truenas_hostname"'; then
          echo "  OK:   truenas host gets storage vars"
          PASSED=$((PASSED + 1))
        else
          echo "  FAIL: truenas host missing storage vars"
          FAILED=$((FAILED + 1))
          ERRORS="${ERRORS}\n  [${env}] truenas host missing storage vars"
        fi
      fi
    fi

    # ip_plan: verify centralized IP plan resolves correctly on mainrouter host
    if [[ -n "$router_host" ]]; then
      local ip_plan_ok=true
      local router_vars_clean
      router_vars_clean=$(ansible-inventory -i "$base_path" -i "$env_path" --host "$router_host" 2>/dev/null)
      # Check ip_plan structure
      if echo "$router_vars_clean" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ip_plan = data.get('ip_plan', {})
assert ip_plan.get('hosts', {}).get('router'), 'missing ip_plan.hosts.router'
assert ip_plan.get('hosts', {}).get('samba4_addc'), 'missing ip_plan.hosts.samba4_addc'
assert ip_plan.get('hosts', {}).get('truenas'), 'missing ip_plan.hosts.truenas'
assert ip_plan.get('hosts', {}).get('pool_remote_access'), 'missing ip_plan.hosts.pool_remote_access'
assert ip_plan.get('hosts', {}).get('edge_garage'), 'missing ip_plan.hosts.edge_garage'
assert ip_plan.get('hosts', {}).get('edge_pool'), 'missing ip_plan.hosts.edge_pool'
assert ip_plan.get('lan_subnet'), 'missing ip_plan.lan_subnet'
assert ip_plan.get('external_dns_servers'), 'missing ip_plan.external_dns_servers'
assert ip_plan.get('dhcp_pool', {}).get('from'), 'missing ip_plan.dhcp_pool.from'
assert ip_plan.get('dhcp_pool', {}).get('to'), 'missing ip_plan.dhcp_pool.to'
assert ip_plan.get('ranges', {}).get('core_infrastructure', {}).get('from'), 'missing ip_plan.ranges.core_infrastructure.from'
assert ip_plan.get('ranges', {}).get('foundational_services', {}).get('from'), 'missing ip_plan.ranges.foundational_services.from'
" 2>/dev/null; then
        echo "  OK:   ip_plan structure resolves correctly"
        PASSED=$((PASSED + 1))
      else
        echo "  FAIL: ip_plan structure incomplete or missing"
        FAILED=$((FAILED + 1))
        ERRORS="${ERRORS}\n  [${env}] ip_plan structure incomplete or missing"
        ip_plan_ok=false
      fi

      # Check backward-compat aliases reference the correct ip_plan paths
      # (ansible-inventory doesn't resolve nested Jinja2; templates resolve at runtime)
      if $ip_plan_ok; then
        if echo "$router_vars_clean" | python3 -c "
import sys, json
data = json.load(sys.stdin)
# Aliases should be Jinja2 refs to ip_plan (unresolved in inventory dump)
rgw = data.get('routerAndPrimaryGatewayIp', '')
assert 'ip_plan.hosts.router' in rgw or rgw == data.get('ip_plan',{}).get('hosts',{}).get('router',''), \
    f\"routerAndPrimaryGatewayIp not referencing ip_plan: {rgw}\"
saip = data.get('samba4_addc_ip', '')
assert 'ip_plan.hosts.samba4_addc' in saip or saip == data.get('ip_plan',{}).get('hosts',{}).get('samba4_addc',''), \
    f\"samba4_addc_ip not referencing ip_plan: {saip}\"
edns = data.get('external_dns_servers', '')
if isinstance(edns, str):
    assert 'ip_plan.external_dns_servers' in edns, \
        f\"external_dns_servers not referencing ip_plan: {edns}\"
else:
    # Already resolved (list) — matches ip_plan directly
    assert edns == data.get('ip_plan',{}).get('external_dns_servers',[]), \
        f\"external_dns_servers mismatch\"
" 2>/dev/null; then
          echo "  OK:   backward-compat aliases match ip_plan values"
          PASSED=$((PASSED + 1))
        else
          echo "  FAIL: backward-compat aliases don't match ip_plan values"
          FAILED=$((FAILED + 1))
          ERRORS="${ERRORS}\n  [${env}] backward-compat aliases mismatch"
        fi
      fi
    fi

  else
    echo "  FAIL: ansible-inventory returned error"
    FAILED=$((FAILED + 1))
    ERRORS="${ERRORS}\n  [${env}] ansible-inventory error"
  fi
}

# Main
cd "$PROJECT_ROOT"

ENVS=("production" "test")
if [[ $# -gt 0 ]]; then
  ENVS=("$1")
fi

for env in "${ENVS[@]}"; do
  validate_environment "$env"
done

echo ""
echo "==============================="
echo "Results: ${PASSED} passed, ${FAILED} failed"
echo "==============================="

if [[ $FAILED -gt 0 ]]; then
  echo -e "\nFailed validations:${ERRORS}"
  exit 1
else
  echo "All directory-based inventories validated successfully."
  exit 0
fi
