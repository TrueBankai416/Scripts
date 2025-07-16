# Proxmox Automation Scripts

This repository contains scripts to automatically fix common Proxmox issues including network connectivity problems and storage management.

## Problems Solved

1. **Network Connectivity**: Proxmox occasionally loses internet connectivity, requiring manual intervention to unplug and plug back in the ethernet cable
2. **Storage Management**: Proxmox storage can fill up quickly with VM backups, logs, and other data, requiring analysis and cleanup

## Files

### Network Management
- `fix-network.sh` - Main script to restart network interface
- `network-monitor.sh` - Continuous monitoring script (optional)
- `network-fix.service` - Systemd service file for monitoring (optional)

### Storage Management
- `storage-analyzer.sh` - Comprehensive storage analysis and reporting
- `storage-cleanup.sh` - Safe cleanup of common space consumers

## Quick Start

1. **Interactive install (Recommended):**
   ```bash
   # Download and run the interactive installation script
   wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/install.sh
   chmod +x install.sh
   sudo ./install.sh
   ```
   
   This will show an interactive menu with options to:
   - Download and install all Proxmox tools (network + storage)
   - Download scripts only
   - Uninstall existing tools
   - Test current installation

2. **Manual setup (Alternative):**
   ```bash
   # Download individual scripts
   wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/fix-network.sh
   wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/storage-analyzer.sh
   wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/storage-cleanup.sh
   
   # Make scripts executable
   chmod +x *.sh
   
   # Move to system location (optional)
   sudo mv fix-network.sh /usr/local/bin/fix-network
   sudo mv storage-analyzer.sh /usr/local/bin/storage-analyzer
   sudo mv storage-cleanup.sh /usr/local/bin/storage-cleanup
   ```

3. **Usage:**
   ```bash
   # Network fixes
   sudo fix-network               # Auto-detect primary interface
   sudo fix-network eth0          # Specify interface
   
   # Storage management
   sudo storage-analyzer          # Analyze storage usage
   sudo storage-cleanup           # Interactive cleanup
   sudo storage-cleanup all       # Clean all categories
   ```

## Features

- **Auto-detection**: Automatically finds the primary network interface
- **Bridge support**: Special handling for Proxmox bridge interfaces (vmbr0, etc.)
- **Physical interface restart**: For bridges, also restarts underlying physical interfaces
- **Hardware hang detection**: Detects and handles Intel e1000e controller hangs from kernel logs
- **Hardware-level reset**: Module reload and PCI reset for hardware hangs (e1000e, etc.)
- **Driver-aware resets**: Different reset strategies based on network controller driver
- **Connectivity checking**: Tests network before and after restart with multiple targets
- **Retry logic**: Attempts multiple times if first try fails
- **DHCP renewal**: Automatically attempts DHCP lease renewal
- **Extended diagnostics**: Comprehensive logging and troubleshooting information
- **Logging**: Comprehensive logging to `/var/log/network-fix.log`
- **Safe operation**: Checks for root privileges and interface existence
- **Interactive mode**: Prompts before restarting if network appears working

## Usage Options

### Manual Execution

```bash
# Auto-detect primary interface
sudo ./fix-network.sh

# Specify interface
sudo ./fix-network.sh eth0

# Show help
./fix-network.sh --help
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
1. Download and install network fix tools (includes automation setup)
2. Download scripts only (no installation)
3. Uninstall network fix tools
4. Test current installation
5. Exit

**Automation Setup:**
After installation, the script will ask if you want to setup automatic monitoring:
- **Systemd Service**: Continuous monitoring (recommended)
- **Cron Job**: Periodic checks every 5 minutes
- **Skip**: Manual setup later

### Automated Monitoring

**Automatic Setup (Recommended):**
The interactive installer will ask if you want to setup monitoring and help you choose between:

**Option 1: Systemd Service (Continuous Monitoring)**
```bash
# Automatically configured during installation, or manually:
sudo systemctl enable network-fix.service
sudo systemctl start network-fix.service
sudo systemctl status network-fix.service
sudo journalctl -u network-fix.service -f
```

**Option 2: Cron Job (Periodic Checks)**
```bash
# Automatically configured during installation, or manually:
sudo crontab -e
# Add: */5 * * * * /usr/local/bin/network-monitor check >/dev/null 2>&1
```

**Manual Setup:**
If you skipped automation during installation, you can set it up later using the commands above.

## Configuration

### Network Scripts
You can modify these variables at the top of fix-network.sh:

- `LOG_FILE`: Location of log file (default: `/var/log/network-fix.log`)
- `MAX_RETRIES`: Number of retry attempts (default: 3)
- `RETRY_DELAY`: Delay between retries in seconds (default: 5)
- `PING_TARGET`: Host to ping for connectivity test (default: 8.8.8.8)
- `CONNECTIVITY_TIMEOUT`: Ping timeout in seconds (default: 5)

### Storage Scripts
You can modify these variables at the top of storage-analyzer.sh and storage-cleanup.sh:

- `LOG_FILE`: Location of log file (default: `/var/log/storage-analyzer.log` or `/var/log/storage-cleanup.log`)
- `REPORT_FILE`: Location of analysis report (default: `/tmp/storage-report.txt`)
- `BACKUP_DIR`: Directory for cleanup backups (default: `/var/backups/storage-cleanup`)

## Log Analysis

View recent network fix attempts:
```bash
sudo tail -f /var/log/network-fix.log
```

Check for patterns:
```bash
sudo grep "ERROR" /var/log/network-fix.log
sudo grep "Network connectivity restored" /var/log/network-fix.log
```

## Common Network Interfaces

- `eth0`, `eth1` - Traditional Ethernet interfaces
- `enp0s3`, `enp0s8` - Modern predictable network interface names
- `vmbr0`, `vmbr1` - Proxmox bridge interfaces (most common)

### Proxmox Bridge Interfaces

Proxmox uses bridge interfaces (typically `vmbr0`) that combine physical interfaces with virtual ones for VMs. The script automatically detects bridge interfaces and:

1. **Identifies bridge members**: Finds physical interfaces attached to the bridge
2. **Restarts physical interfaces first**: Restarts underlying hardware interfaces
3. **Restarts bridge interface**: Then restarts the bridge itself  
4. **Extended wait times**: Allows extra time for bridge stabilization
5. **DHCP renewal**: Attempts to renew DHCP leases
6. **Enhanced diagnostics**: Provides detailed troubleshooting info

To see bridge configuration:
```bash
# List all interfaces
ip link show

# Show bridge members
ls /sys/class/net/vmbr0/brif/

# Check bridge status
brctl show

# View network configuration
cat /etc/network/interfaces
```

### Hardware Hang Detection

The script automatically detects and handles hardware-level network controller issues, particularly common with Intel e1000e controllers:

**What it detects:**
- "Hardware Unit Hang" messages in kernel logs (`dmesg` or `journalctl`)
- Intel e1000e controller lockups (common in Proxmox systems)
- Link down/up cycles due to hardware issues

**Hardware reset methods:**
1. **ethtool reset**: Hardware-level interface reset
2. **Feature cycling**: Disable/enable RX/TX to clear buffers  
3. **Module reload**: For e1000e, completely reload the driver module
4. **Proxmox workaround**: Disable problematic features (gso, gro, tso, etc.)
5. **Persistent configuration**: Create systemd service for permanent feature settings
6. **PCI reset**: Direct PCI bus reset for the network controller

**When hardware reset is used:**
- Kernel logs show "Detected Hardware Unit Hang" messages
- Interface uses Intel e1000e driver (proactive reset)
- Standard software reset fails multiple times

**Multi-layered approach:**
- **Step 1**: ethtool hardware reset
- **Step 2**: Driver module reload (for e1000e)
- **Step 3**: Apply Proxmox community workaround (disable problematic features)
- **Step 4**: Generic PCI reset (for other drivers)
- **Step 5**: Create persistent configuration to prevent future issues

**Persistent Configuration:**
The script automatically creates systemd services to apply ethtool workarounds persistently:
- Service files: `/etc/systemd/system/ethtool-workaround-<interface>.service`
- Applied on every boot to prevent recurring hardware hangs
- Based on successful community solutions from Proxmox forums

To check for hardware hangs:
```bash
# Check recent kernel messages for hangs
dmesg -T | grep -i "hardware unit hang"

# Check system logs
journalctl --since="10 minutes ago" | grep -i "hardware unit hang"

# Check interface driver
ls -l /sys/class/net/*/device/driver

# Check if workaround service exists
systemctl status ethtool-workaround-eno2.service

# View current ethtool features
ethtool -k eno2 | grep -E "(gso|gro|tso|tx|rx|rxvlan|txvlan|sg):"
```

## Troubleshooting

1. **Script fails with permission error:**
   - Make sure you run with `sudo`
   - Check file permissions: `chmod +x fix-network.sh`

2. **Network still doesn't work after restart:**
   - Check physical connections
   - Verify network configuration: `cat /etc/network/interfaces`
   - Check system logs: `journalctl -u networking`

3. **Can't determine primary interface:**
   - Manually specify interface: `sudo ./fix-network.sh eth0`
   - List interfaces: `ip link show`

4. **Script runs but network still broken:**
   - Check if DHCP is working: `dhclient -v`
   - Verify DNS: `nslookup google.com`
   - Check routing: `ip route show`

## Safety Notes

- The script requires root privileges to restart network interfaces
- It will briefly disconnect network connectivity while restarting
- Always test in a non-production environment first
- Keep physical access to the server in case of issues

## Common Storage Issues Resolved

The storage scripts help resolve these common Proxmox storage problems:

1. **Full root filesystem** - Identifies what's consuming space
2. **LVM thin pool full** - Analyzes thin pool usage and suggests cleanup
3. **Large log files** - Finds and helps clean oversized logs
4. **Old VM backups** - Identifies and removes outdated backups
5. **Package cache buildup** - Cleans APT cache and orphaned packages
6. **Temporary file accumulation** - Safely removes old temporary files
7. **Duplicate files** - Finds and helps remove duplicate backups/files

## Best Practices

1. **Regular monitoring** - Set up automated network monitoring
2. **Storage maintenance** - Run storage analysis monthly
3. **Backup before cleanup** - Always backup important data first
4. **Test in non-production** - Validate scripts in test environment
5. **Monitor thin pools** - Watch data_percent and metadata_percent
6. **Log rotation** - Ensure proper log rotation is configured

## License

These scripts are provided as-is for educational and practical purposes. Use at your own risk.
