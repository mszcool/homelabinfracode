# MAC Address Convention

> **Context**: For Terraform architecture overview, see [ARCHITECTURE.md](./ARCHITECTURE.md). For tfvars layout, see [TFVARS_ORGANIZATION.md](./TFVARS_ORGANIZATION.md).
>
> **Path conventions**: Production tfvars in `configs.private/envprod/`. Terraform code in `terraform/`.

## Overview

All Incus-managed instances (VMs, LXC containers, and Docker/OCI containers) use a structured MAC address scheme that encodes ring membership directly in the address. This enables visual identification of which ring an instance belongs to by inspecting its MAC on the network.

## Address Format

```
00:16:3e : RR : XX : YY
└──────┘   ││   └──┴──┘
  OUI      ││    Host ID (00:01 – FF:FF)
           ││
           └┘
        Ring octet
```

| Component       | Value                | Description                                   |
|-----------------|----------------------|-----------------------------------------------|
| OUI prefix      | `00:16:3e`           | Xen/LXC locally-administered OUI (standard for Incus) |
| Ring octet (RR) | `11`, `12`, `13`, …  | Identifies the ring / Incus project            |
| Host ID (XX:YY) | `00:01` – `FF:FF`   | Unique per-instance within a ring (65,535 addresses) |

## Ring-to-Prefix Mapping

| Ring  | Incus Project | MAC Prefix          | Range                                       |
|-------|---------------|---------------------|---------------------------------------------|
| ring0 | `prodlayer0`  | `00:16:3e:11:xx:xx` | `00:16:3e:11:00:01` – `00:16:3e:11:FF:FF`  |
| ring1 | `prodlayer1`  | `00:16:3e:12:xx:xx` | `00:16:3e:12:00:01` – `00:16:3e:12:FF:FF`  |
| ring2 | `prodlayer2`  | `00:16:3e:13:xx:xx` | `00:16:3e:13:00:01` – `00:16:3e:13:FF:FF`  |

> **Reserved**: `xx:xx = 00:00` is not used (avoids ambiguity with "empty" values).

## Adding a New Instance

1. Check this table for the last allocated host ID in the target ring.
2. Assign the next sequential value (e.g., if `00:02` is the last, use `00:03`).
3. Add the MAC address in the corresponding `ring*.tfvars` file.
4. Update the allocation table in this document.
5. Run `terraform plan` — the [validation checks](#terraform-validation) will confirm correctness.

## Terraform Validation

Three `check` blocks in [../../terraform/main.tf](../../terraform/main.tf) enforce this convention at plan time **without affecting Terraform state**:

| Check                       | What it validates                                                    |
|-----------------------------|----------------------------------------------------------------------|
| `mac_address_format`        | Every MAC matches `00:16:3e:XX:YY:ZZ` (Xen/LXC OUI)                |
| `mac_address_ring_prefix`   | The 4th octet matches the ring (e.g., `11` for `prodlayer0`)        |
| `mac_address_uniqueness`    | No two instances share the same MAC address                          |

The ring-to-prefix mapping is defined in the `mac_prefix_by_project` variable in [../../terraform/variables.tf](../../terraform/variables.tf) and can be extended for new rings.

### Disabling Prefix Validation

For test environments or projects not in the mapping, prefix validation is automatically skipped (the check passes when `incus_project` has no entry in `mac_prefix_by_project`). You can also override via:

```hcl
mac_prefix_by_project = {}  # Disables prefix validation entirely
```

## Design Rationale

- **Ring isolation is visible on the wire**: Any network trace, DHCP log, or ARP table immediately shows which ring an instance belongs to.
- **No state impact**: Using Terraform `check` blocks means validation runs during `plan` but creates no resources — adding or changing checks never triggers resource recreation.
- **65K addresses per ring**: Two octets of host ID space is far beyond practical need, so sequential allocation is simple and collision-free.
- **Standard OUI**: `00:16:3e` is the well-known Xen/LXC OUI, making these addresses instantly recognizable as virtualized instances.

## See Also

- [TFVARS_ORGANIZATION.md](./TFVARS_ORGANIZATION.md) — How tfvars files are structured
- [ARCHITECTURE.md](./ARCHITECTURE.md) — Terraform architecture diagrams
- [QUICKSTART.md](./QUICKSTART.md) — Get running in 10 minutes
