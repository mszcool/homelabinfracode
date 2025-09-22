Inventory: host_configs

Purpose
- Consolidate per-host disk and network configuration into a single `host_configs` list.

Structure
- `host_configs` (list)
  - name: unique name to reference from hosts (string)
  - virtual_disk_config: (mapping)
    - name: string
    - devices_in_scope: list of device mappings {device: "sda"}
    - root_partition: mapping (device, size_MB)
    - volume_group_volumes: mapping of LVM volumes and sizes
  - network_config: (mapping)
    - physical_network_parent: e.g. "eth0"
    - bridged_network_parents: list or string

How hosts reference a host_config
- In the inventory hosts section, set `host_config_name` to the matching `host_configs[].name`.

Example
```
all:
  vars:
    host_configs:
      - name: "msz_single_disk_server"
        virtual_disk_config:
          name: "msz_single_disk_server"
          devices_in_scope:
            - device: "sda"
          root_partition:
            device: "sda"
            size_MB: "20480"
          volume_group_volumes:
            images:
              size_MB: "51200"
            instances:
              all_remaining_space: true
        network_config:
          physical_network_parent: "eth0"
          bridged_network_parents: "eth0"

  children:
    incus:
      hosts:
        10.10.0.2:
          hostname: mszpvetest1
          host_config_name: "msz_single_disk_server"
```

Notes
- Playbooks now look up disk and network settings from `host_configs` using the host's `host_config_name`.
- If a host references a missing `host_config_name`, an early validation task will fail the playbook run with a helpful message.
