# fix-network.sh - Network Interface Restart Script

A comprehensive network troubleshooting and repair script designed specifically for Proxmox systems. Automatically detects and fixes network connectivity issues, including hardware-level problems with Intel e1000e controllers.

## Overview

The `fix-network.sh` script addresses the common Proxmox issue where network connectivity is lost and requires manual intervention (like unplugging/plugging network cables). It provides:

- **Automatic interface detection** with Proxmox bridge support
- **Hardware hang detection** for Intel e1000e controllers  
- **Driver-aware reset strategies** for different network controllers
- **Comprehensive logging** and diagnostics
- **Safe operation** with connectivity verification
- **Bridge member handling** for complex Proxmox network setups

## Quick Start

```bash
# Auto-detect and fix primary interface
sudo fix-network

# Fix specific interface
sudo fix-network eth0
sudo fix-network enp0s3

# Show help
./fix-network.sh --help
```

## Features

### Automatic Detection
- **Primary interface detection**: Finds the interface used for default route
- **Bridge interface support**: Handles Proxmox bridge interfaces (vmbr0, etc.)
- **Physical member identification**: Restarts underlying physical interfaces
- **Virtual interface filtering**: Skips virtual/container interfaces

### Hardware Support
- **Intel e1000e hang detection**: Identifies hardware hangs from kernel logs
- **Driver identification**: Determines network controller driver
- **Hardware-level resets**: Module reload and PCI resets when needed
- **Proxmox forum workarounds**: Applies known fixes for e1000e issues

### Safety Features
- **Connectivity testing**: Verifies network before and after restart
- **Interactive mode**: Prompts before restarting working interfaces
- **Retry logic**: Multiple attempts with progressive delays
- **Comprehensive logging**: Detailed activity logs for troubleshooting

## Usage

### Basic Usage
```bash
# Most common usage - auto-detect and fix
sudo ./fix-network.sh

# Specify interface explicitly
sudo ./fix-network.sh eth0
sudo ./fix-network.sh enp0s3
sudo ./fix-network.sh vmbr0
```

### Advanced Usage
```bash
# Run with specific interface and check logs
sudo ./fix-network.sh eth0 && tail -f /var/log/network-fix.log

# Test connectivity only (no restart)
ping -c 1 8.8.8.8 || sudo ./fix-network.sh
```

## Configuration

### Configurable Variables
Edit these variables at the top of the script:

```bash
LOG_FILE="/var/log/network-fix.log"    # Log file location
MAX_RETRIES=3                          # Number of retry attempts
RETRY_DELAY=5                          # Delay between retries (seconds)
PING_TARGET="8.8.8.8"                 # Connectivity test target
CONNECTIVITY_TIMEOUT=5                 # Ping timeout (seconds)
```

### Custom Ping Targets
```bash
# Change ping target for different networks
PING_TARGET="1.1.1.1"        # Cloudflare DNS
PING_TARGET="208.67.222.222"  # OpenDNS
PING_TARGET="192.168.1.1"     # Local gateway
```

## How It Works

### Detection Process
1. **Interface identification**: Finds primary network interface from routing table
2. **Bridge detection**: Checks if interface is a Proxmox bridge
3. **Member enumeration**: Lists physical interfaces attached to bridge
4. **Driver identification**: Determines network controller driver type
5. **Hardware hang checking**: Scans kernel logs for hang indicators

### Reset Strategies

#### Standard Software Reset
For most interfaces:
1. Bring interface down with `ip link set down`
2. Wait for settling
3. Bring interface up with `ip link set up`
4. Test connectivity

#### Hardware Reset (Intel e1000e)
For problematic Intel controllers:
1. **Feature workaround**: Disable problematic ethtool features
2. **Module reload**: Remove and reload e1000e driver
3. **PCI reset**: Hardware-level reset via sysfs
4. **Persistent configuration**: Create systemd service for boot-time fixes

#### Bridge Interface Handling
For Proxmox bridges:
1. **Member identification**: Find physical interfaces attached to bridge
2. **Virtual interface filtering**: Skip VM/container interfaces
3. **Sequential restart**: Restart physical members first
4. **Bridge restart**: Restart bridge interface last
5. **Stabilization wait**: Allow time for proper initialization

### Intel e1000e Workarounds

The script includes specific fixes for Intel e1000e hardware hangs:

#### Feature Disabling
```bash
# Disabled features known to cause issues
ethtool -K interface gso off
ethtool -K interface gro off
ethtool -K interface tso off
ethtool -K interface tx off
ethtool -K interface rx off
```

#### Persistent Configuration
Creates systemd service for boot-time feature disabling:
```bash
/etc/systemd/system/ethtool-workaround-[interface].service
```

## Proxmox Integration

### Bridge Support
The script provides special handling for Proxmox bridge interfaces:
- **vmbr0, vmbr1, etc.**: Common Proxmox bridge naming
- **Physical member restart**: Fixes underlying hardware issues
- **VM interface preservation**: Doesn't interfere with running VMs

### Common Proxmox Scenarios
1. **Single interface with bridge**: Physical interface + vmbr0
2. **Multiple interfaces**: Multiple physical + multiple bridges  
3. **Bond interfaces**: Bonded physical + bridge
4. **VLAN interfaces**: Tagged interfaces + bridges

## Logging and Diagnostics

### Log File Format
```
[2024-01-01 10:00:00] [INFO] Network restart initiated for eth0
[2024-01-01 10:00:01] [INFO] Interface eth0 uses driver: e1000e
[2024-01-01 10:00:02] [WARN] Hardware hang detected for eth0
[2024-01-01 10:00:05] [INFO] Hardware reset completed successfully
```

### Log Analysis
```bash
# View recent activity
tail -f /var/log/network-fix.log

# Search for errors
grep ERROR /var/log/network-fix.log

# Check for hardware hangs
grep "hardware hang" /var/log/network-fix.log

# Monitor in real-time during fix
tail -f /var/log/network-fix.log &
sudo ./fix-network.sh
```

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Must run as root
sudo ./fix-network.sh
```

**2. Interface Not Found**
```bash
# List available interfaces
ip link show

# Check interface name
sudo ./fix-network.sh [correct-interface-name]
```

**3. Hardware Hangs Persist**
```bash
# Check for kernel messages
dmesg | grep -i "hardware unit hang"

# Manual module reload
sudo modprobe -r e1000e
sudo modprobe e1000e

# Check if workaround service is enabled
systemctl status ethtool-workaround-*
```

**4. Bridge Issues**
```bash
# Check bridge configuration
brctl show

# Verify bridge members
ls /sys/class/net/vmbr0/brif/
```

### Advanced Diagnostics

#### Network Controller Information
```bash
# Show PCI network devices
lspci | grep -i ethernet

# Show driver information  
lspci -k | grep -A 3 -i ethernet

# Check ethtool features
ethtool -k eth0
```

#### Interface Status
```bash
# Detailed interface information
ip addr show eth0

# Interface statistics
ip -s link show eth0

# Driver module information
modinfo e1000e
```

## Integration with Monitoring

### Cron Integration
```bash
# Add to crontab for periodic checking
*/5 * * * * /usr/local/bin/fix-network >/dev/null 2>&1
```

### Systemd Service Integration
Use with `network-monitor.sh` for continuous monitoring:
```bash
# The network-monitor.sh script calls fix-network.sh automatically
systemctl enable network-fix.service
```

### Custom Scripts
```bash
#!/bin/bash
# Custom wrapper script
if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    /usr/local/bin/fix-network
    # Send notification, update monitoring, etc.
fi
```

## Best Practices

### Regular Maintenance
1. **Monitor logs**: Check `/var/log/network-fix.log` regularly
2. **Update drivers**: Keep network drivers current
3. **Kernel updates**: Test after kernel updates
4. **Hardware monitoring**: Watch for hardware hang patterns

### Production Usage
1. **Test thoroughly**: Validate in test environment first
2. **Document interfaces**: Know your network configuration
3. **Monitor connectivity**: Use with automated monitoring
4. **Schedule wisely**: Run during maintenance windows if possible

### Security Considerations
1. **Root access**: Script requires root privileges
2. **Network exposure**: Temporary connectivity loss during restart
3. **Log security**: Protect log files from unauthorized access
4. **Update source**: Only use trusted script sources

The `fix-network.sh` script provides a robust solution for the common Proxmox network connectivity issues, with special attention to Intel e1000e hardware problems and Proxmox bridge configurations.
