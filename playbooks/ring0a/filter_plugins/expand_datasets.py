"""Ansible filter plugin to recursively expand dataset children into a flat dict.

Children inherit all parent properties except: name, description, smb, nfs,
share_type, and children.  Children can optionally override quota_gb and
provide their own description (defaults to empty string).

Usage in a playbook:
  datasets_expanded: "{{ datasets | expand_datasets }}"

Quota validation (use before creating datasets):
  quota_errors: "{{ datasets | validate_dataset_quotas }}"
  Returns a list of error strings. Empty list = all OK.
"""

# Keys that are NOT inherited by children
_EXCLUDE_KEYS = frozenset(["children", "smb", "nfs", "name", "description", "share_type"])


def expand_datasets(datasets):
    """Recursively expand dataset children into a flat dictionary."""
    result = {}

    def _expand(key, ds):
        # Add this dataset to the result (without modification)
        result[key] = ds

        for child in ds.get("children", []):
            child_key = key + "__child__" + child["name"]

            # Start with parent properties, skipping excluded keys
            child_ds = {k: v for k, v in ds.items() if k not in _EXCLUDE_KEYS}

            # Set child-specific name and description
            child_ds["name"] = ds["name"] + "/" + child["name"]
            child_ds["description"] = child.get("description", "")

            # Allow quota_gb override
            if "quota_gb" in child:
                child_ds["quota_gb"] = child["quota_gb"]

            # Carry nested children so the next recursion level can process them
            if "children" in child:
                child_ds["children"] = child["children"]

            # Recurse into this child (handles grandchildren, etc.)
            _expand(child_key, child_ds)

    for key, ds in (datasets or {}).items():
        _expand(key, ds)

    return result


def validate_dataset_quotas(datasets):
    """Recursively validate that the sum of children's explicit quotas
    does not exceed their parent's quota at every level of the tree.

    Only children that explicitly set quota_gb are counted.
    Returns a list of error message strings (empty = valid).
    """
    errors = []

    def _validate(parent_name, parent_quota, children):
        # Sum only children with an explicit quota_gb
        children_with_quota = [
            c for c in children
            if "quota_gb" in c and c["quota_gb"] is not None
        ]
        child_quota_sum = sum(c["quota_gb"] for c in children_with_quota)

        if (
            parent_quota is not None
            and children_with_quota
            and child_quota_sum > parent_quota
        ):
            child_detail = " + ".join(
                f"{c['name']}={c['quota_gb']}GB" for c in children_with_quota
            )
            errors.append(
                f"Dataset '{parent_name}': children quota sum "
                f"({child_quota_sum}GB = {child_detail}) exceeds "
                f"parent quota ({parent_quota}GB)"
            )

        # Recurse into each child that has its own children
        for child in children:
            child_name = parent_name + "/" + child["name"]
            # Child's effective quota: explicit override, else inherited from parent
            child_quota = child.get("quota_gb", parent_quota)
            if "children" in child:
                _validate(child_name, child_quota, child["children"])

    for key, ds in (datasets or {}).items():
        if ds.get("children"):
            _validate(ds.get("name", key), ds.get("quota_gb"), ds["children"])

    return errors


class FilterModule:
    """Ansible filter module."""

    def filters(self):
        return {
            "expand_datasets": expand_datasets,
            "validate_dataset_quotas": validate_dataset_quotas,
        }
