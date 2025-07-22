# Proxmox GUI Fix Script

This script diagnoses and fixes common Proxmox web interface loading issues, including JavaScript errors, missing files, and corrupted web components.

## Problems Solved

- **JavaScript Syntax Errors**: Fixes corrupted JavaScript files like `proxmoxlib.js` and `pvemanagerlib.js`
- **Missing Web Files**: Repairs missing critical files like `StdWorkspace.js` and other web interface components
- **ExtJS Library Issues**: Resolves ExtJS constructor and library loading problems
- **Cache/Temporary File Corruption**: Clears corrupted cache and temporary files that can cause loading issues
- **Service Configuration Problems**: Fixes web service configuration and SSL certificate issues
- **File Permission Issues**: Corrects file and directory permissions for web interface components
- **Subscription Popup Script Side Effects**: Detects and repairs GUI issues caused by subscription popup removal modifications

## Common Error Messages Fixed

- `Uncaught SyntaxError: missing formal parameter proxmoxlib.js`
- `Uncaught TypeError: can't access property "defaultText", Proxmox.Utils is undefined`
- `HTTP/1.1 500 no such file '/PVE/StdWorkspace.js'`
- `Uncaught TypeError: c is not constructor ExtJS`
- `XML Parsing Error: syntax error`

## Usage

### Interactive Mode (Recommended)

```bash
# Download and make executable
wget https://raw.githubusercontent.com/TrueBankai416/Proxmox/main/gui-fix.sh
chmod +x gui-fix.sh

# Run interactive mode
sudo ./gui-fix.sh
```

The interactive mode will:
1. **Diagnose** - Check web interface files, services, and cache
2. **Repair** - Fix detected issues automatically
3. **Verify** - Test the web interface functionality

### Command Line Options

```bash
# Run diagnostic checks only
sudo ./gui-fix.sh check

# Repair web interface files
sudo ./gui-fix.sh repair

# Clear cache and temporary files
sudo ./gui-fix.sh cache

# Restart web services
sudo ./gui-fix.sh restart

# Test web interface functionality
sudo ./gui-fix.sh test

# Show diagnostic information
sudo ./gui-fix.sh diag

# Show help
./gui-fix.sh help
```

## What the Script Does

### Diagnostic Phase

1. **Subscription Popup Modification Detection**
   - Checks for modifications made by the subscription popup removal script
   - Identifies potential JavaScript syntax issues caused by popup modifications
   - Locates backup files created by the subscription script
   - Warns about potential conflicts and repair strategies

2. **Web File Integrity Check**
   - Verifies critical JavaScript files exist and are not corrupted
   - Checks file sizes and basic syntax validation
   - Examines web interface directories and permissions
   - Looks for missing components like StdWorkspace.js

3. **Service Configuration Check**
   - Verifies pveproxy service is running properly
   - Checks web interface is listening on port 8006
   - Examines recent error logs
   - Validates SSL certificates and configuration files

4. **Cache and Temporary Files Check**
   - Analyzes cache directory sizes and file counts
   - Identifies corrupted or problematic temporary files
   - Checks directory permissions (especially /var/tmp)

### Repair Phase

1. **Subscription Popup Backup Restoration** (if applicable)
   - Restores original JavaScript files from subscription popup script backups
   - Offers to reapply popup modifications safely after GUI is functional
   - Prevents the need for full package reinstallation when backups are available

2. **Web Interface File Repair**
   - Reinstalls core Proxmox web packages if backup restoration fails:
     - `pve-manager` - Main Proxmox management interface
     - `proxmox-widget-toolkit` - UI widget library
     - `libjs-extjs` - ExtJS JavaScript framework
     - `pveproxy` - Web proxy service
   - Creates backups before making changes
   - Updates package repositories to ensure latest versions

3. **Cache and Temporary File Cleanup**
   - Safely stops pveproxy service
   - Clears corrupted cache files from `/var/cache/pve/`
   - Removes problematic temporary files
   - Recreates directories with correct permissions
   - Ensures `/var/tmp` has proper sticky bit permissions (1777)

4. **Service Restart and Verification**
   - Restarts web services in proper order
   - Verifies each service starts successfully
   - Checks service status after restart

### Verification Phase

1. **Web Interface Testing**
   - Tests basic connectivity to the web interface
   - Verifies critical JavaScript files are accessible
   - Checks HTTP response codes for key components
   - Reports on overall interface functionality

## Configuration

You can modify these variables at the top of the script:

- `LOG_FILE`: Location of log file (default: `/var/log/gui-fix.log`)
- `BACKUP_DIR`: Directory for configuration backups (default: `/var/backups/gui-fix`)

## Prerequisites

- Root access (script checks automatically)
- Proxmox VE system (script validates)
- Internet connection (for package reinstallation)
- `curl` command (usually pre-installed)
- `node` command (for JavaScript syntax checking - optional)

## Safety Features

- **Automatic Backups**: Configuration files are backed up before changes
- **Confirmation Prompts**: User confirmation required for destructive operations
- **Service Validation**: Verifies services start properly after restart
- **Comprehensive Logging**: All operations logged for troubleshooting
- **Non-destructive Checks**: Diagnostic mode doesn't modify system

## Troubleshooting

### If the script doesn't fix the issue:

1. **Check the log file**: `/var/log/gui-fix.log`
2. **Run diagnostic mode**: `sudo ./gui-fix.sh diag`
3. **Verify package integrity**: 
   ```bash
   apt list --installed | grep -E "pve-manager|proxmox-widget|extjs"
   ```
4. **Check for system updates**:
   ```bash
   apt update && apt upgrade
   ```

### Common resolution steps:

1. **Browser Cache**: Clear your browser cache and cookies for the Proxmox interface
2. **Different Browser**: Try accessing the interface from a different browser
3. **Incognito Mode**: Test in browser private/incognito mode
4. **Network Issues**: Ensure no firewall or network issues blocking port 8006

### Manual verification commands:

```bash
# Check if web services are running
systemctl status pveproxy pvedaemon

# Test web interface connectivity
curl -k https://localhost:8006

# Check for recent errors
journalctl -u pveproxy --since="1 hour ago"

# Verify JavaScript files
ls -la /usr/share/pve-manager/js/
ls -la /usr/share/javascript/proxmox-widget-toolkit/
```

## Recovery

If the script causes issues:

1. **Restore from backup**:
   ```bash
   # Backups are stored in /var/backups/gui-fix/
   ls /var/backups/gui-fix/
   ```

2. **Reinstall Proxmox packages**:
   ```bash
   apt update
   apt install --reinstall pve-manager proxmox-ve
   ```

3. **Reset to defaults**:
   ```bash
   apt update && apt full-upgrade
   ```

## Success Indicators

After running the script successfully:

- ✅ Web interface loads without JavaScript errors
- ✅ All interface components render properly  
- ✅ ExtJS widgets function correctly
- ✅ No 500 errors when accessing web resources
- ✅ Console and other features work normally

## When to Use This Script

Use this script when experiencing:

- Blank or partially loading Proxmox web interface
- JavaScript errors in browser console
- Missing interface elements or buttons
- 500 errors for web interface files
- ExtJS library errors
- Interface loading but not functioning properly

This script complements the existing `console-fix.sh` script, which focuses on VM/container console connectivity issues rather than web interface loading problems.

## Relationship with Subscription Popup Script

This GUI fix script has special integration with the subscription popup removal script (`subscription-popup-fix.sh`):

### Common Scenario
If you've run the subscription popup removal script and subsequently experience GUI loading issues, this is likely due to JavaScript modifications made by the popup script. This is a known interaction that can occur when:

1. The popup script modifies JavaScript files
2. The modifications accidentally break other JavaScript functionality
3. The web interface fails to load properly

### Integration Features

- **Automatic Detection**: The GUI fix script automatically detects if subscription popup modifications are present
- **Backup Restoration**: Can restore original files from subscription popup script backups
- **Safe Reapplication**: Offers to reapply popup modifications safely after repairs
- **Cross-Script Compatibility**: Both scripts are aware of each other's operations

### Best Practices

1. **If GUI issues occur after popup removal**:
   ```bash
   sudo ./gui-fix.sh    # Will detect and offer to restore from backups
   ```

2. **For safer popup removal**:
   ```bash
   # Use the improved subscription popup script (includes validation)
   sudo ./subscription-popup-fix.sh
   ```

3. **Testing sequence**:
   ```bash
   sudo ./subscription-popup-fix.sh    # Remove popup with safer methods
   # Test web interface in browser
   sudo ./gui-fix.sh check             # Verify no issues were introduced
   ```

### Improved Subscription Popup Script

The subscription popup script has been enhanced with:
- **JavaScript syntax validation** before and after modifications
- **Safer modification methods** that are less likely to cause syntax errors  
- **Automatic backup restoration** if syntax errors are detected
- **Warning messages** about potential GUI conflicts
- **Integration hints** to use the GUI fix script if problems occur

This script complements the existing `console-fix.sh` script, which focuses on VM/container console connectivity issues rather than web interface loading problems.
