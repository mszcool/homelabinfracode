#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# op-session.sh — Create a short-lived 1Password service account token for
#                 HomeLab infrastructure work (Terraform + Ansible).
#
# Usage:
#   eval $(./scripts/op-session.sh [duration] [environment])
#
# Arguments:
#   duration     Token TTL (default: 2h). Accepts: 30m, 1h, 2h, 8h, 24h, etc.
#   environment  "prod" or "test" (default: prod)
#
# Prerequisites:
#   - 1Password CLI (op) installed and signed in to your personal account
#   - jq installed
#
# Examples:
#   eval $(./scripts/op-session.sh)           # 2-hour prod session
#   eval $(./scripts/op-session.sh 1h test)   # 1-hour test session
#   eval $(./scripts/op-session.sh 8h prod)   # full work day, prod
#
# After eval, both Terraform and Ansible will use the token automatically:
#   terraform plan --var-file ../configs.private/envprod/ring0.tfvars
#   ansible-playbook -i configs/envbase/ -i configs.private/envprod/inventory/ ...
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DURATION="${1:-2h}"
ENV="${2:-prod}"

# ── Validate prerequisites ──────────────────────────────────────────────────
for cmd in op jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is not installed. Please install it first." >&2
    exit 1
  fi
done

# Clear any existing SA token so op CLI uses the personal session
unset OP_SERVICE_ACCOUNT_TOKEN

# Verify the user has an active personal op session (needed to create SAs)
if ! op whoami &>/dev/null; then
  echo "Error: Not signed in to 1Password CLI. Run 'eval \$(op signin)' first." >&2
  exit 1
fi

# ── Define vault access per environment ──────────────────────────────────────
declare -a VAULT_ARGS=()

if [[ "$ENV" == "prod" ]]; then
  # Infrastructure vault (includes VM passwords and AD user passwords)
  VAULT_ARGS+=("--vault" "HomeLab-Prod:read_items")
elif [[ "$ENV" == "test" ]]; then
  VAULT_ARGS+=("--vault" "HomeLab-Test:read_items")
else
  echo "Error: Unknown environment '$ENV'. Use 'prod' or 'test'." >&2
  exit 1
fi

# ── Create the service account with a unique timestamped name ────────────────
SA_NAME="HomeLab-${ENV}-$(date +%Y%m%d-%H%M%S)"

TOKEN=$(op service-account create "$SA_NAME" \
  --expires-in "$DURATION" \
  "${VAULT_ARGS[@]}" \
  --format json | jq -r '.token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "Error: Failed to create service account token." >&2
  exit 1
fi

# ── Output the export command (consumed by eval) ─────────────────────────────
echo "export OP_SERVICE_ACCOUNT_TOKEN=\"${TOKEN}\""

# Print info to stderr so it's visible but doesn't interfere with eval
echo "# ✓ Created 1Password session '$SA_NAME' (expires in $DURATION)" >&2
echo "#   Environment: $ENV" >&2
echo "#   Vaults: ${VAULT_ARGS[*]}" >&2
echo "#   Token exported as OP_SERVICE_ACCOUNT_TOKEN" >&2
