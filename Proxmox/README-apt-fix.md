# apt-fix.sh - APT Repository Fix

A comprehensive APT repository diagnostic and repair tool designed for Proxmox and Debian-based systems. Automatically detects and fixes common APT repository issues including broken local repositories, duplicate configurations, and corrupted cache.

## Overview

The `apt-fix.sh` script provides:

- **Automatic issue detection** for broken and misconfigured repositories
- **Safe repository fixes** with configuration backups
- **Duplicate repository resolution** with intelligent handling
- **APT cache cleanup** and refresh functionality
- **Comprehensive logging** of all operations
- **Interactive and automatic modes** for different use cases

## Quick Start

```bash
# Interactive mode (default)
sudo apt-fix

# Check repository health only
sudo apt-fix check

# Automatically fix all detected issues
sudo apt-fix fix

# Test APT functionality
sudo apt-fix test

# Show help
./apt-fix.sh --help
```

## Common Issues Resolved

### 1. Broken Local Repositories
- **File URL errors**: Fixes `file://` repositories with missing Release files
- **Missing directories**: Identifies and disables repositories pointing to non-existent paths
- **CUDA repository issues**: Handles broken local CUDA repositories from installations
- **Safe disabling**: Comments out broken entries rather than deleting them

### 2. Duplicate Repository Configurations
- **Multiple definitions**: Fixes repositories defined in both `sources.list` and `sources.list.d/`
- **Intelligent resolution**: Keeps specific configurations, disables general duplicates
- **Preference handling**: Prioritizes `sources.list.d/` files over main `sources.list`
- **Warning elimination**: Removes "configured multiple times" warnings

### 3. APT Cache Issues
- **Corrupted cache**: Cleans and rebuilds APT cache
- **Partial downloads**: Removes incomplete package downloads
- **Index corruption**: Refreshes package indexes after cleanup
- **Lock file issues**: Handles common APT lock conflicts

### 4. Repository Configuration Errors
- **Syntax errors**: Identifies malformed repository entries
- **Invalid URLs**: Detects unreachable or incorrect repository URLs
- **GPG key issues**: Reports missing or invalid repository keys
- **Network problems**: Identifies connectivity-related repository failures

## Usage Modes

### Interactive Mode (Default)
```bash
sudo apt-fix
# or
sudo ./apt-fix.sh interactive
```

Presents menu with options:
1. Check APT repository health
2. Fix broken local repositories
3. Fix duplicate repository configurations
4. Clean APT cache and refresh
5. Run complete APT diagnosis and repair
6. Test APT functionality only
7. Exit

### Automatic Mode
```bash
# Complete automatic repair
sudo apt-fix fix

# Individual operations
sudo apt-fix check          # Health check only
sudo apt-fix test           # Functionality test only
```

### Check Mode
```bash
# Comprehensive repository health check
sudo apt-fix check
```

Shows:
- Current APT update status
- Broken local repositories
- Duplicate configurations
- GPG key issues
- Network connectivity problems

## Detailed Operations

### Repository Health Check
```bash
# Example output:
Testing current APT update...
✓ APT update completed successfully

Checking for broken local repositories...
✗ Broken local repository: /var/cuda-repo-ubuntu2404-12-6-local
  File not found: /var/cuda-repo-ubuntu2404-12-6-local/Release

Checking for duplicate configurations... 
⚠ Duplicate repository configurations detected
  Duplicate: deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
  Found in: /etc/apt/sources.list:16 and /etc/apt/sources.list.d/pve-no-subscription.list:2
```

### Broken Repository Fixing
```bash
# Operations performed:
# 1. Identifies broken file:// repositories
# 2. Comments out broken entries with descriptive comments
# 3. Preserves original configuration for recovery

# Example fix:
# Before: deb file:/var/cuda-repo-ubuntu2404-12-6-local /
# After:  # DISABLED by apt-fix.sh - broken local repository: deb file:/var/cuda-repo-ubuntu2404-12-6-local /
```

### Duplicate Resolution Strategy
```bash
# Strategy applied:
# 1. Keep repositories in /etc/apt/sources.list.d/ (more specific)
# 2. Comment out duplicates in /etc/apt/sources.list (general)
# 3. Preserve original functionality

# Example:
# /etc/apt/sources.list.d/pve-no-subscription.list:
#   deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
# /etc/apt/sources.list (after fix):
#   # DISABLED by apt-fix.sh - duplicate of sources.list.d entry: deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
```

### APT Cache Cleanup
```bash
# Operations performed:
apt clean                           # Remove cached packages
rm -rf /var/lib/apt/lists/partial/* # Remove partial downloads
apt update                          # Refresh package lists

# Status reported:
✓ APT cache cleaned
✓ Partial downloads removed  
✓ Package lists updated successfully
```

## Safety Features

### Automatic Backups
All configuration files are backed up before modifications:
```bash
# Backup locations:
/var/backups/apt-fix/sources.list.backup.20240115_143022
/var/backups/apt-fix/sources.list.d.backup.20240115_143022.tar.gz
/var/backups/apt-fix/preferences.backup.20240115_143022
```

### Non-Destructive Fixes
- **Comments rather than deletes**: Broken entries are commented out, not removed
- **Reversible changes**: All modifications can be easily undone
- **Descriptive comments**: Each disabled entry includes reason for disabling
- **Original preservation**: Original configuration remains intact in comments

### User Confirmation
Major operations require user confirmation:
```bash
Remove or comment out broken local repositories? [y/N]: y
Automatically resolve duplicate repository configurations? [y/N]: y
Clean APT cache and refresh package lists? [y/N]: y
```

## Configuration

### Configurable Variables
Edit these variables at the top of the script:

```bash
LOG_FILE="/var/log/apt-fix.log"              # Log file location
BACKUP_DIR="/var/backups/apt-fix"            # Backup directory location
```

### Custom Configuration Examples
```bash
# Different backup location
BACKUP_DIR="/backup/apt-configs"

# Custom log location
LOG_FILE="/var/log/proxmox/apt-fix.log"
```

## Logging and Reporting

### Log File Format
```
[2024-01-15 14:30:00] [INFO] APT fix script started
[2024-01-15 14:30:15] [ERROR] Broken local repository found: /var/cuda-repo-ubuntu2404-12-6-local
[2024-01-15 14:30:30] [INFO] Commented out broken repository in sources.list: /var/cuda-repo-ubuntu2404-12-6-local
[2024-01-15 14:30:45] [WARN] Duplicate repository configurations detected
[2024-01-15 14:31:00] [INFO] Fixed 1 duplicate repositories
[2024-01-15 14:31:15] [INFO] APT update completed successfully
[2024-01-15 14:31:30] [INFO] APT fix script completed
```

### Repair Report
Generated at `/tmp/apt-fix-report.txt`:
```
Proxmox APT Repository Fix Report
Generated: 2024-01-15 14:35:00
===============================

SYSTEM INFORMATION:
System: Proxmox Virtual Environment
pve-manager/8.1.3/b46aac3b (running kernel: 6.5.11-7-pve)
APT Version: apt 2.6.1 (amd64)

REPAIR ACTIONS PERFORMED:
- Backed up /etc/apt/sources.list
- Backed up /etc/apt/sources.list.d/
- Commented out broken repository in sources.list: /var/cuda-repo-ubuntu2404-12-6-local
- Fixed 1 duplicate repositories
- APT cache cleaned successfully
- APT update completed successfully

CURRENT APT STATUS:
Latest APT update test:
Hit:1 http://ftp.debian.org/debian bookworm InRelease
Hit:2 http://security.debian.org/debian-security bookworm-security InRelease
Hit:3 http://ftp.debian.org/debian bookworm-updates InRelease
Hit:4 http://download.proxmox.com/debian/pve bookworm InRelease
Hit:5 https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64 InRelease
Hit:6 https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64 InRelease
Reading package lists... Done

REPOSITORY CONFIGURATION:
Active repositories in /etc/apt/sources.list:
deb http://ftp.debian.org/debian bookworm main contrib
deb http://ftp.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib

Active repositories in /etc/apt/sources.list.d/:
/etc/apt/sources.list.d/pve-no-subscription.list:deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription

BACKUP LOCATION:
Configuration backups saved to: /var/backups/apt-fix
-rw-r--r-- 1 root root 1234 Jan 15 14:30 sources.list.backup.20240115_143022
-rw-r--r-- 1 root root 5678 Jan 15 14:30 sources.list.d.backup.20240115_143022.tar.gz

RECOMMENDATIONS:
1. Monitor APT operations for any remaining issues
2. Run 'apt update' periodically to ensure continued functionality
3. Keep backups until system stability is confirmed
4. Consider removing unused repository entries
```

## Troubleshooting

### Common Issues

**1. APT Update Still Failing**
```bash
# Check for remaining issues
sudo apt-fix check

# View detailed error output
sudo apt update

# Check log for clues
tail -20 /var/log/apt-fix.log
```

**2. Permission Denied Errors**
```bash
# Must run as root for system modifications
sudo ./apt-fix.sh

# Check file permissions
ls -la /etc/apt/sources.list*
```

**3. Backup Directory Issues**
```bash
# Create backup directory manually
sudo mkdir -p /var/backups/apt-fix
sudo chmod 755 /var/backups/apt-fix
```

**4. Network Connectivity Problems**
```bash
# Test basic connectivity
ping -c 4 8.8.8.8

# Test repository connectivity
curl -I http://ftp.debian.org/debian/

# Check DNS resolution
nslookup ftp.debian.org
```

**5. GPG Key Errors**
```bash
# Update GPG keys (common fix)
sudo apt-key adv --refresh-keys --keyserver keyserver.ubuntu.com

# For Proxmox systems
wget -qO - https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg | sudo apt-key add -
```

### Recovery Procedures

#### Restore Original Configuration
```bash
# List available backups
ls -la /var/backups/apt-fix/

# Restore sources.list
sudo cp /var/backups/apt-fix/sources.list.backup.TIMESTAMP /etc/apt/sources.list

# Restore sources.list.d
cd /
sudo tar -xzf /var/backups/apt-fix/sources.list.d.backup.TIMESTAMP.tar.gz

# Test restoration
sudo apt update
```

#### Manual Repository Fixing
```bash
# Edit sources.list manually
sudo nano /etc/apt/sources.list

# Remove or comment out problematic lines:
# deb file:/broken/path/to/repo /

# Edit individual repository files
sudo nano /etc/apt/sources.list.d/problematic-repo.list

# Test changes
sudo apt update
```

#### Reset to Default Configuration
```bash
# Backup current config
sudo cp /etc/apt/sources.list /etc/apt/sources.list.current

# For Proxmox systems, create minimal working config:
sudo cat > /etc/apt/sources.list << 'EOF'
deb http://ftp.debian.org/debian bookworm main contrib
deb http://ftp.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib
EOF

# Test minimal configuration
sudo apt update
```

## Advanced Usage

### Scripted APT Health Monitoring
```bash
#!/bin/bash
# APT health check script
LOG="/var/log/apt-health-monitor.log"

echo "$(date): Running APT health check" >> $LOG

# Run health check
if ! /usr/local/bin/apt-fix check >> $LOG 2>&1; then
    echo "$(date): APT issues detected, running auto-fix" >> $LOG
    /usr/local/bin/apt-fix fix >> $LOG 2>&1
    
    # Send notification
    echo "APT issues detected and fixed on $(hostname)" | \
    mail -s "APT Auto-Fix Applied" admin@example.com
fi
```

### Integration with Configuration Management
```bash
# Ansible playbook integration
- name: Check APT repository health
  command: /usr/local/bin/apt-fix check
  register: apt_check
  failed_when: false
  changed_when: false

- name: Fix APT repositories if needed
  command: /usr/local/bin/apt-fix fix
  when: apt_check.rc != 0
  notify: update package cache
```

### Custom Repository Validation
```bash
#!/bin/bash
# Custom repository validator
validate_repositories() {
    local config_file="$1"
    local issues=0
    
    # Check each repository line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*deb[[:space:]] ]]; then
            local url=$(echo "$line" | awk '{print $2}')
            
            # Test repository accessibility
            if [[ "$url" =~ ^https?:// ]]; then
                if ! curl -I "$url" >/dev/null 2>&1; then
                    echo "WARNING: Repository unreachable: $url"
                    ((issues++))
                fi
            fi
        fi
    done < "$config_file"
    
    return $issues
}

# Validate main sources.list
validate_repositories /etc/apt/sources.list
```

## Automation and Scheduling

### Cron Integration
```bash
# Add to root's crontab
sudo crontab -e

# Daily APT health check
0 6 * * * /usr/local/bin/apt-fix check >> /var/log/daily-apt-check.log 2>&1

# Weekly comprehensive check and fix
0 3 * * 1 /usr/local/bin/apt-fix fix >> /var/log/weekly-apt-fix.log 2>&1
```

### Systemd Timer Setup
```bash
# Create service file
sudo nano /etc/systemd/system/apt-fix.service

[Unit]
Description=APT Repository Fix Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/apt-fix check
ExecStartPost=/bin/bash -c 'if [ $EXIT_STATUS -ne 0 ]; then /usr/local/bin/apt-fix fix; fi'
StandardOutput=journal
StandardError=journal

# Create timer file
sudo nano /etc/systemd/system/apt-fix.timer

[Unit]
Description=Daily APT Repository Check
Requires=apt-fix.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target

# Enable and start timer
sudo systemctl daemon-reload
sudo systemctl enable apt-fix.timer
sudo systemctl start apt-fix.timer
```

## Best Practices

### Pre-Fix Planning
1. **Backup first**: Always create configuration backups before making changes
2. **Test in stages**: Use check mode before applying fixes
3. **Network verification**: Ensure internet connectivity before repository operations
4. **System stability**: Run during low-usage periods for system maintenance

### Safety Guidelines
1. **Non-production testing**: Test fixes on non-critical systems first
2. **Incremental fixes**: Address one issue type at a time if uncertain
3. **Monitor results**: Check APT functionality after each fix
4. **Keep logs**: Maintain detailed logs for troubleshooting

### Maintenance Schedule
1. **Daily**: Automated health checks with logging
2. **Weekly**: Comprehensive check and fix cycle
3. **Monthly**: Review logs and cleanup old backups
4. **As needed**: Emergency fixes when APT operations fail

### Repository Management
1. **Minimize repositories**: Only enable needed repositories
2. **Prefer official sources**: Use distribution official repositories when possible
3. **Regular updates**: Keep repository configurations current
4. **Document changes**: Maintain records of custom repository additions

The `apt-fix.sh` script provides comprehensive APT repository management for Proxmox and Debian-based systems with robust safety features and detailed diagnostics.
