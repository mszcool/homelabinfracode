#!/bin/bash
# Validate that all relative Markdown links resolve to existing files.
#
# Usage:
#   ./scripts/validate-docs-links.sh            # check docs/ and README.md
#   ./scripts/validate-docs-links.sh --verbose   # also print each valid link

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

BROKEN_COUNT=0
CHECKED_COUNT=0

# Colours (disabled when piped)
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
else
  RED=''; GREEN=''; NC=''
fi

# Check that a resolved path stays inside the project root.
is_path_safe() {
  local absolute_target
  absolute_target=$(readlink -m "$1" 2>/dev/null || echo "")
  [[ "$absolute_target" == "$PROJECT_ROOT"* ]]
}

check_links_in_file() {
  local mdfile="$1"
  local dir
  dir=$(dirname "$mdfile")

  while IFS= read -r match; do
    local raw="${match#]\(}"
    raw="${raw%)}"
    local target="${raw%%#*}"
    [[ -z "$target" ]] && continue

    local resolved="$dir/$target"
    (( CHECKED_COUNT++ )) || true

    if ! is_path_safe "$resolved"; then
      echo -e "  ${RED}ESCAPE${NC}  $mdfile  →  $target  (resolves outside repo)"
      (( BROKEN_COUNT++ )) || true
    elif [[ ! -f "$resolved" && ! -d "$resolved" ]]; then
      echo -e "  ${RED}BROKEN${NC}  $mdfile  →  $target"
      (( BROKEN_COUNT++ )) || true
    elif $VERBOSE; then
      echo -e "  ${GREEN}OK${NC}      $mdfile  →  $target"
    fi
  done < <(grep -oP '\]\((?!https?://|#|mailto:)[^)]+\)' "$mdfile" 2>/dev/null || true)
  return 0
}

echo "Checking Markdown links..."
echo ""

while IFS= read -r -d '' f; do
  [[ -f "$f" ]] && check_links_in_file "$f"
done < <(find docs/ -name '*.md' -type f -print0 2>/dev/null; printf 'README.md\0')

echo ""
echo "  Checked: $CHECKED_COUNT    Broken: $BROKEN_COUNT"

if (( BROKEN_COUNT > 0 )); then
  echo ""
  echo -e "  ${RED}FAILED${NC}"
  exit 1
else
  echo ""
  echo -e "  ${GREEN}PASSED${NC}"
  exit 0
fi
