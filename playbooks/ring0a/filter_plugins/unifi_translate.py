"""Ansible filter plugin: compile the vendor-neutral network-fabric schema
(group_vars/network_fabric/networking-foundation.yaml) into UniFi Network API
request bodies.

These filters perform PURE transformations only. They never need controller-
assigned object IDs (network/zone/site IDs): those are resolved at runtime by the
playbook (GET-then-upsert), which injects them by name. Keeping ID resolution out
of the filters keeps them deterministic and unit-testable.

Filters:
  net_zones      | unifi_network_body(zone)          -> integration API network dict (no id)
  wlan           | unifi_wlan_body(wlan)             -> integration API wlan dict (no ids)
  firewall_policy| unifi_expand_firewall             -> normalized rule list (zones by name)
  member         | unifi_reservation_body(net_name)  -> internal rest/user dict (no id)
  bands          | unifi_frequencies                 -> ["2.4 GHz", ...]
"""

# Map schema band tokens -> UniFi frequency labels.
_BAND_MAP = {
    "2g": "2.4 GHz",
    "2.4g": "2.4 GHz",
    "5g": "5 GHz",
    "6g": "6 GHz",
}

# Map schema security tokens -> UniFi WLAN security values.
_SECURITY_MAP = {
    "wpa2": "WPA2",
    "wpa3": "WPA3",
    "wpa2wpa3": "WPA2/WPA3",
    "open": "open",
}

# Internal rest/wlanconf band tokens (kept as 2g/5g/6g, unlike the integration labels).
_WLAN_BAND_MAP = {
    "2g": "2g",
    "2.4g": "2g",
    "5g": "5g",
    "6g": "6g",
}


def unifi_frequencies(bands):
    """Translate schema band tokens (2g/5g/6g) to UniFi frequency labels."""
    return [_BAND_MAP.get(str(b).lower(), b) for b in (bands or [])]


def unifi_network_body(zone, zone_id=None):
    """Build an integration-API network (VLAN) body from a net_zone dict.

    With Zone-Based Firewall enabled every network must carry a `zoneId`, so the
    playbook creates the firewall zones first and passes the resolved id here.

    Field shapes confirmed against a live UniFi OS console (Network integration
    API v1): L3 lives under `ipv4Configuration` (hostIpAddress + prefixLength) and
    DHCP under `ipv4Configuration.dhcpConfiguration` (ipAddressRange.start/stop).
    """
    dhcp = zone.get("dhcp", {}) or {}
    dhcp_enabled = bool(dhcp.get("enabled", True))
    try:
        prefix_length = int(str(zone["subnet"]).split("/")[1])
    except (KeyError, IndexError, ValueError):
        prefix_length = 24

    ipv4 = {
        # Explicit range provided below, so disable auto-scaling of the pool.
        "autoScaleEnabled": False,
        "hostIpAddress": zone["gateway"],
        "prefixLength": prefix_length,
    }
    if dhcp_enabled:
        ipv4["dhcpConfiguration"] = _prune({
            "mode": "SERVER",
            "ipAddressRange": {
                "start": dhcp.get("pool_from"),
                "stop": dhcp.get("pool_to"),
            },
            "leaseTimeSeconds": int(dhcp.get("lease", 86400)),
            "domainName": zone.get("domain_name"),
            "pingConflictDetectionEnabled": True,
            # Per-zone DNS override field name TBD on this API version — added once
            # confirmed (servers zone needs DC-first DNS).
        })

    body = {
        "name": zone["name"],
        "enabled": True,
        "management": "GATEWAY",
        "zoneId": zone_id,
        "vlanId": int(zone["vlan_id"]),
        "internetAccessEnabled": bool(zone.get("internet", True)),
        "isolationEnabled": bool(zone.get("isolated", False)),
        "mdnsForwardingEnabled": bool(zone.get("mdns", False)),
        "cellularBackupEnabled": bool(zone.get("cellular_backup", False)),
        "ipv4Configuration": ipv4,
    }
    # Drop keys that are None so PUT merges don't clobber controller defaults.
    return _prune(body)


def unifi_wlan_body(wlan, networkconf_id=None, usergroup_id=None, ap_group_ids=None):
    """Build an INTERNAL rest/wlanconf body from a wlan dict.

    WLANs are not exposed by the integration API, so they go through the internal
    rest/wlanconf endpoint. Field shapes confirmed against a live UCG. The playbook
    resolves and injects: networkconf_id (internal network _id), usergroup_id (site
    "Default" user group) and ap_group_ids ([site "All APs" group]).

    WPA3 encoding (wpa3_support/wpa3_transition) is best-effort — verify against a
    WPA3 SSID GET if you use WPA3 in anger.
    """
    security = str(wlan.get("security", "wpa2")).lower()
    is_open = security == "open"
    is_wpa3 = "wpa3" in security
    is_transition = security in ("wpa2wpa3", "wpa3transition")
    bands = [_WLAN_BAND_MAP.get(str(b).lower(), b) for b in (wlan.get("bands", ["2g", "5g"]))]

    body = {
        "name": wlan["ssid"],
        "enabled": bool(wlan.get("enabled", True)),
        "security": "open" if is_open else "wpapsk",
        "wlan_bands": bands,
        "ap_group_mode": "all",
        "hide_ssid": bool(wlan.get("hide_ssid", False)),
        "is_guest": bool(wlan.get("is_guest", False)),
        "l2_isolation": bool(wlan.get("client_isolation", False)),
    }
    if not is_open:
        body["wpa_mode"] = "wpa2"
        body["wpa_enc"] = "ccmp"
        body["wpa3_support"] = bool(is_wpa3)
        body["wpa3_transition"] = bool(is_transition)
        body["x_passphrase"] = wlan.get("passphrase")
    if networkconf_id:
        body["networkconf_id"] = networkconf_id
    if usergroup_id:
        body["usergroup_id"] = usergroup_id
    if ap_group_ids:
        body["ap_group_ids"] = list(ap_group_ids)
    return _prune(body)


def unifi_reservation_body(member, network_id=None):
    """Build an internal rest/user body (fixed-IP reservation + optional DNS).

    `network_id` is the INTERNAL network _id (from rest/networkconf), resolved by
    the playbook.
    """
    sd = member.get("static_dhcp", {}) or {}
    dns_names = member.get("dns_names", []) or []
    body = {
        "mac": (sd.get("mac") or "").lower() or None,
        "name": member.get("alias"),
        "note": member.get("alias"),
        "fixed_ip": sd.get("ip"),
        "use_fixedip": True if sd.get("ip") else False,
        "network_id": network_id,
    }
    if dns_names:
        body["local_dns_record"] = dns_names[0]
        body["local_dns_record_enabled"] = True
    return _prune(body)


def unifi_expand_firewall(firewall_policy):
    """Normalize firewall_policy.rules into a flat, ordered list of rule dicts.

    Zone and network references stay as NAMES; the playbook resolves them to IDs.
    Adds a stable `index` so rule ordering is deterministic on the controller.
    """
    rules = []
    for i, r in enumerate((firewall_policy or {}).get("rules", []) or []):
        rules.append({
            "name": r["name"],
            "index": (i + 1) * 10,
            "action": "ALLOW" if r.get("action", "allow") == "allow" else "BLOCK",
            "src_zones": r.get("from", []) or [],
            "dst_zones": r.get("to", []) or [],
            "src_networks": r.get("from_networks", []) or [],
            "dst_networks": r.get("to_networks", []) or [],
            "src_hosts": r.get("from_hosts", []) or [],
            "dst_hosts": r.get("to_hosts", []) or [],
            "ports": r.get("ports", []) or [],
            "proto": r.get("proto", "all"),
            "paused": bool(r.get("paused", False)),
            "temporary": bool(r.get("temporary", False)),
            "deprecated": bool(r.get("deprecated", False)),
        })
    return rules


def _prune(obj):
    """Recursively drop dict entries whose value is None (keep False/0/empty)."""
    if isinstance(obj, dict):
        return {k: _prune(v) for k, v in obj.items() if v is not None}
    if isinstance(obj, list):
        return [_prune(v) for v in obj]
    return obj


def unifi_policy_body(rule, zone_of=None, zone_ids=None, group_ids=None, net_cidrs=None):
    """Build a zone-based firewall policy body from an expanded rule.

    Shape confirmed against a live UCG (integration firewall/policies): action is
    an object, source/destination carry an optional nested trafficFilter, and
    protocol lives under ipProtocolScope.

    Name resolution:
      zone_of      net_zone role name (iot/kids/...) -> firewall zone name
      zone_ids     firewall zone name               -> controller zone id
      group_ids    address/port group name          -> firewall-group external_id
      net_cidrs    net_zone name                    -> its subnet CIDR (source narrowing)

    A rule with `paused: true` is created disabled (enabled:false) — the UI
    "Pause" toggle — so it can be enabled on demand.

    NOTE: DPI app-category/domain filters are not yet mapped (need a live example);
    the Filtered-zone content block is expressed as a simple paused deny rule.
    """
    zone_of = zone_of or {}
    zone_ids = zone_ids or {}
    group_ids = group_ids or {}
    net_cidrs = net_cidrs or {}

    def zone_id_for(name):
        # 'internet'/'gateway'/'wan' map to the built-in External zone.
        if name in ("internet", "gateway", "wan"):
            return zone_ids.get("External")
        return zone_ids.get(zone_of.get(name, name))

    def ip_items(values):
        # A CIDR value uses item type SUBNET; a bare host IP uses IP_ADDRESS.
        def _item(v):
            return {"type": "SUBNET" if "/" in str(v) else "IP_ADDRESS", "value": v}
        return {
            "type": "IP_ADDRESS",
            "ipAddressFilter": {
                "type": "IP_ADDRESSES",
                "matchOpposite": False,
                "items": [_item(v) for v in values],
            },
        }

    src_zone_ids = [z for z in (zone_id_for(n) for n in rule.get("src_zones", [])) if z]
    dst_zone_ids = [z for z in (zone_id_for(n) for n in rule.get("dst_zones", [])) if z]

    action_type = rule.get("action", "ALLOW")
    action = {"type": action_type}
    # allowReturnTraffic is required for ALLOW but must be false for internet-bound
    # (External zone) allows; omitted entirely for BLOCK/REJECT.
    dst_is_external = any(n in ("internet", "gateway", "wan") for n in rule.get("dst_zones", []))
    if action_type == "ALLOW":
        action["allowReturnTraffic"] = not dst_is_external

    source = {"zoneId": src_zone_ids[0] if src_zone_ids else None}
    # Narrow the source to specific host IPs and/or whole net_zone subnets
    # (from_networks), so a zone-scoped rule can target one network within a
    # shared firewall zone (e.g. kids only, inside the Filtered zone).
    src_values = list(rule.get("src_hosts", []) or []) \
        + [net_cidrs[n] for n in (rule.get("src_networks", []) or []) if n in net_cidrs]
    if src_values:
        source["trafficFilter"] = ip_items(src_values)

    destination = {"zoneId": dst_zone_ids[0] if dst_zone_ids else None}
    # Narrow the destination to specific host IPs and/or whole net_zone subnets
    # (to_networks), e.g. reach only the kids network inside the shared KidsMedia zone.
    dst_values = list(rule.get("dst_hosts", []) or []) \
        + [net_cidrs[n] for n in (rule.get("dst_networks", []) or []) if n in net_cidrs]
    dst_tf = ip_items(dst_values) if dst_values else None
    if rule.get("ports"):
        dst_tf = dst_tf or {"type": "PORT"}
        dst_tf["portFilter"] = {
            "type": "PORTS",
            "matchOpposite": False,
            "items": [{"type": "PORT_NUMBER", "value": int(p)} for p in rule["ports"]],
        }
    if dst_tf:
        destination["trafficFilter"] = dst_tf

    proto = str(rule.get("proto", "all")).lower()
    ip_scope = {"ipVersion": "IPV4_AND_IPV6"}
    if proto in ("tcp", "udp"):
        ip_scope["protocolFilter"] = {
            "type": "NAMED_PROTOCOL",
            "protocol": {"name": proto.upper()},
            "matchOpposite": False,
        }

    body = {
        "name": rule["name"],
        # "Pause" in the UI == enabled:false; there is no separate paused field.
        "enabled": not rule.get("paused", False),
        "action": action,
        "source": _prune(source),
        "destination": _prune(destination),
        "ipProtocolScope": ip_scope,
        "loggingEnabled": False,
    }
    return _prune(body)


def unifi_portforward_body(pf):
    """Build an INTERNAL rest/portforward body (WAN inbound port forward).

    Field names confirmed against the UniFi internal API: pfwd_interface (wan),
    dst_port (external), fwd (internal IP), fwd_port (internal), proto
    (tcp|udp|tcp_udp). `paused: true` creates it disabled.
    """
    body = {
        "name": pf.get("name"),
        "enabled": not pf.get("paused", False),
        "pfwd_interface": "wan",
        "src": "any",
        "dst_port": str(pf.get("wan_port")),
        "fwd": pf.get("to_host"),
        "fwd_port": str(pf.get("to_port")),
        "proto": str(pf.get("proto", "tcp_udp")).lower(),
        "log": False,
    }
    return _prune(body)


class FilterModule:
    """Ansible filter module."""

    def filters(self):
        return {
            "unifi_frequencies": unifi_frequencies,
            "unifi_network_body": unifi_network_body,
            "unifi_wlan_body": unifi_wlan_body,
            "unifi_reservation_body": unifi_reservation_body,
            "unifi_expand_firewall": unifi_expand_firewall,
            "unifi_policy_body": unifi_policy_body,
            "unifi_portforward_body": unifi_portforward_body,
        }
