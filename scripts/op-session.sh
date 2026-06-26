#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# op-session.sh — Provide a 1Password service account token for HomeLab
#                 infrastructure work (Terraform + Ansible).
#
# Usage:
#   eval $(./scripts/op-session.sh [environment] [access])
#
# Arguments:
#   environment  "prod" or "test" (default: prod)
#   access       "read" (default) or "write". "write" grants read+write
#                permissions on the vault(s) for the session.
#
# Why this design:
#   The `op` CLI (as of 2.x) can only CREATE service accounts. It cannot list,
#   delete, or rotate the token of an existing service account — those actions
#   are web-console only. Minting a fresh service account per session therefore
#   piles up orphaned accounts that can never be cleaned up via script and
#   eventually hits the account's service-account limit (→ 400 Bad Request).
#
#   Instead, this script keeps ONE long-lived service account per
#   (environment, access) combination — at most four total. The token is stored
#   in your Private vault (a service account can never be granted access to the
#   Private vault, so only your personal `op` session can read it back). On each
#   run the script simply reads and exports the stored token. It only creates a
#   new service account when the stored token is missing or has expired.
#
# Prerequisites:
#   - 1Password CLI (op) installed and signed in to your personal account
#   - jq installed
#
# Configuration (environment variable overrides):
#   OP_SA_STORE_VAULT   Vault used to store the tokens (default: Private)
#   OP_SA_LIFETIME      Lifetime for newly created SA tokens (default: 90d)
#   OP_SA_RENEW_BUFFER  Seconds before expiry to proactively rotate (default: 86400)
#
# Examples:
#   eval $(./scripts/op-session.sh)                  # prod, read-only
#   eval $(./scripts/op-session.sh test)             # test, read-only
#   eval $(./scripts/op-session.sh prod write)       # prod, read+write
#
# After eval, both Terraform and Ansible will use the token automatically:
#   terraform plan --var-file ../configs.private/envprod/ring0.tfvars
#   ansible-playbook -i configs/envbase/ -i configs.private/envprod/inventory/ ...
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

STORE_VAULT="${OP_SA_STORE_VAULT:-Private}"
SA_LIFETIME="${OP_SA_LIFETIME:-90d}"
RENEW_BUFFER="${OP_SA_RENEW_BUFFER:-86400}" # rotate if expiring within this many seconds

# ── Backward compatibility: the old signature was [duration] [environment] ──
# If the first argument looks like a duration (e.g. 2h, 30m, 90d), treat it as a
# lifetime override and shift it out so the rest of the arguments line up.
if [[ "${1:-}" =~ ^[0-9]+[smhd]$ ]]; then
  echo "# Note: leading duration argument is deprecated; using '$1' as SA lifetime." >&2
  SA_LIFETIME="$1"
  shift
fi

ENV="${1:-prod}"
ACCESS="${2:-read}"

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
case "$ENV" in
  prod)
    SA_VAULT="HomeLab-Prod"
    ;;
  test)
    SA_VAULT="HomeLab-Test"
    ;;
  *)
    echo "Error: Unknown environment '$ENV'. Use 'prod' or 'test'." >&2
    exit 1
    ;;
esac

# ── Convert a lifetime spec (e.g. 90d, 2h) into an absolute expiry epoch ──────
lifetime_to_epoch() {
  local spec="$1" now num unit
  now=$(date -u +%s)
  num="${spec%[smhd]}"
  unit="${spec##*[0-9]}"
  case "$unit" in
    s) echo $((now + num)) ;;
    m) echo $((now + num * 60)) ;;
    h) echo $((now + num * 3600)) ;;
    d) echo $((now + num * 86400)) ;;
    *) echo $((now + num)) ;;
  esac
}

# Warn if the configured lifetime is short — short lifetimes recreate the
# service account frequently and re-introduce the orphaned-account pile-up.
if (( $(lifetime_to_epoch "$SA_LIFETIME") - $(date -u +%s) < 86400 )); then
  echo "# Warning: SA lifetime '$SA_LIFETIME' is under a day. Each expiry creates a" >&2
  echo "#          new (undeletable) service account. Prefer a long lifetime (e.g. 90d)." >&2
fi

# Title of the item that stores the reusable token for this (env, access) combo.
ITEM_TITLE="HomeLab-SA-${ENV}-${ACCESS}"
TOKEN_REF="op://${STORE_VAULT}/${ITEM_TITLE}/credential"

# ── Try to reuse an existing, still-valid stored token ───────────────────────
EXISTING_TOKEN=""
EXISTING_EXP=""
if op item get "$ITEM_TITLE" --vault "$STORE_VAULT" &>/dev/null; then
  EXISTING_TOKEN=$(op read "$TOKEN_REF" 2>/dev/null || true)
  EXISTING_EXP=$(op item get "$ITEM_TITLE" --vault "$STORE_VAULT" \
    --fields label=expires --format json 2>/dev/null \
    | jq -r 'if type=="array" then (.[0].value // empty) else (.value // empty) end' 2>/dev/null || true)
fi

NOW_EPOCH=$(date -u +%s)
if [[ -n "$EXISTING_TOKEN" && -n "$EXISTING_EXP" ]] \
  && (( EXISTING_EXP - NOW_EPOCH > RENEW_BUFFER )); then
  echo "export OP_SERVICE_ACCOUNT_TOKEN=\"${EXISTING_TOKEN}\""
  echo "export TF_VAR_op_service_account_token=\"${EXISTING_TOKEN}\""
  echo "# ✓ Reusing stored token '$ITEM_TITLE' (valid until $(date -u -d "@${EXISTING_EXP}" '+%Y-%m-%d %H:%M:%SZ'))" >&2
  echo "#   Environment: $ENV   Access: $ACCESS ($PERMS)   Vault: $SA_VAULT" >&2
  exit 0
fi

# ── Otherwise create a fresh service account and store its token ─────────────
echo "# → No valid stored token for '$ITEM_TITLE'; creating a new service account..." >&2

SA_NAME="HomeLab-${ENV}-${ACCESS}-$(date +%Y%m%d-%H%M%S)"

TOKEN=$(op service-account create "$SA_NAME" \
  --expires-in "$SA_LIFETIME" \
  --vault "${SA_VAULT}:${PERMS}" \
  --format json | jq -r '.token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "Error: Failed to create service account token." >&2
  exit 1
fi

EXP_EPOCH=$(lifetime_to_epoch "$SA_LIFETIME")

# Upsert the stored item with the new token, expiry and SA name.
if op item get "$ITEM_TITLE" --vault "$STORE_VAULT" &>/dev/null; then
  op item edit "$ITEM_TITLE" --vault "$STORE_VAULT" \
    "credential[password]=${TOKEN}" \
    "expires[text]=${EXP_EPOCH}" \
    "sa_name[text]=${SA_NAME}" >/dev/null
else
  op item create \
    --category "API Credential" \
    --title "$ITEM_TITLE" \
    --vault "$STORE_VAULT" \
    "credential[password]=${TOKEN}" \
    "expires[text]=${EXP_EPOCH}" \
    "sa_name[text]=${SA_NAME}" >/dev/null
fi

# ── Output the export command (consumed by eval) ─────────────────────────────
echo "export OP_SERVICE_ACCOUNT_TOKEN=\"${TOKEN}\""
echo "export TF_VAR_op_service_account_token=\"${TOKEN}\""

echo "# ✓ Created service account '$SA_NAME' and stored token as '$ITEM_TITLE'." >&2
echo "#   Environment: $ENV   Access: $ACCESS ($PERMS)   Vault: $SA_VAULT" >&2
echo "#   Token valid until $(date -u -d "@${EXP_EPOCH}" '+%Y-%m-%d %H:%M:%SZ') (lifetime $SA_LIFETIME)" >&2
echo "#   Token exported as OP_SERVICE_ACCOUNT_TOKEN" >&2
