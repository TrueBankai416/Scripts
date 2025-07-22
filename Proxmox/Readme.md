# Proxmox Automation Scripts

A comprehensive collection of scripts to automatically fix common Proxmox issues and perform system maintenance. This toolkit provides automated solutions for network connectivity problems, storage management, console access issues, filesystem expansion, and firmware management.

## Problems Solved

1. **Network Connectivity**: Proxmox occasionally loses internet connectivity, requiring manual intervention to unplug and plug back in the ethernet cable
2. **Storage Management**: Proxmox storage can fill up quickly with VM backups, logs, and other data, requiring analysis and cleanup  
3. **Storage Configuration**: Proxmox storage display inconsistencies where summary page shows wrong capacity compared to actual disk size
4. **Console Access**: Proxmox console 500 errors preventing VM/container console access through the web interface
5. **GUI Loading Issues**: Web interface JavaScript errors, missing files, and ExtJS library problems preventing proper GUI loading
6. **Root Filesystem Expansion**: Expanding root filesystem after cloning to larger drives or upgrading storage
7. **Firmware Management**: Scanning NVMe and HDD drives for current firmware versions and providing update guidance
8. **Subscription Popup**: Annoying "no valid subscription" popup that appears every login for users without enterprise subscriptions

## Scripts Overview

### Installation & Management
- **`install.sh`** - Interactive installation script that downloads and installs all other scripts

### Network Management  
- **`fix-network.sh`** - Fixes network connectivity issues, handles hardware hangs (Intel e1000e support)
- **`network-monitor.sh`** - Continuous network monitoring with automatic fixing
- **`network-fix.service`** - Systemd service for automated monitoring

### Storage Management
- **`storage-analyzer.sh`** - Comprehensive storage analysis and reporting
- **`storage-cleanup.sh`** - Interactive cleanup of logs, packages, VM backups, and temporary files
- **`storage-config-fix.sh`** - Fix storage configuration discrepancies and expand LVM volumes
- **`root-filesystem-expand.sh`** - Expand root filesystem after cloning to larger drives

### System Management
- **`console-fix.sh`** - Diagnose and fix Proxmox console 500 errors
- **`gui-fix.sh`** - Diagnose and fix Proxmox web interface loading issues and JavaScript errors
- **`firmware-scanner.sh`** - Scan drives for firmware versions and provide update guidance
- **`subscription-popup-fix.sh`** - Remove the "no valid subscription" popup warning at login

For detailed documentation on each script, see the individual README files:
- [README-install.md](README-install.md) - Complete install.sh documentation
- [README-fix-network.md](README-fix-network.md) - Network fixing script
- [README-network-monitor.md](README-network-monitor.md) - Network monitoring
- [README-storage-analyzer.md](README-storage-analyzer.md) - Storage analysis
- [README-storage-cleanup.md](README-storage-cleanup.md) - Storage cleanup
- [README-storage-config-fix.md](README-storage-config-fix.md) - Storage configuration fixes
- [README-console-fix.md](README-console-fix.md) - Console troubleshooting
- [README-gui-fix.md](README-gui-fix.md) - Web interface loading issues
- [README-root-filesystem-expand.md](README-root-filesystem-expand.md) - Root filesystem expansion
- [README-firmware-scanner.md](README-firmware-scanner.md) - Firmware scanning and updates
- [README-subscription-popup-fix.md](README-subscription-popup-fix.md) - Subscription popup removal

## Quick Start

### Method 1: Interactive Installation (Recommended)

Download and run the interactive installation script:

```bash
# Download the installer
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/refs/heads/main/Proxmox/install.sh
chmod +x install.sh

# Run interactive installation
sudo ./install.sh
```

The interactive installer will present you with options to:
1. **Download and install all Proxmox tools** (network + storage + console + root expansion + firmware + subscription popup fix)
2. **Download and install specific tool categories** (network only, storage only, etc.)
3. **Download scripts only** (no system installation)
4. **Check for script updates**
5. **Uninstall existing tools**
6. **Test current installation**

### Method 2: Command Line Installation

```bash
# Install all tools
sudo ./install.sh install

# Install specific categories
sudo ./install.sh install-network    # Network tools only
sudo ./install.sh install-storage    # Storage tools only  
sudo ./install.sh install-console    # Console tools only
sudo ./install.sh install-root       # Root expansion only

# Other operations
sudo ./install.sh uninstall          # Remove all tools
sudo ./install.sh test               # Test installation
./install.sh download                # Download scripts only
./install.sh check-updates           # Check for updates
./install.sh help                    # Show help
```

### Method 3: Direct Script Usage

After installation, use the tools directly:

```bash
# Network management
sudo fix-network                     # Auto-detect and fix primary interface
sudo fix-network eth0                # Fix specific interface
sudo network-monitor                 # Start continuous monitoring

# Storage management  
sudo storage-analyzer                # Analyze storage usage
sudo storage-cleanup                 # Interactive cleanup
sudo storage-config-fix              # Fix configuration issues
sudo root-filesystem-expand          # Expand root filesystem

# System management
sudo console-fix                     # Fix console 500 errors
sudo gui-fix                         # Fix web interface loading issues
sudo firmware-scanner                # Scan drive firmware
sudo subscription-popup-fix          # Remove subscription popup warning
```

## Key Features

### Installation & Management
- **Interactive installer** with menu-driven interface
- **Automatic dependency detection** and installation
- **Update checking** with version comparison
- **Selective installation** by tool category
- **Safe uninstallation** with cleanup
- **Installation testing** and validation

### Network Management
- **Auto-detection** of primary network interfaces
- **Bridge support** for Proxmox bridge interfaces (vmbr0, etc.)  
- **Hardware hang detection** for Intel e1000e controllers
- **Hardware-level reset** with module reload and PCI reset
- **Driver-aware resets** with different strategies per controller type
- **Continuous monitoring** with automatic fixing
- **Comprehensive logging** and diagnostics

### Storage Management  
- **Storage analysis** with detailed usage reporting
- **Interactive cleanup** with safety confirmations
- **LVM expansion** including thin pool support
- **Configuration fixing** for storage discrepancies
- **Root filesystem expansion** after disk upgrades
- **VM backup management** with age-based cleanup

### System Management
- **Console troubleshooting** for 500 errors
- **SSL certificate management** and regeneration
- **Service health checking** and repair
- **Firmware scanning** for NVMe and SATA drives
- **Manufacturer-specific** update guidance
- **Security and performance** update prioritization

## Usage Options

### Manual Execution

```bash
# Auto-detect primary interface
sudo ./fix-network.sh

# Specify interface
sudo ./fix-network.sh eth0

# Show help
./fix-network.sh --help

# Root filesystem expansion
sudo ./root-filesystem-expand.sh

# Firmware scanning
sudo ./firmware-scanner.sh
```

### Installation Options

The `install.sh` script supports both interactive and command-line modes:

**Interactive Mode (Default):**
```bash
sudo ./install.sh    # Shows interactive menu
```

**Command Line Mode:**
```bash
sudo ./install.sh install    # Download and install tools
./install.sh download         # Download scripts only
sudo ./install.sh uninstall  # Remove all tools
sudo ./install.sh test       # Test installation
./install.sh help            # Show usage help
```

**Interactive Menu Options:**
1. Download and install all Proxmox tools (includes network, storage, console, root expansion, and firmware scanning)
2. Download scripts only (no installation)
3. Uninstall Proxmox tools
4. Test current installation
5. Exit

**Automation Setup:**
After installation, the script will ask if you want to setup automatic monitoring:
- **Systemd Service**: Continuous monitoring (recommended)
- **Cron Job**: Periodic checks every 5 minutes
- **Skip**: Manual setup later

## Configuration

### Network Scripts
You can modify these variables at the top of fix-network.sh:

- `LOG_FILE`: Location of log file (default: `/var/log/network-fix.log`)
- `MAX_RETRIES`: Number of retry attempts (default: 3)
- `RETRY_DELAY`: Delay between retries in seconds (default: 5)
- `PING_TARGET`: Host to ping for connectivity test (default: 8.8.8.8)
- `CONNECTIVITY_TIMEOUT`: Ping timeout in seconds (default: 5)

### Storage Scripts
You can modify these variables at the top of storage-analyzer.sh, storage-cleanup.sh, and storage-config-fix.sh:

- `LOG_FILE`: Location of log file (default: `/var/log/storage-analyzer.log`, `/var/log/storage-cleanup.log`, or `/var/log/storage-config-fix.log`)
- `REPORT_FILE`: Location of analysis report (default: `/tmp/storage-report.txt`)
- `BACKUP_DIR`: Directory for cleanup backups (default: `/var/backups/storage-cleanup`)

### Root Filesystem Expansion
You can modify these variables at the top of root-filesystem-expand.sh:

- `LOG_FILE`: Location of log file (default: `/var/log/root-filesystem-expand.log`)

### Firmware Scanner
You can modify these variables at the top of firmware-scanner.sh:

- `LOG_FILE`: Location of log file (default: `/var/log/firmware-scanner.log`)
- `REPORT_FILE`: Location of analysis report (default: `/tmp/firmware-report.txt`)

### GUI Fix Script
You can modify these variables at the top of gui-fix.sh:

- `LOG_FILE`: Location of log file (default: `/var/log/gui-fix.log`)
- `BACKUP_DIR`: Directory for configuration backups (default: `/var/backups/gui-fix`)

## Documentation

For detailed usage instructions for individual scripts:

- **Network Tools**: See inline help with `./fix-network.sh --help`
- **Storage Tools**: See inline help and comprehensive logging
- **Console Tools**: See inline help with `./console-fix.sh --help`
- **GUI Tools**: See inline help with `./gui-fix.sh --help` and [README-gui-fix.md](README-gui-fix.md)
- **Root Expansion**: See [README-root-filesystem-expand.md](README-root-filesystem-expand.md) for detailed usage guide
- **Firmware Scanner**: See inline help with `./firmware-scanner.sh --help`

## Common Issues Resolved

### Network Issues
- Network connectivity loss requiring cable replug
- Intel e1000e hardware hangs
- Bridge interface problems
- DHCP renewal failures

### Storage Issues
1. **Storage display discrepancies** - Fixes cases where Proxmox shows incorrect storage capacity
2. **Unallocated disk space** - Expands physical volumes and logical volumes to use full disk
3. **Thin pool expansion** - Automatically expands thin pools when space is available
4. **Root filesystem expansion** - Expands root filesystem after cloning to larger drive with custom sizing
5. **Full root filesystem** - Identifies what's consuming space in root partition
6. **LVM thin pool full** - Analyzes thin pool usage and suggests cleanup

### Console Issues
1. **Console 500 errors** - Fixes internal server errors preventing console access
2. **Proxmox service issues** - Diagnoses and restarts failed web services
3. **SSL certificate problems** - Detects expired or corrupted certificates
4. **Service dependency failures** - Ensures all required services are running

### GUI Loading Issues
1. **JavaScript syntax errors** - Fixes corrupted JavaScript files like proxmoxlib.js and pvemanagerlib.js
2. **Missing web interface files** - Repairs missing critical files and web components
3. **ExtJS library problems** - Resolves ExtJS constructor and loading issues
4. **Cache corruption** - Clears corrupted cache and temporary files causing loading failures
5. **Web service configuration** - Fixes pveproxy and web service configuration problems
6. **File permission issues** - Corrects permissions on web interface directories and files

### Firmware Issues
1. **Outdated firmware** - Identifies current firmware versions and available updates
2. **Security vulnerabilities** - Highlights firmware updates that fix security issues
3. **Performance problems** - Identifies firmware updates that improve drive performance
4. **Compatibility issues** - Provides manufacturer-specific update guidance

## Best Practices

1. **Regular monitoring** - Set up automated network monitoring
2. **Storage maintenance** - Run storage analysis monthly
3. **Storage configuration** - Fix storage discrepancies when they occur
4. **Console health checks** - Run console diagnostics after system updates
5. **GUI maintenance** - Run GUI diagnostics if experiencing web interface issues
6. **Backup before expansion** - Always backup important data before expanding filesystems
7. **Test in non-production** - Validate scripts in test environment
8. **Plan expansions** - Use the expansion opportunity checker before making changes
9. **Firmware monitoring** - Run firmware scans quarterly to check for updates
10. **Update planning** - Schedule firmware updates during maintenance windows
11. **Update verification** - Always verify system stability after firmware updates

## License

These scripts are provided as-is for educational and practical purposes. Use at your own risk.
