# network-monitor.sh - Continuous Network Monitoring

A continuous network monitoring script designed to work with Proxmox systems. Automatically detects network connectivity issues and calls the network fix script when problems are detected.

## Overview

The `network-monitor.sh` script provides:

- **Continuous monitoring** of network connectivity
- **Automatic problem detection** with configurable failure thresholds
- **Integration with fix-network.sh** for automatic repairs
- **Flexible operation modes** (continuous monitoring or single checks)
- **Comprehensive logging** with activity tracking
- **Systemd service support** for background operation

## Quick Start

```bash
# Start continuous monitoring (default)
sudo network-monitor

# Start monitoring while keeping network offloading enabled
sudo network-monitor --no-disable-offloading monitor

# Perform single connectivity check (for cron)
sudo network-monitor check

# Single check while keeping offloading enabled
sudo network-monitor --keep-offloading check

# View recent log entries
network-monitor status

# Show help
./network-monitor.sh help
```

## Operation Modes

### 1. Continuous Monitoring (Default)
```bash
sudo network-monitor
# or
sudo ./network-monitor.sh monitor
```
- Runs continuously in foreground
- Tests connectivity every 5 minutes
- Requires 2 consecutive failures before attempting fix
- Suitable for systemd service operation

### 2. Single Check Mode
```bash
sudo network-monitor check
# or
sudo ./network-monitor.sh check
```
- Performs one connectivity test
- Attempts fix immediately if connectivity fails
- Returns exit code for script integration
- Ideal for cron job usage

### 3. Status Mode
```bash
network-monitor status
# or
./network-monitor.sh status
```
- Shows recent log entries
- No root privileges required
- Useful for checking monitoring activity

## Configuration

### Configurable Variables
Edit these variables at the top of the script:

```bash
LOG_FILE="/var/log/network-monitor.log"    # Log file location
PING_TARGET="8.8.8.8"                     # Connectivity test target
PING_TIMEOUT=5                             # Ping timeout (seconds)
CHECK_INTERVAL=300                         # Check interval (5 minutes)
MAX_FAILURES=2                             # Failures before attempting fix
FIX_SCRIPT="/usr/local/bin/fix-network.sh" # Network fix script path
```

### Custom Configuration Examples

#### Different Check Intervals
```bash
CHECK_INTERVAL=60    # Check every minute
CHECK_INTERVAL=900   # Check every 15 minutes
CHECK_INTERVAL=1800  # Check every 30 minutes
```

#### Different Ping Targets
```bash
PING_TARGET="1.1.1.1"        # Cloudflare DNS
PING_TARGET="208.67.222.222"  # OpenDNS
PING_TARGET="192.168.1.1"     # Local gateway
```

#### Failure Thresholds
```bash
MAX_FAILURES=1   # Fix immediately on first failure
MAX_FAILURES=3   # Require 3 failures before fixing
MAX_FAILURES=5   # More conservative approach
```

## Integration Methods

### Systemd Service (Recommended)
The installer sets up a systemd service for continuous monitoring:

```bash
# Service management
sudo systemctl start network-fix.service
sudo systemctl stop network-fix.service
sudo systemctl restart network-fix.service
sudo systemctl status network-fix.service

# Enable/disable automatic startup
sudo systemctl enable network-fix.service
sudo systemctl disable network-fix.service

# View service logs
sudo journalctl -u network-fix.service -f
```

### Cron Job Integration
For periodic checks instead of continuous monitoring:

```bash
# Add to root's crontab
sudo crontab -e

# Check every 5 minutes
*/5 * * * * /usr/local/bin/network-monitor check >/dev/null 2>&1

# Check every 10 minutes with logging
*/10 * * * * /usr/local/bin/network-monitor check >> /var/log/cron-network.log 2>&1
```

### Manual Integration
```bash
#!/bin/bash
# Custom monitoring script
while true; do
    if ! /usr/local/bin/network-monitor check; then
        echo "Network issue detected at $(date)" >> /var/log/custom-monitor.log
        # Additional custom actions here
    fi
    sleep 300  # 5 minutes
done
```

## How It Works

### Monitoring Loop
1. **Connectivity test**: Ping configured target
2. **Result evaluation**: Track success/failure
3. **Failure counting**: Increment counter on failure
4. **Threshold checking**: Compare against MAX_FAILURES
5. **Fix triggering**: Call fix script if threshold reached
6. **Status logging**: Record all activity
7. **Sleep cycle**: Wait for next check interval

### Failure Detection Logic
```
Failure Counter Logic:
- Success: Reset failure counter to 0
- Failure: Increment failure counter
- Threshold: If counter >= MAX_FAILURES, attempt fix
- Recovery: Reset counter after successful fix
```

### Network Fix Integration
When failures reach the threshold:
1. **Log warning**: Record fix attempt
2. **Call fix script**: Execute `/usr/local/bin/fix-network.sh`
3. **Monitor result**: Check fix script exit code
4. **Log outcome**: Record success or failure
5. **Reset counter**: Reset failure count after fix
6. **Send notification**: Log notification message

## Logging and Monitoring

### Log File Format
```
[2024-01-01 10:00:00] [INFO] Network monitoring started (PID: 12345)
[2024-01-01 10:05:00] [DEBUG] Network connectivity OK
[2024-01-01 10:10:00] [WARN] Network connectivity failed (failure 1/2)
[2024-01-01 10:15:00] [ERROR] Network connectivity failed 2 consecutive times
[2024-01-01 10:15:01] [INFO] Network fix attempted, will verify on next check
[2024-01-01 10:20:00] [INFO] Network connectivity restored after 2 failures
```

### Log Analysis
```bash
# View real-time monitoring
tail -f /var/log/network-monitor.log

# Count recent failures
grep -c "connectivity failed" /var/log/network-monitor.log | tail -100

# Check fix attempts
grep "fix attempted" /var/log/network-monitor.log

# Monitor restoration
grep "connectivity restored" /var/log/network-monitor.log
```

### Log Levels
- **INFO**: Normal operations, monitoring start/stop, fix results
- **DEBUG**: Successful connectivity tests (can be verbose)
- **WARN**: Failed connectivity tests, fix attempts
- **ERROR**: Multiple consecutive failures, fix failures
- **NOTIFY**: Important status changes, recovery events

## Exit Codes

The script uses standard exit codes for integration:

```bash
0  # Success - connectivity OK or fix successful
1  # Failure - connectivity failed or fix failed
2  # Error - invalid arguments or system error
```

### Using Exit Codes
```bash
# Simple connectivity test
if network-monitor check; then
    echo "Network is OK"
else
    echo "Network has issues"
fi

# In scripts
/usr/local/bin/network-monitor check
case $? in
    0) echo "Network OK" ;;
    1) echo "Network failed" ;;
    *) echo "Monitor error" ;;
esac
```

## Advanced Usage

### Custom Notification Integration
Modify the `send_notification()` function for custom notifications:

```bash
send_notification() {
    local message="$1"
    log_message "NOTIFY" "$message"
    
    # Add custom notifications here:
    # echo "$message" | mail -s "Network Alert" admin@example.com
    # curl -X POST "https://hooks.slack.com/..." -d "{\"text\":\"$message\"}"
    # /usr/local/bin/custom-alert.sh "$message"
}
```

### Multiple Target Monitoring
For monitoring multiple connectivity targets:

```bash
# Create multiple monitor instances with different configs
cp network-monitor.sh network-monitor-dns.sh
cp network-monitor.sh network-monitor-gateway.sh

# Edit each with different PING_TARGET values
# Run as separate services or cron jobs
```

### Performance Monitoring
```bash
# Monitor response times
ping_with_time() {
    local target="$1"
    local timeout="$2"
    local start_time=$(date +%s.%N)
    
    if ping -c 1 -W "$timeout" "$target" &>/dev/null; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        log_message "DEBUG" "Ping successful in ${duration}s"
        return 0
    else
        log_message "WARN" "Ping failed after ${timeout}s timeout"
        return 1
    fi
}
```

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Monitor script needs root for network fixes
sudo network-monitor
```

**2. Fix Script Not Found**
```bash
# Verify fix script location
ls -la /usr/local/bin/fix-network.sh

# Update FIX_SCRIPT variable if needed
FIX_SCRIPT="/path/to/fix-network.sh"
```

**3. High CPU Usage in Debug Mode**
```bash
# Reduce debug logging frequency
CHECK_INTERVAL=600  # Check every 10 minutes instead of 5
```

**4. Log File Growth**
```bash
# Set up log rotation
sudo nano /etc/logrotate.d/network-monitor

# Add:
/var/log/network-monitor.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
```

### Service Troubleshooting

```bash
# Check service status
sudo systemctl status network-fix.service

# View service logs
sudo journalctl -u network-fix.service --since="1 hour ago"

# Debug service startup
sudo systemctl stop network-fix.service
sudo /usr/local/bin/network-monitor monitor  # Run manually
```

## Best Practices

### Production Deployment
1. **Test thoroughly**: Validate in test environment
2. **Configure appropriately**: Set suitable check intervals and thresholds
3. **Monitor logs**: Set up log rotation and monitoring
4. **Document configuration**: Keep track of custom settings

### Performance Considerations
1. **Check interval**: Balance responsiveness vs. resource usage
2. **Failure threshold**: Prevent false positives from temporary issues
3. **Log verbosity**: Reduce DEBUG logging in production
4. **Target selection**: Choose reliable, fast-responding ping targets

### Maintenance
1. **Log rotation**: Prevent log files from growing too large
2. **Monitoring health**: Monitor the monitor script itself
3. **Update coordination**: Keep synchronized with fix-network.sh
4. **Configuration backup**: Save custom configurations

The `network-monitor.sh` script provides robust, automated network monitoring that integrates seamlessly with the Proxmox network fix tools for a complete connectivity management solution.
