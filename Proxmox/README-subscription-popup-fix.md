# Proxmox Subscription Popup Fix

This script removes the "no valid subscription" popup warning that appears when logging into the Proxmox web interface without an enterprise subscription.

## Problem

Proxmox VE displays a subscription popup warning every time you log into the web interface if you don't have a valid enterprise subscription. This popup is annoying for home lab users and those using the free community version.

## Solution

The script modifies the Proxmox JavaScript files to disable the subscription check popup while maintaining all other functionality. The modification is:

- **Safe**: Only affects the popup display, no system functionality is changed
- **Reversible**: Automatic backups allow easy restoration
- **Non-destructive**: Original files are preserved
- **Clean**: Uses proper JavaScript commenting

## Usage

### Basic Usage

```bash
# Remove subscription popup (with confirmation)
sudo ./subscription-popup-fix.sh

# Check current popup status
sudo ./subscription-popup-fix.sh --status

# Restore original popup behavior
sudo ./subscription-popup-fix.sh --restore

# Create backup only (no changes)
sudo ./subscription-popup-fix.sh --backup
```

### Command Line Options

- `--status` - Check if popup is currently enabled/disabled
- `--restore` - Restore original popup from backup
- `--backup` - Create backup without making changes
- `--help` - Show detailed help information

## Features

### Safety Features
- **Automatic backups** before any modifications
- **Backup validation** to ensure files can be restored
- **Rollback capability** with `--restore` option
- **Status checking** to verify current state
- **Confirmation prompts** before making changes

### Smart Detection
- **Auto-locates** Proxmox JavaScript files across different versions
- **Version compatibility** with various Proxmox VE releases
- **Path detection** handles different installation locations
- **File validation** ensures correct files are modified

### Comprehensive Logging
- **Detailed logging** of all operations
- **Timestamped entries** for audit trail
- **Error tracking** for troubleshooting
- **Status reporting** for verification

## Technical Details

### Files Modified

The script typically modifies one of these files:
- `/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js`
- `/usr/share/pve-manager/js/pvemanagerlib.js`
- Other location-dependent JavaScript files containing subscription checks

### Modification Method

The script replaces subscription popup code with:
```javascript
// POPUP DISABLED - Original subscription check replaced
void(0);
```

### Backup Location

Backups are stored in `/var/backups/subscription-popup-fix/` with timestamp preservation.

## Installation Integration

This script is included in the main installation system and can be installed via:

```bash
# Download installer
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/refs/heads/main/Proxmox/install.sh
chmod +x install.sh

# Interactive installation
sudo ./install.sh

# Command line installation
sudo ./install.sh install
```

## Compatibility

### Supported Versions
- Proxmox VE 6.x
- Proxmox VE 7.x
- Proxmox VE 8.x
- Future versions (with auto-detection)

### System Requirements
- Root/sudo access required
- Proxmox VE installation
- systemctl available for service restart

## Common Use Cases

### Home Lab Setup
Perfect for home lab environments where enterprise subscription isn't needed:

```bash
# One-time setup after Proxmox installation
sudo ./subscription-popup-fix.sh
```

### Development Environment
Ideal for development and testing environments:

```bash
# Disable popup for clean development experience
sudo ./subscription-popup-fix.sh

# Later restore for production deployment
sudo ./subscription-popup-fix.sh --restore
```

### Batch Deployment
For multiple Proxmox installations:

```bash
# Script can be run on multiple systems
for server in server1 server2 server3; do
    ssh root@$server 'curl -s https://raw.githubusercontent.com/TrueBankai416/Scripts/refs/heads/main/Proxmox/subscription-popup-fix.sh | bash -s'
done
```

## Troubleshooting

### Popup Still Appears

If the popup still appears after running the script:

1. Check browser cache:
   ```bash
   # Clear browser cache and hard refresh (Ctrl+F5)
   ```

2. Verify modification:
   ```bash
   sudo ./subscription-popup-fix.sh --status
   ```

3. Restart web service:
   ```bash
   sudo systemctl restart pveproxy
   ```

### Script Cannot Find Files

If the script reports it cannot find Proxmox files:

```bash
# Check Proxmox installation
pveversion

# Manual file search
find /usr/share -name "*.js" -exec grep -l "No valid subscription" {} \;
```

### Restore Issues

If restoration fails:

```bash
# Check backup exists
ls -la /var/backups/subscription-popup-fix/

# Manual restore (replace filename as needed)
sudo cp /var/backups/subscription-popup-fix/proxmoxlib.js.backup /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
sudo systemctl restart pveproxy
```

## Updates and Upgrades

### After Proxmox Updates

Proxmox updates may restore the original files. After updates:

```bash
# Check if popup returned
sudo ./subscription-popup-fix.sh --status

# Re-apply fix if needed
sudo ./subscription-popup-fix.sh
```

### Script Updates

The script includes version detection and will work with newer Proxmox versions automatically.

## Security Considerations

### What This Script Does
- ✅ Only modifies JavaScript popup display
- ✅ Creates backups for safety
- ✅ Preserves all system functionality
- ✅ Uses standard system tools

### What This Script Does NOT Do
- ❌ Modify system security settings
- ❌ Change Proxmox licensing checks
- ❌ Affect enterprise features
- ❌ Alter authentication mechanisms

## Best Practices

1. **Run after installation**: Apply the fix after initial Proxmox setup
2. **Check after updates**: Re-run after Proxmox updates
3. **Keep backups**: Don't delete backup files
4. **Test in non-production**: Verify in test environment first
5. **Document usage**: Keep record of when fix was applied

## Logging

All operations are logged to `/var/log/subscription-popup-fix.log`:

```bash
# View recent log entries
tail -f /var/log/subscription-popup-fix.log

# Search for specific operations
grep "disabled" /var/log/subscription-popup-fix.log
```

## Related Scripts

This script works well with other Proxmox automation tools:
- `console-fix.sh` - Fixes console access issues
- `storage-cleanup.sh` - Manages storage space
- `network-monitor.sh` - Monitors network connectivity

## Support

For issues or questions:
1. Check the log file for detailed error messages
2. Run with `--status` to verify current state
3. Use `--restore` to return to original state
4. Refer to troubleshooting section above

## License

This script is provided as-is for educational and practical purposes. Use at your own risk.
