# Unified ISO Generation for Multiple Server Configurations

## Overview

This directory contains the optimized approach for generating a single Ubuntu ISO image that supports multiple server configurations through a GRUB boot menu selection.

## Key Benefits

1. **Single ISO**: One ISO file instead of multiple server-specific ISOs
2. **Interactive Selection**: GRUB menu allows you to choose server type at boot time
3. **No Timeout**: Menu requires manual selection, preventing accidental installations
4. **Clear Organization**: Each server configuration is stored in its own directory structure

## File Structure

### New Unified Approach Files

- `host-incus-image-unified.yaml` - Main playbook for unified ISO generation
- `tasks/host-incus-image-unified-server-tasks.yml` - Tasks for processing each server configuration
- `templates/grub-unified.cfg.j2` - Enhanced GRUB configuration with server selection menu
- `templates/autoinstall-unified.yaml.j2` - Enhanced autoinstall template for unified approach
- `templates/server-types.conf.j2` - Metadata file describing available server configurations

### Generated ISO Structure

```
/autoinstall/
├── common/
│   ├── incus-firstboot-setup.service
│   └── (shared files)
├── msz_single_disk_server/
│   ├── autoinstall.yaml
│   ├── incus-preseed.yaml
│   ├── incus-profile-production.yaml
│   └── incus-firstboot-setup.sh
├── msz_dual_disk_server/
│   ├── autoinstall.yaml
│   ├── incus-preseed.yaml
│   ├── incus-profile-production.yaml
│   └── incus-firstboot-setup.sh
└── server-types.conf
```

## Usage

### Generate Unified ISO

```bash
# Using default config directory
ansible-playbook -i configs/host-incus-cluster.yaml playbooks/ring0/host-incus-image-unified.yaml

# Using private configs
ansible-playbook -i configs.private/infra-bootstrap/host-incus-cluster.yaml \
                 -e preseed_output_dir=configs.private/infra-bootstrap \
                 playbooks/ring0/host-incus-image-unified.yaml
```

### Boot Process

1. **Boot from ISO**: Start the system with the unified ISO
2. **GRUB Menu**: You'll see a menu with:
   - Header indicating this is a server type selection
   - Individual entries for each server configuration (e.g., "AUTOINSTALL - MSZ_SINGLE_DISK_SERVER (1 disk)")
   - Manual installation option (safe mode)
   - Information display option
   - Reboot/Shutdown options
3. **Selection Required**: No timeout - you must manually select a server type
4. **Automatic Installation**: Once selected, the system will automatically install using the chosen configuration

### GRUB Menu Features

- **No Timeout**: Prevents accidental installations
- **Clear Labels**: Each server type shows disk count and configuration name
- **Safe Options**: Manual installation mode available
- **Information Display**: Shows details about each server configuration
- **Visual Separation**: Menu separators improve readability

## Server Configuration Detection

The system uses several methods to ensure the correct configuration is applied:

1. **Kernel Parameter**: The selected server type is passed as `server_type=<name>`
2. **Directory Path**: Autoinstall looks in `/cdrom/autoinstall/<server_type>/`
3. **Marker File**: Creates `/etc/server-type` on the installed system for reference

## Output Files

- **Unified ISO**: `~/iso/ubuntu-unified-autoinstall.iso`
- **Config Files**: Still generated in the specified `preseed_output_dir` for reference

## Migration from Original Approach

### Before (Multiple ISOs)
- Generated separate ISO per server type
- Each ISO: ~4GB+ storage requirement
- Manual management of multiple files
- Risk of using wrong ISO

### After (Single Unified ISO)
- One ISO contains all configurations: ~4GB total
- Interactive selection prevents errors  
- Centralized management
- Easier deployment and storage

## Compatibility

- **Backward Compatible**: Original playbooks (`host-incus-image-main.yaml`) still work
- **Same Templates**: Uses existing Jinja2 templates with minimal modifications
- **Same Configuration**: Uses same `host-incus-cluster.yaml` inventory structure

## Advanced Features

### Server Type Information Display

The GRUB menu includes an information option that displays:
- Available server configurations
- Disk layout for each type
- Network configuration details
- Root partition sizes

### Error Prevention

- **Clear Warnings**: Each autoinstall option shows disk wipe warning
- **Server Type Validation**: System validates server type during installation
- **Safe Mode**: Manual installation always available
- **Configuration Logging**: Installation logs show selected server type

## Troubleshooting

### Common Issues

1. **Menu Not Appearing**: Check GRUB configuration generation
2. **Wrong Configuration Applied**: Verify kernel parameters in GRUB entries
3. **File Not Found Errors**: Ensure all server configurations are generated properly

### Debug Information

- Check `/cdrom/autoinstall/server-types.conf` for available configurations
- Boot logs show selected server type during early-commands phase
- `/etc/server-type` file on installed system shows which configuration was used

## Future Enhancements

Potential improvements to consider:

1. **Dynamic Detection**: Auto-detect hardware and suggest server type
2. **Validation**: Pre-installation hardware validation against selected configuration
3. **Recovery**: Option to change server type if initial selection was incorrect
4. **Custom Configurations**: Runtime modification of disk layouts