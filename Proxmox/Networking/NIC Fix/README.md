# Proxmox Network Interface Restart Script

This repository contains a script to automatically fix network connectivity issues in Proxmox by restarting the network interface - simulating the "unplug and plug back in" fix.

## Problem

Proxmox occasionally loses internet connectivity, requiring manual intervention to unplug and plug back in the ethernet cable. This script automates that process by restarting the network interface.

## Files

- `fix-network.sh` - Main script to restart network interface
- `network-monitor.sh` - Continuous monitoring script (optional)
- `network-fix.service` - Systemd service file for monitoring (optional)

## Automated Installation (Recommended)

**One-command installation:**
```bash
# Download and run the automated installer
curl -sSL https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/Networking/NIC%20Fix/install.sh | sudo bash
```

**Or download first then install:**
```bash
# Download the installer
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/Networking/NIC%20Fix/install.sh

# Make it executable and run
chmod +x install.sh
sudo ./install.sh
```

This automated installer will:
- Install all scripts to `/usr/local/bin/`
- Create systemd service files
- Set up logging
- Create convenient command aliases
- Test the installation

## Manual Installation

### Option 1: Clone Repository (Get Everything)
```bash
# Clone the entire repository
git clone https://github.com/TrueBankai416/Scripts.git
cd Scripts/Proxmox/Networking/NIC\ Fix/

# Run the installer
chmod +x install.sh
sudo ./install.sh
```

### Option 2: Download All Files
```bash
# Create temporary directory
mkdir -p ~/proxmox-network-fix
cd ~/proxmox-network-fix

# Download all files
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/Networking/NIC%20Fix/fix-network.sh
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/Networking/NIC%20Fix/network-monitor.sh
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/Networking/NIC%20Fix/network-fix.service
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/Networking/NIC%20Fix/install.sh

# Run the installer
chmod +x install.sh
sudo ./install.sh
```

### Option 3: Individual Script Setup (Quick Start)
```bash
# Download just the main script
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/Networking/NIC%20Fix/fix-network.sh

# Make it executable
chmod +x fix-network.sh

# Move to system location (optional)
sudo mv fix-network.sh /usr/local/bin/fix-network
```

## Usage

**After installation, run the script:**
```bash
# Run with auto-detection of primary interface
sudo fix-network

# Or specify a specific interface
sudo fix-network eth0

# If using manual installation without moving to /usr/local/bin
sudo ./fix-network.sh
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

### Automated Monitoring (Option 1: Systemd Service - Recommended)

If you used the automated installer, the systemd service is already configured:

```bash
# Enable and start the monitoring service
sudo systemctl enable network-fix.service
sudo systemctl start network-fix.service

# Check service status
sudo systemctl status network-fix.service

# View service logs
sudo journalctl -u network-fix.service -f
```

### Automated Monitoring (Option 2: Cron Job)

For simpler periodic checks, add to root's crontab:

```bash
# Edit crontab
sudo crontab -e

# Add this line (check every 5 minutes)
*/5 * * * * /usr/local/bin/network-monitor check > /dev/null 2>&1
```

Note: If you used the automated installer, the `network-monitor` command is already available.

## Configuration

You can modify these variables at the top of the script:

- `LOG_FILE`: Location of log file (default: `/var/log/network-fix.log`)
- `MAX_RETRIES`: Number of retry attempts (default: 3)
- `RETRY_DELAY`: Delay between retries in seconds (default: 5)
- `PING_TARGET`: Host to ping for connectivity test (default: 8.8.8.8)
- `CONNECTIVITY_TIMEOUT`: Ping timeout in seconds (default: 5)

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

## License

This script is provided as-is for educational and practical purposes. Use at your own risk.
