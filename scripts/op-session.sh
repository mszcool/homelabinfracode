#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# op-session.sh — Create a short-lived 1Password service account token for
#                 HomeLab infrastructure work (Terraform + Ansible).
#
# Usage:
#   eval $(./scripts/op-session.sh [duration] [environment] [access])
#
# Arguments:
#   duration     Token TTL (default: 2h). Accepts: 30m, 1h, 2h, 8h, 24h, etc.
#   environment  "prod" or "test" (default: prod)
#   access       "read" (default) or "write". "write" grants read+write
#                permissions on the vault(s) for the session.
#
# Prerequisites:
#   - 1Password CLI (op) installed and signed in to your personal account
#   - jq installed
#
# Examples:
#   eval $(./scripts/op-session.sh)                  # 2h prod, read-only
#   eval $(./scripts/op-session.sh 1h test)          # 1h test, read-only
#   eval $(./scripts/op-session.sh 8h prod)          # full work day, prod
#   eval $(./scripts/op-session.sh 1h prod write)    # 1h prod, read+write
#
# After eval, both Terraform and Ansible will use the token automatically:
#   terraform plan --var-file ../configs.private/envprod/ring0.tfvars
#   ansible-playbook -i configs/envbase/ -i configs.private/envprod/inventory/ ...
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DURATION="${1:-2h}"
ENV="${2:-prod}"
ACCESS="${3:-read}"

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

# ── Clean up outdated / expired HomeLab service accounts ─────────────────────
# Delete every service account whose name starts with "HomeLab-" and that is
# either already expired or whose TTL has elapsed since creation. This keeps
# the 1Password tenant tidy and avoids hitting the SA quota.
echo "# → Scanning for outdated HomeLab service accounts..." >&2

NOW_EPOCH=$(date -u +%s)

# `op service-account list` returns: id, name, created_at, expires_at, state ...
# Some op CLI versions name the field differently; tolerate both.
SA_JSON=$(op service-account list --format json 2>/dev/null || echo '[]')

# Build a list of "id<TAB>name<TAB>reason" for accounts to delete.
TO_DELETE=$(jq -r --argjson now "$NOW_EPOCH" '
  .[]
  | select(.name | startswith("HomeLab-"))
  | . as $sa
  | (.expires_at // .expiresAt // .expiry // null) as $exp_raw
  | (.state // .status // "") as $state
  | (
      if $exp_raw == null then null
      else ($exp_raw | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)
      end
    ) as $exp_epoch
  | if ($state | ascii_downcase) == "expired" then
      "\(.id)\t\(.name)\texpired (state)"
    elif ($exp_epoch != null and $exp_epoch <= $now) then
      "\(.id)\t\(.name)\texpired at \($exp_raw)"
    else
      empty
    end
' <<<"$SA_JSON" 2>/dev/null || true)

if [[ -n "$TO_DELETE" ]]; then
  while IFS=$'\t' read -r SA_ID SA_OLD_NAME SA_REASON; do
    [[ -z "$SA_ID" ]] && continue
    echo "#   • Deleting '$SA_OLD_NAME' ($SA_REASON)" >&2
    if ! op service-account delete "$SA_ID" >/dev/null 2>&1; then
      echo "#     ! Failed to delete '$SA_OLD_NAME' ($SA_ID) — continuing" >&2
    fi
  done <<<"$TO_DELETE"
else
  echo "#   (no outdated HomeLab service accounts found)" >&2
fi

# ── Resolve permission set based on access mode ──────────────────────────────
case "$ACCESS" in
  read)
    PERMS="read_items"
    ;;
  write)
    # Service accounts only support read_items / write_items on vaults.
    # write_items implies create/update/archive of items in that vault.
    PERMS="read_items,write_items"
    ;;
  *)
    echo "Error: Unknown access mode '$ACCESS'. Use 'read' or 'write'." >&2
    exit 1
    ;;
esac

# ── Define vault access per environment ──────────────────────────────────────
declare -a VAULT_ARGS=()

if [[ "$ENV" == "prod" ]]; then
  # Infrastructure vault (includes VM passwords and AD user passwords)
  VAULT_ARGS+=("--vault" "HomeLab-Prod:${PERMS}")
elif [[ "$ENV" == "test" ]]; then
  VAULT_ARGS+=("--vault" "HomeLab-Test:${PERMS}")
else
  echo "Error: Unknown environment '$ENV'. Use 'prod' or 'test'." >&2
  exit 1
fi

# ── Create the service account with a unique timestamped name ────────────────
SA_NAME="HomeLab-${ENV}-${ACCESS}-$(date +%Y%m%d-%H%M%S)"

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
echo "export TF_VAR_op_service_account_token=\"${TOKEN}\""

# Print info to stderr so it's visible but doesn't interfere with eval
echo "# ✓ Created 1Password session '$SA_NAME' (expires in $DURATION)" >&2
echo "#   Environment: $ENV" >&2
echo "#   Access:      $ACCESS ($PERMS)" >&2
echo "#   Vaults: ${VAULT_ARGS[*]}" >&2
echo "#   Token exported as OP_SERVICE_ACCOUNT_TOKEN" >&2
