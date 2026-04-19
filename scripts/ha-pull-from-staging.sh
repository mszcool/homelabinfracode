#!/usr/bin/env bash
#
# ha-pull-from-staging.sh
#
# Pulls UI-managed Home Assistant config files from a staging instance back
# into the repo so they can be reviewed, committed, and deployed to prod.
#
# This closes the loop on the staging->repo->prod workflow:
#
#   1. Configure HA on staging via the UI (areas, floors, dashboards, energy,
#      MQTT subentries, lovelace, etc.).
#   2. Run this script to copy the relevant files into the env overlay.
#   3. Diff with `git diff`, review, commit, push.
#   4. Run the Ansible playbook against prod -- the JSON-diff logic will
#      detect the changes and apply them inside a stop window.
#
# Files this script pulls (and where they land in the env overlay):
#
#   ha_configs/           (YAML config -- !included from configuration.yaml)
#     mqtt.yaml                  (generated from MQTT subentries on remote
#                                 via scripts/ha-mqtt-subentries-to-yaml.py)
#
#   ha_configs_storage/   (general .storage registries / settings)
#     core.area_registry.json
#     core.floor_registry.json
#     core.label_registry.json   (if present)
#     energy.json
#
#   ha_dashboards/        (everything Lovelace-related)
#     lovelace_dashboards.json   (the dashboard index)
#     lovelace.<id>.json         (one per per-dashboard storage file)
#
# What it does NOT pull (intentionally):
#   * configuration.yaml and other YAML configs (you edit those by hand)
#   * .storage/auth*  (user accounts / tokens are environment-specific)
#   * .storage/hacs.* (HACS files are managed by HACS itself in prod)
#   * .storage/core.entity_registry  /  core.device_registry
#       (these are MASSIVE and largely environment-specific; treat as
#       prod-owned. If you need to seed them, copy by hand explicitly.)
#
# Usage:
#   scripts/ha-pull-from-staging.sh <ssh-target> <env-name> [--dry-run]
#
# Examples:
#   scripts/ha-pull-from-staging.sh root@homeassistant-staging envprod
#   scripts/ha-pull-from-staging.sh -i ~/.ssh/ha root@10.0.0.50 envprod --dry-run
#
# Requirements on the staging side: the SSH/community add-on with key auth.
# The remote .storage path is auto-detected (/homeassistant or /config).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ha-pull-from-staging.sh [<ssh opts...>] <ssh-target> <env-name> [--dry-run]

  <ssh-target>  scp/ssh-style target (user@host)
  <env-name>    name of the env overlay under configs.private/<env>/inventory/
                e.g. envprod, envlocaldev
  --dry-run     show what would be copied/diffed; do not modify any files

The repo root is auto-detected from the script location.
EOF
  exit 1
}

# --- Parse args ---
DRY_RUN=0
SSH_TARGET=""
ENV_NAME=""
SSH_EXTRA_OPTS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    -i|-p|-o|-l|-F)
      # ssh-style option taking a value
      SSH_EXTRA_OPTS+=("$1" "$2"); shift ;;
    *)
      if [ -z "$SSH_TARGET" ]; then
        SSH_TARGET="$1"
      elif [ -z "$ENV_NAME" ]; then
        ENV_NAME="$1"
      else
        echo "Unexpected argument: $1" >&2; usage
      fi
      ;;
  esac
  shift
done

[ -n "$SSH_TARGET" ] && [ -n "$ENV_NAME" ] || usage

# --- Locate repo + env overlay ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="$REPO_ROOT/configs.private/$ENV_NAME/inventory/home_assistant_files"
CONFIGS_DST="$ENV_DIR/ha_configs"
STORAGE_DST="$ENV_DIR/ha_configs_storage"
DASHBOARDS_DST="$ENV_DIR/ha_dashboards"

if [ ! -d "$ENV_DIR" ]; then
  echo "ERROR: env overlay not found: $ENV_DIR" >&2
  echo "       (expected configs.private/$ENV_NAME/inventory/home_assistant_files/)" >&2
  exit 2
fi

mkdir -p "$CONFIGS_DST" "$STORAGE_DST" "$DASHBOARDS_DST"

# --- Helpers ---
ssh_cmd() {
  ssh "${SSH_EXTRA_OPTS[@]}" "$SSH_TARGET" "$@"
}

scp_cmd() {
  scp -q "${SSH_EXTRA_OPTS[@]}" "$@"
}

# --- Detect remote .storage path ---
echo "[*] Detecting remote .storage path on $SSH_TARGET..."
REMOTE_STORAGE="$(ssh_cmd '
  if   [ -d /homeassistant/.storage ]; then echo /homeassistant/.storage
  elif [ -d /config/.storage ]; then echo /config/.storage
  else echo "" ; fi
')"
if [ -z "$REMOTE_STORAGE" ]; then
  echo "ERROR: could not find .storage on $SSH_TARGET (looked in /homeassistant and /config)" >&2
  exit 3
fi
echo "[*] Remote .storage = $REMOTE_STORAGE"

# --- Files to pull (general .storage -> ha_configs_storage/) ---
# Note: real .storage filenames on HA Core 2026.x:
#   areas  -> core.area_registry
#   floors -> core.floor_registry
#   labels -> core.label_registry
# All Lovelace-related files (lovelace_dashboards + per-dashboard
# lovelace.<id>) are pulled separately into ha_dashboards/ so the playbook's
# existing ha_dashboard_files loop owns them.
STORAGE_FILES=(
  core.area_registry
  core.floor_registry
  core.label_registry
  energy
)

# Plus every per-dashboard file (lovelace.*) and the MQTT extraction
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- Pull known fixed-name files ---
for f in "${STORAGE_FILES[@]}"; do
  if ssh_cmd "test -f '$REMOTE_STORAGE/$f'"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[dry-run] would copy: .storage/$f -> $STORAGE_DST/$f.json"
    else
      echo "[*] copying .storage/$f"
      scp_cmd "$SSH_TARGET:$REMOTE_STORAGE/$f" "$STORAGE_DST/$f.json"
    fi
  else
    echo "[ ] (skip) .storage/$f does not exist on remote"
  fi
done

# --- Pull lovelace_dashboards + per-dashboard lovelace.* files ---
# These all go into ha_dashboards/ to match the playbook's split.
echo "[*] Pulling Lovelace dashboards (-> ha_dashboards/)..."

# The dashboard index (lovelace_dashboards) -- treated as a dashboard file
# so it lives next to the per-dashboard files in ha_dashboards/.
if ssh_cmd "test -f '$REMOTE_STORAGE/lovelace_dashboards'"; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] would copy: .storage/lovelace_dashboards -> $DASHBOARDS_DST/lovelace_dashboards.json"
  else
    echo "[*] copying .storage/lovelace_dashboards"
    scp_cmd "$SSH_TARGET:$REMOTE_STORAGE/lovelace_dashboards" "$DASHBOARDS_DST/lovelace_dashboards.json"
  fi
else
  echo "[ ] (skip) .storage/lovelace_dashboards does not exist on remote"
fi

echo "[*] Listing per-dashboard lovelace.* storage files..."
DASHBOARD_FILES="$(ssh_cmd "ls -1 '$REMOTE_STORAGE'/lovelace.* 2>/dev/null || true")"
if [ -n "$DASHBOARD_FILES" ]; then
  while IFS= read -r remote_f; do
    base="$(basename "$remote_f")"
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[dry-run] would copy: .storage/$base -> $DASHBOARDS_DST/$base.json"
    else
      echo "[*] copying .storage/$base"
      scp_cmd "$SSH_TARGET:$remote_f" "$DASHBOARDS_DST/$base.json"
    fi
  done <<< "$DASHBOARD_FILES"
else
  echo "[ ] (skip) no per-dashboard lovelace.* files on remote"
fi

# --- Pull core.config_entries and convert MQTT subentries to mqtt.yaml ---
# The broker config (top-level mqtt entry in core.config_entries) is owned
# by Ansible and stays in .storage. MQTT entities (switches, sensors, ...)
# that were added via the staging UI live in subentries[]; we extract them
# and convert to YAML so they can live in ha_configs/mqtt.yaml under the
# `mqtt: !include mqtt.yaml` pattern.
echo "[*] Extracting MQTT subentries from core.config_entries -> mqtt.yaml..."
if ssh_cmd "test -f '$REMOTE_STORAGE/core.config_entries'"; then
  scp_cmd "$SSH_TARGET:$REMOTE_STORAGE/core.config_entries" "$TMPDIR/core.config_entries"

  # Step 1: extract just the mqtt entry's subentries[] into a JSON array
  python3 - "$TMPDIR/core.config_entries" "$TMPDIR/mqtt-subentries.json" <<'PY'
import json, sys, pathlib
src, dst = sys.argv[1], sys.argv[2]
data = json.loads(pathlib.Path(src).read_text())
mqtt = next(
    (e for e in data.get("data", {}).get("entries", []) if e.get("domain") == "mqtt"),
    None,
)
subentries = (mqtt or {}).get("subentries", []) or []
pathlib.Path(dst).write_text(json.dumps(subentries, indent=4) + "\n")
print(f"[*] extracted {len(subentries)} MQTT subentries", file=sys.stderr)
PY

  # Step 2: convert subentries -> mqtt.yaml using the shared converter
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] would convert subentries -> $CONFIGS_DST/mqtt.yaml"
    python3 "$SCRIPT_DIR/ha-mqtt-subentries-to-yaml.py" "$TMPDIR/mqtt-subentries.json" - \
      | sed 's/^/[dry-run]   /'
  else
    python3 "$SCRIPT_DIR/ha-mqtt-subentries-to-yaml.py" \
      "$TMPDIR/mqtt-subentries.json" "$CONFIGS_DST/mqtt.yaml"
  fi
else
  echo "[ ] (skip) .storage/core.config_entries does not exist on remote"
fi

# --- Show diff summary ---
echo
echo "============================================================"
echo "Done. Review changes with:"
echo "  cd $REPO_ROOT && git status configs.private/$ENV_NAME/inventory/home_assistant_files/"
echo "  cd $REPO_ROOT && git diff  configs.private/$ENV_NAME/inventory/home_assistant_files/"
echo "============================================================"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "(dry-run mode -- no files were modified)"
fi
