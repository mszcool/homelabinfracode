#!/usr/bin/env python3
"""
ha-mqtt-subentries-to-yaml.py

Converts a `core.config_entries.mqtt-subentries.json` file (the array of
device-typed subentries that HA writes when MQTT entities are added via the
UI) into the equivalent MQTT entity YAML blocks that work under
`mqtt: !include_dir_merge_list msz_mqtt_sensors` in `configuration.yaml`.

Usage:
    ha-mqtt-subentries-to-yaml.py <input.json> <output.yaml>
    cat input.json | ha-mqtt-subentries-to-yaml.py - <output.yaml>

Conversion rules (per subentry of subentry_type=device):
  * subentry.data.device  -> shared device block; all components in this
    subentry share a HA device by reusing the same `identifiers` list.
    We synthesize identifiers from `subentry_id` (stable across UI edits,
    survives renames) so the YAML-defined entities map onto the same HA
    device that the subentry created (or, if the device was UI-only, a
    fresh device whose id is deterministic).
  * subentry.data.components{<uuid>: {platform, ...}}  -> one YAML list
    item per component, keyed by the platform name. The component's UUID
    becomes the entity's `unique_id` so HA preserves entity registry
    customizations across the migration.
  * Drops null-valued keys for cleanliness.
  * Emits deterministic, hand-rolled YAML so output is diff-stable across
    runs (no PyYAML dependency).

Out of scope:
  * Anything other than `subentry_type == "device"` is skipped with a
    warning to stderr.
  * The broker config (top-level mqtt entry in core.config_entries) is
    not touched -- it stays in `.storage` and is managed by the playbook.
"""

import json
import sys
from typing import Any


_INDENT = "  "


def _scalar(value: Any) -> str:
    """Emit a YAML scalar with appropriate quoting."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    s = str(value)
    # Quote if it could be misparsed (booleans, numbers, special chars,
    # leading/trailing whitespace, empty, or contains chars that would
    # need escaping in unquoted form).
    needs_quote = (
        s == ""
        or s != s.strip()
        or s.lower() in {"yes", "no", "true", "false", "on", "off", "null", "~"}
        or any(c in s for c in ":#&*!|>'\"%@`,[]{}")
        or s.startswith("-")
    )
    try:
        # If parseable as int/float, must quote to keep as string
        float(s)
        needs_quote = True
    except ValueError:
        pass
    if needs_quote:
        # Use double quotes; escape backslash and double-quote
        escaped = s.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return s


def _emit(value: Any, indent: int, lines: list[str], inline: bool = False) -> None:
    """Recursively emit YAML for value. `inline=True` means caller has
    already started the line and we should not re-indent the first item."""
    pad = _INDENT * indent
    if isinstance(value, dict):
        # Skip null-valued keys for cleanliness.
        items = [(k, v) for k, v in value.items() if v is not None]
        if not items:
            lines.append(f"{pad}{{}}" if not inline else "{}")
            return
        for i, (k, v) in enumerate(items):
            prefix = "" if (inline and i == 0) else pad
            if isinstance(v, (dict, list)) and v:
                lines.append(f"{prefix}{k}:")
                _emit(v, indent + 1, lines)
            elif isinstance(v, list) and not v:
                lines.append(f"{prefix}{k}: []")
            elif isinstance(v, dict) and not v:
                lines.append(f"{prefix}{k}: {{}}")
            else:
                lines.append(f"{prefix}{k}: {_scalar(v)}")
    elif isinstance(value, list):
        if not value:
            lines.append(f"{pad}[]" if not inline else "[]")
            return
        for item in value:
            if isinstance(item, dict):
                lines.append(f"{pad}-")
                # Emit the dict entries indented one more level.
                # We use the standard approach: the "- " marker on its own
                # line followed by indented keys keeps things diff-stable.
                _emit(item, indent + 1, lines)
            elif isinstance(item, list):
                lines.append(f"{pad}-")
                _emit(item, indent + 1, lines)
            else:
                lines.append(f"{pad}- {_scalar(item)}")
    else:
        lines.append(f"{pad}{_scalar(value)}")


def _build_device_block(subentry: dict) -> dict:
    """Build the per-entity `device` mapping from a subentry's device dict.

    We synthesize a stable `identifiers` value from `subentry_id` so all
    entities under one subentry are grouped onto the same HA device.
    """
    src = (subentry.get("data") or {}).get("device") or {}
    subentry_id = subentry.get("subentry_id") or subentry.get("title") or "mqtt-yaml"
    # Flatten existing identifiers (list of [domain, id] pairs) into
    # ["domain:id", ...] form per HA YAML convention. Always include our
    # synthesized identifier so the device is stable even if the original
    # subentry had no identifiers.
    flat_ids = [f"mqtt:{subentry_id}"]
    for ident in src.get("identifiers") or []:
        if isinstance(ident, (list, tuple)) and len(ident) == 2:
            flat_ids.append(f"{ident[0]}:{ident[1]}")
        elif isinstance(ident, str):
            flat_ids.append(ident)
    # Deduplicate while preserving order.
    seen = set()
    deduped = []
    for i in flat_ids:
        if i not in seen:
            seen.add(i)
            deduped.append(i)

    # Build device block, preserving order: name, identifiers, then misc.
    block: dict = {}
    if src.get("name"):
        block["name"] = src["name"]
    block["identifiers"] = deduped
    for key in (
        "manufacturer",
        "model",
        "model_id",
        "hw_version",
        "sw_version",
        "serial_number",
        "configuration_url",
        "suggested_area",
    ):
        if src.get(key) is not None:
            block[key] = src[key]
    # mqtt_settings / connections are not standard YAML device fields --
    # skip them. The mqtt_settings.qos value, when present, applies to the
    # whole subentry; we propagate it to each component below.
    return block


def _convert_subentry(subentry: dict, warnings: list[str]) -> list[dict]:
    """Returns a list of {domain: { ... entity config ... }} dicts."""
    if subentry.get("subentry_type") not in (None, "device"):
        warnings.append(
            f"skipping subentry_id={subentry.get('subentry_id')!r} "
            f"with subentry_type={subentry.get('subentry_type')!r} "
            f"(only 'device' is supported)"
        )
        return []

    data = subentry.get("data") or {}
    components = data.get("components") or {}
    device_block = _build_device_block(subentry)
    qos = ((data.get("device") or {}).get("mqtt_settings") or {}).get("qos")

    out: list[dict] = []
    # Sort components by their UUID key for deterministic output.
    for comp_uuid in sorted(components.keys()):
        comp = dict(components[comp_uuid])  # shallow copy
        platform = comp.pop("platform", None)
        if not platform:
            warnings.append(
                f"skipping component {comp_uuid!r} in subentry "
                f"{subentry.get('subentry_id')!r}: missing 'platform'"
            )
            continue

        # Build the entity config, preserving a sensible key order:
        # unique_id first, then name, then component-specific keys
        # (sorted), then qos, then device.
        entity: dict = {"unique_id": comp_uuid}
        if comp.get("name"):
            entity["name"] = comp.pop("name")
        # Drop nulls; sort remaining keys for stability.
        rest = {k: v for k, v in comp.items() if v is not None}
        for k in sorted(rest.keys()):
            entity[k] = rest[k]
        if qos is not None and "qos" not in entity:
            entity["qos"] = qos
        entity["device"] = device_block

        out.append({platform: entity})

    return out


def convert(subentries: list, warnings: list[str]) -> str:
    """Convert a list of subentries to a YAML string."""
    lines: list[str] = [
        "# Managed by Ansible (do not hand-edit on prod).",
        "# Generated from .storage/core.config_entries.mqtt-subentries.json",
        "# by scripts/ha-mqtt-subentries-to-yaml.py.",
        "#",
        "# Loaded via `mqtt: !include_dir_merge_list msz_mqtt_sensors` in",
        "# configuration.yaml. The MQTT broker connection itself is still",
        "# managed by Ansible in .storage/core.config_entries -- only",
        "# entities live here.",
        "#",
        "# This file (mqtt-ux.yaml) holds MQTT entities that were added",
        "# through the Home Assistant UI on staging. Hand-curated entity",
        "# files (mqtt_pool_sensors.yaml, mqtt_evcc_sensors.yaml, ...)",
        "# live alongside it in this same directory.",
        "",
    ]
    if not subentries:
        lines.append("[]")
        return "\n".join(lines) + "\n"

    items: list[dict] = []
    for sub in subentries:
        items.extend(_convert_subentry(sub, warnings))

    if not items:
        lines.append("[]")
        return "\n".join(lines) + "\n"

    _emit(items, 0, lines)
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        sys.stderr.write(
            "Usage: ha-mqtt-subentries-to-yaml.py <input.json|-> <output.yaml|->\n"
        )
        return 2
    src, dst = argv[1], argv[2]

    if src == "-":
        raw = sys.stdin.read()
    else:
        with open(src, encoding="utf-8") as f:
            raw = f.read()

    data = json.loads(raw)
    if not isinstance(data, list):
        sys.stderr.write(
            f"ERROR: input must be a JSON array of subentries, got {type(data).__name__}\n"
        )
        return 3

    warnings: list[str] = []
    yaml_text = convert(data, warnings)
    for w in warnings:
        sys.stderr.write(f"WARN: {w}\n")

    if dst == "-":
        sys.stdout.write(yaml_text)
    else:
        with open(dst, "w", encoding="utf-8") as f:
            f.write(yaml_text)
        sys.stderr.write(
            f"OK: converted {len(data)} subentries -> {dst} "
            f"({yaml_text.count(chr(10))} lines)\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
