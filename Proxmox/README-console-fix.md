# console-fix.sh - Proxmox Console Troubleshooting

A comprehensive diagnostic and repair tool for Proxmox console 500 errors and related web interface issues. Addresses SSL certificates, service problems, disk space issues, and console-specific components.

## Overview

The `console-fix.sh` script provides:

- **Console 500 error diagnosis** and automated fixes
- **Proxmox service health checking** and repair
- **SSL certificate management** and regeneration
- **Disk space analysis** and cleanup
- **File permission verification** and correction
- **Interactive and automated repair modes**

## Quick Start

```bash
# Interactive diagnosis and fix
sudo console-fix

# Automated fixes (minimal prompts)  
sudo console-fix fix

# Diagnosis only (no fixes)
sudo console-fix diagnose

# Show help
./console-fix.sh --help
```

## Common Console Issues Solved

### 1. HTTP 500 Errors
- **Internal server errors**: Web interface crashes and 500 responses
- **Service failures**: pveproxy, pvedaemon, or pvestatd not running
- **SSL certificate issues**: Expired or corrupted certificates
- **Disk space problems**: Full root filesystem preventing operations

### 2. Console Access Problems
- **VNC console failures**: Cannot access VM/container consoles
- **noVNC component issues**: Missing or corrupted noVNC files
- **Port binding problems**: Console ports not listening
- **WebSocket connection failures**: Browser-to-console communication issues

### 3. Service Dependencies
- **Cluster communication**: pve-cluster service issues
- **Statistics gathering**: pvestatd failures affecting monitoring
- **Firewall integration**: pve-firewall service problems
- **SPICE proxy**: spiceproxy service for enhanced console access

## Usage

### Interactive Mode (Default)
```bash
sudo console-fix
```

Provides guided troubleshooting:
1. **System overview**: Shows Proxmox version and system status
2. **Service checking**: Validates all Proxmox services
3. **Disk space analysis**: Checks for space-related issues
4. **SSL certificate verification**: Examines certificate validity
5. **Permission checking**: Verifies file and directory permissions
6. **Component analysis**: Tests console-specific components

### Automated Modes
```bash
# Automated fix mode
sudo console-fix fix

# Diagnosis only
sudo console-fix diagnose

# Test console access
sudo console-fix test
```

## Diagnostic Categories

### 1. System Overview
```
Proxmox Version: pve-manager/8.1.4/ec12ce92cadd750a
System uptime: 15 days, 4:30
Current disk usage:
/dev/sda1    50G   45G   2.8G  95% /     <-- CRITICAL
Memory usage: 8.2G / 16G (51%)
Load average: 0.15, 0.10, 0.08
```

### 2. Service Health Check
```
Checking Proxmox Services:
✓ pveproxy is running
✗ pvedaemon is not running      <-- PROBLEM FOUND
✓ pvestatd is running
✓ pve-cluster is running
✓ pve-firewall is running
✗ spiceproxy is not running     <-- PROBLEM FOUND

Failed services: pvedaemon, spiceproxy
```

### 3. Disk Space Analysis
```
Root filesystem usage: 95%      <-- CRITICAL
✗ Root filesystem is critically full (95%)

/var filesystem usage: 92%
✗ /var filesystem is critically full (92%)

Large log files found:
-rw-r--r-- 1 root root 2.1G Jan 15 10:00 /var/log/daemon.log
-rw-r--r-- 1 root root 1.8G Jan 14 09:30 /var/log/syslog
```

### 4. SSL Certificate Check
```
Checking SSL Certificates:
Certificate dates:
notBefore=Jan  1 00:00:00 2024 GMT
notAfter=Dec 31 23:59:59 2024 GMT
✓ SSL certificate is valid
✓ SSL private key is valid
```

### 5. File Permissions Check
```
Directory /etc/pve: owner=root:www-data, permissions=755
Directory /var/lib/pve-cluster: owner=root:www-data, permissions=755
Directory /var/log/pve: owner=root:root, permissions=755
✗ CRITICAL: Directory /var/tmp does not exist (required for console temp files)
```

## Fix Operations

### 1. Service Restart
**Problem**: Failed Proxmox services
**Solution**: Systematic service restart with dependency management

```bash
# Services restarted in order:
systemctl restart pvestatd      # Statistics daemon first
systemctl restart pvedaemon     # Main daemon second  
systemctl restart pveproxy      # Web proxy last

# Verification:
systemctl is-active pvestatd pvedaemon pveproxy
```

### 2. SSL Certificate Regeneration
**Problem**: Expired or corrupted SSL certificates
**Solution**: Generate new self-signed certificates

```bash
# Backup existing certificates
cp /etc/pve/local/pve-ssl.pem /var/backups/console-fix/
cp /etc/pve/local/pve-ssl.key /var/backups/console-fix/

# Generate new certificates
pvecm updatecerts --force       # Regenerate certificates
systemctl restart pveproxy      # Apply new certificates
```

### 3. Disk Space Cleanup
**Problem**: Critical disk space shortage
**Solution**: Emergency cleanup of logs and temporary files

```bash
# Emergency cleanup operations:
find /var/log -name "*.gz" -mtime +7 -delete     # Old compressed logs
journalctl --vacuum-time=3d                      # Systemd journal
apt clean                                        # Package cache
find /tmp -type f -mtime +1 -delete             # Temporary files
find /var/tmp -type f -mtime +1 -delete         # Var temporary files
```

### 4. Permission Correction
**Problem**: Incorrect file or directory permissions
**Solution**: Restore proper permissions for Proxmox operation

```bash
# Critical permission fixes:
mkdir -p /var/tmp                        # Ensure temp directory exists
chmod 1777 /var/tmp                      # Set sticky bit
chown root:www-data /etc/pve             # Correct ownership
chmod 755 /var/lib/pve-cluster          # Proper cluster permissions
```

### 5. Console Component Verification
**Problem**: Missing or corrupted console components
**Solution**: Verify and repair noVNC and console infrastructure

```bash
# Component checks:
ls -la /usr/share/novnc/                 # Verify noVNC installation
netstat -tlnp | grep :8006              # Check web interface port
netstat -tlnp | grep :59                # Check VNC port range
systemctl status spiceproxy             # Verify SPICE proxy
```

## Interactive Workflow

### Step 1: Initial Assessment
```
=== Proxmox System Overview ===
[Shows system status and identifies immediate issues]

=== Checking Proxmox Services ===
✓ 4 services running normally
✗ 2 services require attention
```

### Step 2: Problem Identification
```
=== Checking Disk Space ===
✗ Root filesystem is critically full (95%)

=== Checking SSL Certificates ===
✓ SSL certificates are valid

=== Checking File Permissions ===
✗ CRITICAL: Directory /var/tmp does not exist
```

### Step 3: Fix Confirmation
```
Restart pvedaemon service? [y/N]: y
Restarting pvedaemon...
✓ pvedaemon restarted successfully

Clean up disk space? [y/N]: y
Cleaning up disk space...
✓ Disk cleanup completed (2.1GB freed)

Fix file permissions? [y/N]: y
Creating /var/tmp with correct permissions...
✓ File permissions corrected
```

### Step 4: Verification
```
=== Testing Console Access ===
Testing Proxmox web interface connectivity...
✓ Port 8006 is listening
✓ HTTPS response received
✓ Console infrastructure appears functional
```

## Configuration

### Configurable Variables
```bash
LOG_FILE="/var/log/console-fix.log"              # Log file location
BACKUP_DIR="/var/backups/console-fix"            # Backup directory
```

### Environment Variables
```bash
# Skip interactive prompts
export CONSOLE_FIX_AUTO=true

# Custom backup location
export BACKUP_DIR="/backup/console-fix-backups"
```

## Advanced Features

### Comprehensive Testing
**Console Access Test**: Verifies complete console pipeline
```bash
# Test sequence:
1. Check web interface port (8006)
2. Verify SSL certificate response
3. Test VNC port availability  
4. Check noVNC component integrity
5. Validate service dependencies
```

### Backup and Recovery
**Automatic Backups**: Creates backups before destructive operations
```bash
# Backed up before changes:
- SSL certificates → /var/backups/console-fix/
- Configuration files → /var/backups/console-fix/
- Service configurations → /var/backups/console-fix/

# Recovery procedure:
sudo cp /var/backups/console-fix/pve-ssl.pem.backup.* /etc/pve/local/pve-ssl.pem
```

### Log Analysis Integration
**Recent Log Checking**: Analyzes recent errors
```bash
# Logs analyzed:
journalctl -u pvedaemon --since="10 minutes ago"     # Daemon errors
journalctl -u pveproxy --since="10 minutes ago"      # Proxy errors  
journalctl --since="10 minutes ago" | grep console   # Console-specific errors
```

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Must run as root for system repairs
sudo ./console-fix.sh
```

**2. Service Start Failures**
```bash
# Check detailed service status
sudo systemctl status pvedaemon -l

# Check service logs
sudo journalctl -u pvedaemon --since="1 hour ago"

# Check for port conflicts
sudo netstat -tlnp | grep 8006
```

**3. SSL Certificate Issues**
```bash
# Manual certificate verification
openssl x509 -in /etc/pve/local/pve-ssl.pem -noout -dates

# Test certificate with curl
curl -k https://localhost:8006

# Check certificate permissions
ls -la /etc/pve/local/pve-ssl.*
```

**4. Disk Space Problems**
```bash
# Emergency space cleanup
sudo journalctl --vacuum-size=100M
sudo apt clean
sudo find /tmp -type f -delete
```

### Advanced Troubleshooting

#### Cluster Issues
```bash
# Check cluster status
sudo pvecm status

# Verify cluster communication
sudo pvecm nodes

# Check cluster configuration
sudo cat /etc/pve/corosync.conf
```

#### Network Configuration
```bash
# Check listening ports
sudo ss -tlnp | grep -E ':(8006|59[0-9][0-9])'

# Verify firewall rules
sudo iptables -L | grep 8006

# Check network connectivity
curl -I https://localhost:8006
```

## Integration with Other Tools

### Pre-Console-Fix Analysis
```bash
# Check storage first (console issues often storage-related)
sudo storage-analyzer
sudo console-fix
```

### Post-Fix Verification
```bash
# Verify fix effectiveness
sudo console-fix test

# Check web interface
curl -k https://your-proxmox-server:8006
```

### Monitoring Integration
```bash
#!/bin/bash
# Console health check script
/usr/local/bin/console-fix diagnose

if [ $? -ne 0 ]; then
    echo "Console issues detected, attempting automatic fix..."
    /usr/local/bin/console-fix fix
    
    # Send alert if fix fails
    if [ $? -ne 0 ]; then
        echo "Console fix failed - manual intervention required" | \
        mail -s "Proxmox Console Alert" admin@example.com
    fi
fi
```

## Automation and Scheduling

### Cron Integration
```bash
# Add to root's crontab
sudo crontab -e

# Daily console health check
0 6 * * * /usr/local/bin/console-fix diagnose >/dev/null 2>&1

# Weekly automated fix attempt
0 3 * * 0 /usr/local/bin/console-fix fix >> /var/log/weekly-console-fix.log 2>&1
```

### Service Health Monitoring
```bash
#!/bin/bash
# Continuous console monitoring
while true; do
    if ! curl -k -s https://localhost:8006 >/dev/null; then
        /usr/local/bin/console-fix fix
    fi
    sleep 300  # Check every 5 minutes
done
```

## Best Practices

### Preventive Maintenance
1. **Regular disk cleanup**: Prevent space-related console issues
2. **Certificate monitoring**: Track SSL certificate expiration
3. **Service health checks**: Monitor Proxmox services proactively
4. **Log rotation**: Configure proper log rotation to prevent space issues

### Emergency Procedures
1. **Quick diagnosis**: Use `console-fix diagnose` for rapid assessment
2. **Service recovery**: Restart services in proper dependency order
3. **Space emergency**: Priority cleanup of logs and temp files
4. **Certificate regeneration**: Quick SSL certificate renewal

### Production Deployment
1. **Test thoroughly**: Validate all fixes in test environment
2. **Schedule maintenance**: Run fixes during maintenance windows
3. **Monitor results**: Track fix effectiveness over time
4. **Document procedures**: Keep records of common issues and solutions

The `console-fix.sh` script provides comprehensive diagnosis and repair capabilities for Proxmox console issues, ensuring reliable web interface and console access.
