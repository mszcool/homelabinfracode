# Projects Configuration Directory

This directory contains individual project configuration files for Incus projects. Each file defines the preseed configuration for a specific project that was previously hardcoded in the main templates.

## Convention

- Each project is defined in a separate YAML file named `{project_name}.yaml`
- The file contains the project configuration including name, config parameters, and description
- When adding a new project, simply create a new file in this directory following the same structure
- All playbooks, tasks, and templates will automatically discover and use these project definitions

## Structure

Each project file should follow this structure:

```yaml
---
# Project description comment
name: project_name
config:
  features.images: true
  features.networks: false
  features.profiles: true
  features.storage.volumes: true
  limits.disk: "{{ tp_incus_config.project_disk_limits.production }}"
  restricted: true
  restricted.networks.access: phys-br,iso-nat
  restricted.devices.pci: allow
description: Human-readable project description
```

## Current Projects

- `prodlayer0.yaml` - Production Layer 0 project
- `prodlayer1.yaml` - Production Layer 1 project

## Migration

This replaces the previous `production_projects` list configuration approach with a convention-based file structure.