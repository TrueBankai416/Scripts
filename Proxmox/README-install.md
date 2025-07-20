# install.sh - Proxmox Tools Installer

The `install.sh` script is an interactive installer that downloads, installs, manages, and maintains all Proxmox automation tools in this repository.

## Overview

This installer provides a complete management system for Proxmox automation tools with features including:

- **Interactive menu-driven interface** for easy operation
- **Automatic script downloads** from the GitHub repository
- **Update checking and management** with version comparison
- **Selective installation** by tool category
- **System integration** with proper permissions and symlinks
- **Service setup** for automated monitoring
- **Safe uninstallation** with complete cleanup
- **Installation testing** and validation

## Quick Start

### Basic Usage

```bash
# Download and run interactively
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/refs/heads/main/Proxmox/install.sh
chmod +x install.sh
sudo ./install.sh
```

### Command Line Usage

```bash
# Install all tools
sudo ./install.sh install

# Install specific categories
sudo ./install.sh install-network
sudo ./install.sh install-storage
sudo ./install.sh install-console
sudo ./install.sh install-root

# Management operations
sudo ./install.sh uninstall
sudo ./install.sh test
./install.sh download
./install.sh check-updates
./install.sh help
```

## Interactive Menu Options

When run without arguments, the installer presents an interactive menu:

### 1. Download and Install All Proxmox Tools
- Downloads all scripts from the repository
- Installs to `/usr/local/bin/` with proper permissions
- Creates symlinks for easy command access
- Sets up systemd services for monitoring
- Configures log files
- Offers to set up automated network monitoring

### 2-5. Install Specific Tool Categories
- **Network tools**: `fix-network.sh`, `network-monitor.sh`, `network-fix.service`
- **Storage tools**: `storage-analyzer.sh`, `storage-cleanup.sh`, `storage-config-fix.sh`
- **Console tools**: `console-fix.sh`
- **Root expansion**: `root-filesystem-expand.sh`
- **Firmware tools**: `firmware-scanner.sh`

### 6. Download Scripts Only
- Downloads scripts to current directory without installation
- Makes scripts executable
- No system integration or service setup
- Useful for review or custom installation

### 7. Check for Script Updates
- Compares local files with repository versions
- Shows available updates with file size and date information
- Option to download and install updates
- Handles both existing and missing files

### 8. Uninstall Proxmox Tools
- Interactive selection of what to uninstall
- Removes installed scripts and symlinks
- Stops and disables systemd services
- Removes cron jobs if present
- Preserves log files for reference

### 9. Test Current Installation
- Validates all installed scripts are executable
- Tests help functionality for each script
- Checks systemd service files
- Reports installation status and issues

## Installation Details

### File Locations
- **Scripts**: `/usr/local/bin/` (with `.sh` extension)
- **Symlinks**: `/usr/local/bin/` (without extension for easy access)
- **Services**: `/etc/systemd/system/`
- **Log Files**: `/var/log/`
- **Backups**: `/var/backups/storage-cleanup/`

### Installed Commands
After installation, these commands become available:
- `fix-network` → `fix-network.sh`
- `network-monitor` → `network-monitor.sh`
- `storage-analyzer` → `storage-analyzer.sh`
- `storage-cleanup` → `storage-cleanup.sh`
- `storage-config-fix` → `storage-config-fix.sh`
- `console-fix` → `console-fix.sh`
- `root-filesystem-expand` → `root-filesystem-expand.sh`
- `firmware-scanner` → `firmware-scanner.sh`

### Log Files Created
- `/var/log/network-fix.log`
- `/var/log/network-monitor.log`
- `/var/log/storage-analyzer.log`
- `/var/log/storage-cleanup.log`
- `/var/log/storage-config-fix.log`
- `/var/log/console-fix.log`
- `/var/log/root-filesystem-expand.log`
- `/var/log/firmware-scanner.log`

## Update Management

### Automatic Update Checking
The installer automatically checks for updates when run interactively:
- Compares file sizes and modification dates
- Downloads newer versions from the repository
- Handles both GitHub repository files and local modifications
- Provides clear update summaries

### Manual Update Checking
```bash
# Check for updates
./install.sh check-updates

# Force update check
./install.sh check-updates --force
```

### Update Process
1. **Detection**: Compares local vs. repository file versions
2. **Reporting**: Shows which files have updates available
3. **Selection**: User chooses whether to download updates
4. **Download**: Fetches updated files from repository
5. **Validation**: Ensures downloaded files are valid
6. **Installation**: Updates installed versions if requested

## Network Monitoring Setup

After installing network tools, the installer offers automated monitoring setup:

### Systemd Service (Recommended)
- Continuous network monitoring
- Automatic restart on failure
- Integrated with systemd logging
- Easy management with `systemctl`

```bash
# Service management commands
sudo systemctl status network-fix.service
sudo systemctl stop network-fix.service
sudo systemctl start network-fix.service
sudo systemctl disable network-fix.service
```

### Cron Job Alternative
- Periodic checks every 5 minutes
- Lightweight resource usage
- Traditional cron-based scheduling
- Logs to file

```bash
# Cron job added:
*/5 * * * * /usr/local/bin/network-monitor check >/dev/null 2>&1
```

## Advanced Features

### Dependency Management
The installer automatically handles dependencies:
- Checks for required system packages
- Installs missing packages via `apt`
- Validates tool availability
- Provides fallback suggestions

### Error Handling
- Comprehensive error checking at each step
- Clear error messages with suggested solutions
- Graceful degradation when possible
- Detailed logging for troubleshooting

### Repository Integration
- Downloads from GitHub repository
- Handles HTTP errors and network issues
- Validates downloaded file integrity
- Supports branch switching (uses main branch)

### Safety Features
- **Root privilege checking**: Ensures proper permissions
- **File validation**: Confirms downloads are complete and valid
- **Backup creation**: Preserves existing configurations
- **Rollback capability**: Can restore previous versions
- **Dry run mode**: Preview changes before applying

## Troubleshooting

### Common Issues

**1. Download Failures**
```bash
# Check internet connectivity
ping -c 3 github.com

# Manual download test
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/refs/heads/main/Proxmox/install.sh
```

**2. Permission Errors**
```bash
# Ensure running as root for installation
sudo ./install.sh
```

**3. Service Start Failures**
```bash
# Check service status
sudo systemctl status network-fix.service

# Check service logs
sudo journalctl -u network-fix.service
```

**4. Update Check Failures**
- Network connectivity issues
- Repository access problems
- Local file permission issues

### Log Analysis
```bash
# View installer activity
tail -f /var/log/syslog | grep install

# Check specific tool logs
ls -la /var/log/*-*.log
```

## Configuration

### Customization Options
The installer can be customized by editing these variables at the top of the script:

```bash
INSTALL_DIR="/usr/local/bin"      # Installation directory
SERVICE_DIR="/etc/systemd/system" # Systemd service directory
LOG_DIR="/var/log"                # Log file directory
REPO_URL="https://raw.githubusercontent.com/TrueBankai416/Scripts/refs/heads/main/Proxmox"
```

### Environment Variables
- `SKIP_AUTO_CHECK`: Skip automatic update checking
- `AUTO_FIX`: Enable automatic fixes without prompts

## Best Practices

### Regular Maintenance
1. **Monthly update checks**: Run `./install.sh check-updates`
2. **Log monitoring**: Check `/var/log/` for tool activity
3. **Service health**: Monitor systemd services if enabled
4. **Disk space**: Ensure adequate space for logs and backups

### Security Considerations
1. **Download verification**: Always verify script integrity
2. **Source validation**: Only download from trusted repository
3. **Permission review**: Understand what the installer modifies
4. **Log monitoring**: Review installation and update logs

### Integration Tips
1. **Automation**: Use command-line options in scripts
2. **Monitoring**: Integrate with existing monitoring systems
3. **Documentation**: Keep track of installed tools and versions
4. **Testing**: Test in non-production environment first

## Support and Updates

### Getting Help
- Use `./install.sh help` for command reference
- Check individual script README files for detailed usage
- Review log files for troubleshooting information
- Test installation with `./install.sh test`

### Staying Updated
- Run periodic update checks
- Monitor repository for new features
- Test updates in development environment
- Keep backups of working configurations

The installer is designed to be the primary interface for managing all Proxmox automation tools, providing a consistent and reliable way to maintain your toolkit.
