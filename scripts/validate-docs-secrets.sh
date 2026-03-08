#!/bin/bash
# Scan public documentation for private values that should stay in configs.private.
#
# Extracts concrete IPs, MAC addresses, hostnames, usernames, person names, and
# domain names from configs.private/ at runtime, then greps docs/ and README.md
# for any matches.  Uses fixed-string matching with whole-word boundaries to
# avoid both regex escaping bugs and substring false positives.
#
# SSH public keys are explicitly excluded (safe to be public).
#
# Usage:
#   ./scripts/validate-docs-secrets.sh            # check docs/ and README.md
#   ./scripts/validate-docs-secrets.sh --verbose   # also print extraction stats

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

LEAK_COUNT=0

# Colours (disabled when piped)
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; NC=''
fi

PRIVATE_DIR="configs.private"
if [[ ! -d "$PRIVATE_DIR" ]]; then
  echo "configs.private/ not found — nothing to check against."
  exit 0
fi

# Temp files with restricted permissions (not world-readable)
SECRETS_FILE=$(mktemp)
VALUES_FILE=$(mktemp)       # plain values only (for grep -f)
chmod 600 "$SECRETS_FILE" "$VALUES_FILE"
trap 'rm -f "$SECRETS_FILE" "$VALUES_FILE"' EXIT  # updated below when ALLOWED_TMP is created

# Minimum value length — skip short strings that would cause false positives
MIN_LEN=4

# Allowlist — values to ignore even if they appear (one per line, comments # allowed)
ALLOWLIST_FILE="$PROJECT_ROOT/.docs-secrets-allowlist"

# ── Extraction helpers ──────────────────────────────────────────────────────

# Collect all private config files (yaml, tfvars, json) excluding certs/keys
collect_private_files() {
  find "$PRIVATE_DIR" -type f \( -name '*.yaml' -o -name '*.yml' \
    -o -name '*.tfvars' -o -name '*.json' -o -name '*.txt' \) \
    ! -name '*.crt' ! -name '*.key' ! -name '*.pub' \
    ! -path '*/.git/*' 2>/dev/null
}

# Extract IPv4 addresses (skip 0.0.0.0, 127.x, broadcast)
extract_ips() {
  grep -ohrP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' "$@" 2>/dev/null \
    | grep -vP '^(0\.0\.0\.0|127\.\d+\.\d+\.\d+|255\.\d+\.\d+\.\d+)$' \
    | sort -uV \
    | while read -r ip; do echo -e "IP\t$ip"; done
}

# Extract MAC addresses (XX:XX:XX:XX:XX:XX)
extract_macs() {
  grep -ohrPi '\b[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}\b' "$@" 2>/dev/null \
    | sort -uf \
    | while read -r mac; do echo -e "MAC\t$mac"; done
}

# Extract hostnames and FQDNs containing the private domain
extract_hostnames() {
  local domain
  # Find the local domain — require the key to be 'localdomain' exactly
  domain=$(grep -rPoh '^\s*localdomain:\s*["\x27]?([a-zA-Z0-9._-]+)["\x27]?\s*$' \
    "$PRIVATE_DIR" 2>/dev/null | grep -oP ':\s*["\x27]?\K[a-zA-Z0-9._-]+' \
    | head -1)

  if [[ -n "$domain" ]]; then
    echo -e "DOMAIN\t$domain"
    local upper_domain="${domain^^}"
    echo -e "DOMAIN\t$upper_domain"
    echo -e "DOMAIN\tad.$domain"
    echo -e "DOMAIN\tAD.${upper_domain}"
  fi

  # FQDN-style hostnames containing the domain
  if [[ -n "${domain:-}" ]]; then
    grep -ohrP '\b[a-z][a-z0-9_.-]+\.'"$domain"'\b' \
      "$PRIVATE_DIR" 2>/dev/null | sort -u \
      | while read -r h; do echo -e "HOSTNAME\t$h"; done
  fi

  # Ansible host keys from inventory (indented host definitions)
  if [[ -f "$PRIVATE_DIR/envprod/inventory/hosts.yaml" ]]; then
    grep -Poh '^\s{8}(\w[\w.-]+):$' "$PRIVATE_DIR/envprod/inventory/hosts.yaml" 2>/dev/null \
      | sed 's/://;s/^[[:space:]]*//' | sort -u \
      | while read -r h; do echo -e "HOSTNAME\t$h"; done
  fi
}

# Extract usernames — cast a wide net across known key patterns
extract_usernames() {
  # Match common YAML keys that hold usernames
  grep -rPoh '(?:ansible_user|admin_user|_username|root_user|samba4_admin_user|username|user_name|routeruser|routeradminuser|router_automation_user)\s*:\s*["\x27]?([a-zA-Z0-9_.-]+)["\x27]?' \
    "$PRIVATE_DIR" 2>/dev/null \
    | grep -oP ':\s*["\x27]?\K[a-zA-Z0-9_.-]+' | sort -u \
    | while read -r u; do echo -e "USERNAME\t$u"; done
}

# Extract real person names (full_name, firstname, surname fields)
extract_person_names() {
  grep -rPoh '(?:full_name|firstname|surname|first_name|last_name)\s*:\s*["\x27]?([A-Z][a-zA-Z -]+)["\x27]?' \
    "$PRIVATE_DIR" 2>/dev/null \
    | grep -oP ':\s*["\x27]?\K[A-Z][a-zA-Z -]+' \
    | sed 's/[[:space:]]*$//' | sort -u \
    | while read -r n; do echo -e "PERSON\t$n"; done
}

# Extract WiFi SSIDs
extract_ssids() {
  grep -rPoh '(?:wifi_name|wifi_ssid|ssid|edge_local_wifi_name)\s*:\s*["\x27]?([a-zA-Z0-9_-]+)["\x27]?' \
    "$PRIVATE_DIR" 2>/dev/null \
    | grep -oP ':\s*["\x27]?\K[a-zA-Z0-9_-]+' | sort -u \
    | while read -r s; do echo -e "SSID\t$s"; done
}

# Extract location info (city, state that are non-generic)
extract_locations() {
  grep -rPoh '(?:city|state|locality)\s*:\s*["\x27]?([A-Z][a-zA-Z ]+)["\x27]?' \
    "$PRIVATE_DIR" 2>/dev/null \
    | grep -oP ':\s*["\x27]?\K[A-Z][a-zA-Z ]+' \
    | sed 's/[[:space:]]*$//' | sort -u \
    | while read -r l; do echo -e "LOCATION\t$l"; done
}

# ── Run extraction ──────────────────────────────────────────────────────────

echo "Extracting private values from configs.private/..."
echo ""

mapfile -t PRIV_FILES < <(collect_private_files)

if (( ${#PRIV_FILES[@]} == 0 )); then
  echo "  No config files found in configs.private/ — nothing to check."
  exit 0
fi

extract_ips "${PRIV_FILES[@]}"          >> "$SECRETS_FILE"
extract_macs "${PRIV_FILES[@]}"         >> "$SECRETS_FILE"
extract_hostnames                       >> "$SECRETS_FILE"
extract_usernames                       >> "$SECRETS_FILE"
extract_person_names                    >> "$SECRETS_FILE"
extract_ssids                           >> "$SECRETS_FILE"
extract_locations                       >> "$SECRETS_FILE"

# Deduplicate, remove empty lines, strip values shorter than MIN_LEN
sort -u -o "$SECRETS_FILE" "$SECRETS_FILE"
sed -i '/^$/d' "$SECRETS_FILE"

# Build the plain-values file (for grep -f), filtering short strings and allowed values
ALLOWED_TMP=$(mktemp)
chmod 600 "$ALLOWED_TMP"
trap 'rm -f "$SECRETS_FILE" "$VALUES_FILE" "$ALLOWED_TMP"' EXIT
if [[ -f "$ALLOWLIST_FILE" ]]; then
  # Strip comments and blank lines from allowlist
  grep -v '^\s*#' "$ALLOWLIST_FILE" | grep -v '^\s*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | sort -u > "$ALLOWED_TMP"
  ALLOWED_COUNT=$(wc -l < "$ALLOWED_TMP")
  if $VERBOSE; then
    echo "  Allowlist loaded: $ALLOWED_COUNT entries from .docs-secrets-allowlist"
  fi
else
  ALLOWED_COUNT=0
  if $VERBOSE; then
    echo "  No .docs-secrets-allowlist found — nothing excluded"
  fi
fi

awk -F'\t' -v min="$MIN_LEN" 'length($2) >= min { print $2 }' \
  "$SECRETS_FILE" | sort -u \
  | if [[ -s "$ALLOWED_TMP" ]]; then grep -Fxv -f "$ALLOWED_TMP" || true; else cat; fi \
  > "$VALUES_FILE"

TOTAL_SECRETS=$(wc -l < "$VALUES_FILE")

if $VERBOSE; then
  echo "  Extracted $TOTAL_SECRETS unique private values (>=${MIN_LEN} chars):"
  while IFS=$'\t' read -r cat val; do
    if (( ${#val} >= MIN_LEN )); then
      printf "    %-10s %s\n" "$cat" "$val"
    fi
  done < "$SECRETS_FILE"
  echo ""
fi

echo "  Values extracted: $TOTAL_SECRETS"
echo ""

if (( TOTAL_SECRETS == 0 )); then
  echo "  No private values found to check against."
  exit 0
fi

# ── Scan documentation ──────────────────────────────────────────────────────

echo "Scanning docs/ and README.md for leaked private values..."
echo ""

# Use grep -Fw (fixed strings, whole word) with -f (patterns from file).
# This avoids regex escaping entirely and prevents substring false positives.
HITS=$(grep -rFwn --include='*.md' -f "$VALUES_FILE" docs/ README.md 2>/dev/null || true)

if [[ -n "$HITS" ]]; then
  while IFS= read -r hit_line; do
    local_file="${hit_line%%:*}"
    rest="${hit_line#*:}"
    line_num="${rest%%:*}"
    line_content="${rest#*:}"

    # Identify which private value(s) matched on this line
    matched_vals=""
    while IFS=$'\t' read -r cat val; do
      if (( ${#val} >= MIN_LEN )) && echo "$line_content" | grep -qFw "$val"; then
        matched_vals="${matched_vals:+$matched_vals, }$cat=$val"
      fi
    done < "$SECRETS_FILE"

    echo -e "  ${RED}LEAK${NC}  $local_file:$line_num"
    echo "        Matched: $matched_vals"
    if $VERBOSE; then
      echo "        Line:    $line_content"
    fi
    (( LEAK_COUNT++ )) || true
  done <<< "$HITS"
else
  echo -e "  ${GREEN}No leaks found${NC}"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "  Private values checked: $TOTAL_SECRETS"
echo "  Allowlisted (skipped) : $ALLOWED_COUNT"
echo "  Leaks found           : $LEAK_COUNT"

if (( LEAK_COUNT > 0 )); then
  echo ""
  echo -e "  ${RED}FAILED${NC} — private values found in public docs."
  exit 1
else
  echo ""
  echo -e "  ${GREEN}PASSED${NC}"
  exit 0
fi
