# storage-cleanup.sh - Interactive Storage Cleanup

A comprehensive storage cleanup tool designed for Proxmox systems. Safely removes common space consumers with interactive confirmation and detailed logging.

## Overview

The `storage-cleanup.sh` script provides:

- **Interactive cleanup** with safety confirmations
- **Multiple cleanup categories** (packages, logs, backups, temps)
- **Dry run mode** for safe testing
- **Comprehensive logging** of all operations
- **Backup creation** before destructive operations
- **Space savings reporting** with before/after comparison

## Quick Start

```bash
# Interactive mode (default)
sudo storage-cleanup

# Clean all categories automatically
sudo storage-cleanup all

# Preview changes without applying
sudo storage-cleanup --dry-run all

# Show help
./storage-cleanup.sh --help
```

## Cleanup Categories

### 1. Package Cache
- **APT cache cleanup**: Removes downloaded package files
- **Orphaned packages**: Removes packages no longer needed
- **Cache analysis**: Shows current cache size before cleanup

### 2. Log Files  
- **Systemd journal**: Cleans journal logs (keeps last 7 days)
- **Log rotation**: Forces rotation of all log files
- **Compressed logs**: Removes old compressed logs (>30 days)
- **Large log identification**: Reports logs over 10MB

### 3. VM Backups
- **Age-based cleanup**: Removes backups older than specified days
- **Interactive selection**: User specifies retention period
- **Backup analysis**: Shows all backups with dates and sizes
- **Safe defaults**: Conservative 30-day default retention

### 4. Temporary Files
- **System temp cleanup**: Cleans /tmp and /var/tmp
- **Age-based removal**: Removes files older than 7 days
- **Size reporting**: Shows temp directory usage before cleanup

### 5. VM Templates and ISOs
- **ISO file analysis**: Lists ISO files with sizes
- **Template review**: Shows template directory usage
- **Manual review**: Prompts for user review of large files

### 6. Thin Pool Optimization
- **fstrim operations**: Runs fstrim on all mounted filesystems
- **Thin pool analysis**: Shows thin pool usage statistics
- **Space reclamation**: Helps reclaim unused thin pool space

## Usage Modes

### Interactive Mode (Default)
```bash
sudo storage-cleanup
# or
sudo ./storage-cleanup.sh interactive
```

Presents menu with options:
1. Clean package cache
2. Clean log files  
3. Clean VM backups
4. Clean temporary files
5. Clean VM templates and ISOs
6. Optimize thin pools
7. Clean all categories
8. Exit

### Automatic Mode
```bash
# Clean all categories
sudo storage-cleanup all

# Individual categories  
sudo storage-cleanup packages
sudo storage-cleanup logs
sudo storage-cleanup backups
sudo storage-cleanup temps
sudo storage-cleanup templates
sudo storage-cleanup optimize
```

### Dry Run Mode
```bash
# Preview all cleanup operations
sudo storage-cleanup --dry-run all

# Preview specific category
sudo storage-cleanup --dry-run logs
```

## Configuration

### Configurable Variables
Edit these variables at the top of the script:

```bash
LOG_FILE="/var/log/storage-cleanup.log"          # Log file location
BACKUP_DIR="/var/backups/storage-cleanup"        # Backup directory
DRY_RUN=false                                    # Dry run mode
```

### Custom Configuration Examples
```bash
# Different backup location
BACKUP_DIR="/backup/cleanup-backups"

# Custom log location  
LOG_FILE="/var/log/proxmox/storage-cleanup.log"

# Enable dry run by default
DRY_RUN=true
```

## Safety Features

### Confirmation Prompts
The script asks for confirmation before each operation:
```
Clean APT package cache? [y/N]: 
Remove orphaned packages? [y/N]:
Remove VM backups older than 30 days (5 files)? [y/N]:
```

### Backup Creation
Important files are backed up before deletion:
- Configuration files → `/var/backups/storage-cleanup/`
- Timestamped backups for recovery
- Automatic backup directory creation

### Dry Run Mode
Preview all operations without making changes:
```bash
sudo storage-cleanup --dry-run all
```
Shows:
```
[DRY RUN] Would execute: Clean APT cache
[DRY RUN] Would execute: Remove 5 VM backups older than 30 days
[DRY RUN] Would execute: Clean systemd journal
```

## Detailed Operations

### Package Cache Cleanup
```bash
# Operations performed:
apt clean                    # Remove downloaded packages
apt autoremove -y           # Remove orphaned packages

# Analysis shown:
Current APT cache size: 2.5GB
Orphaned packages: 15 packages
```

### Log File Cleanup
```bash
# Operations performed:
journalctl --vacuum-time=7d              # Clean systemd journal
logrotate -f /etc/logrotate.conf        # Force log rotation
find /var/log -name "*.gz" -mtime +30 -delete  # Remove old compressed logs

# Analysis shown:
Current log directory usage: 1.2GB
Large log files (>10MB): daemon.log (150MB), syslog (89MB)
```

### VM Backup Cleanup
```bash
# User prompted for retention period:
Remove backups older than how many days? [30]: 45

# Operations performed:
find /var/lib/vz/dump -name "*.vma*" -mtime +45 -delete
find /var/lib/vz/dump -name "*.tar*" -mtime +45 -delete

# Analysis shown:
VM backups by date:
Jan 15 10:00 vzdump-qemu-100-2024_01_15.vma.zst (2.1GB)
Jan 10 10:00 vzdump-qemu-100-2024_01_10.vma.zst (2.0GB)
Jan  5 10:00 vzdump-qemu-100-2024_01_05.vma.zst (1.9GB) [OLD]
```

### Temporary File Cleanup
```bash
# Operations performed:
find /tmp -type f -mtime +7 -delete
find /var/tmp -type f -mtime +7 -delete
find /tmp -type d -empty -delete
find /var/tmp -type d -empty -delete

# Analysis shown:
Current /tmp usage: 450MB
Current /var/tmp usage: 120MB
```

### Thin Pool Optimization
```bash
# Operations performed:
fstrim -av                  # Trim all mounted filesystems

# Analysis shown:
Current thin pool status:
data   pve  twi-aotz-- 200.00g   85.23% data, 5.45% meta
```

## Logging and Reporting

### Log File Format
```
[2024-01-15 10:00:00] [INFO] Storage cleanup started
[2024-01-15 10:00:15] [INFO] Cleaning APT cache
[2024-01-15 10:00:30] [INFO] APT cache cleaned successfully
[2024-01-15 10:01:00] [INFO] Removing old VM backups (older than 30 days)
[2024-01-15 10:01:15] [INFO] Old VM backups removed successfully
[2024-01-15 10:02:00] [INFO] Storage cleanup completed
```

### Cleanup Report
Generated at `/tmp/storage-cleanup-report.txt`:
```
Proxmox Storage Cleanup Report
Generated: 2024-01-15 10:30:00
===============================

DISK USAGE AFTER CLEANUP:
/dev/sda1    50G   20G   27G  43% /    [was 53%]
/dev/sda2   100G   65G   30G  69% /var/lib/vz  [was 85%]

CLEANUP ACTIONS PERFORMED:
- Cleaned APT cache (2.5GB freed)
- Removed orphaned packages (15 packages)
- Cleaned systemd journal (500MB freed)
- Removed 5 old VM backups (8.2GB freed)
- Cleaned temporary files (570MB freed)

TOTAL SPACE FREED: 11.8GB

RECOMMENDATIONS FOR FURTHER CLEANUP:
1. Review VM disk images for unused or oversized disks
2. Consider compressing old VM backups
3. Monitor log rotation to prevent future buildup
4. Regular maintenance with this script
```

### Space Savings Summary
Before and after disk usage comparison:
```
Initial disk usage:
/dev/sda1    50G   25G   23G  53% /
/dev/sda2   100G   80G   15G  85% /var/lib/vz

Final disk usage:  
/dev/sda1    50G   20G   27G  43% /
/dev/sda2   100G   65G   30G  69% /var/lib/vz

Space freed: 11.8GB
```

## Advanced Usage

### Custom Cleanup Scripts
```bash
#!/bin/bash
# Custom cleanup wrapper
echo "Starting automated cleanup..."

# Run analysis first
/usr/local/bin/storage-analyzer

# Clean if usage is high
ROOT_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $ROOT_USAGE -gt 80 ]; then
    echo "High usage detected ($ROOT_USAGE%), cleaning..."
    /usr/local/bin/storage-cleanup all
else
    echo "Usage acceptable ($ROOT_USAGE%), skipping cleanup"
fi
```

### Selective Cleanup Functions
```bash
# Clean only logs and packages
clean_logs_and_packages() {
    /usr/local/bin/storage-cleanup logs
    /usr/local/bin/storage-cleanup packages
}

# Emergency cleanup (most aggressive)
emergency_cleanup() {
    /usr/local/bin/storage-cleanup --dry-run all  # Preview first
    read -p "Proceed with emergency cleanup? [y/N]: " confirm
    if [[ "$confirm" == "y" ]]; then
        /usr/local/bin/storage-cleanup all
    fi
}
```

### Integration with Monitoring
```bash
#!/bin/bash
# Monitoring integration
CLEANUP_LOG="/var/log/storage-cleanup.log"

# Run cleanup
/usr/local/bin/storage-cleanup all

# Extract metrics
SPACE_FREED=$(tail -20 $CLEANUP_LOG | grep "Space freed" | cut -d: -f2)
if [[ -n "$SPACE_FREED" ]]; then
    echo "storage_cleanup_freed_gb $(echo $SPACE_FREED | sed 's/[^0-9.]//g')" | \
    curl -X POST monitoring-system/metrics
fi
```

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Must run as root for system cleanup
sudo ./storage-cleanup.sh
```

**2. Backup Directory Issues**
```bash
# Create backup directory manually
sudo mkdir -p /var/backups/storage-cleanup
sudo chmod 755 /var/backups/storage-cleanup
```

**3. Package Lock Issues**
```bash
# Wait for other package operations to complete
sudo fuser /var/lib/dpkg/lock-frontend
sudo killall apt apt-get dpkg
```

**4. Disk Space Errors**
```bash
# If cleanup fails due to no space, try individual categories
sudo storage-cleanup packages  # Start with package cache
sudo storage-cleanup logs      # Then logs
```

### Recovery Procedures

#### Restore Backed Up Files
```bash
# List available backups
ls -la /var/backups/storage-cleanup/

# Restore specific file
sudo cp /var/backups/storage-cleanup/filename.backup.timestamp /original/location
```

#### Undo Recent Cleanup
```bash
# Check what was cleaned in recent run
grep "removed successfully" /var/log/storage-cleanup.log | tail -10

# Review backup directory for restorable files
find /var/backups/storage-cleanup -mtime -1 -ls
```

## Automation and Scheduling

### Cron Integration
```bash
# Add to root's crontab
sudo crontab -e

# Weekly automated cleanup
0 2 * * 0 /usr/local/bin/storage-cleanup all >> /var/log/weekly-cleanup.log 2>&1

# Monthly comprehensive cleanup
0 3 1 * * /usr/local/bin/storage-cleanup all && /usr/local/bin/storage-analyzer
```

### Systemd Timer
```bash
# Create service file
sudo nano /etc/systemd/system/storage-cleanup.service

[Unit]
Description=Proxmox Storage Cleanup
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/storage-cleanup all
StandardOutput=journal
StandardError=journal

# Create timer file
sudo nano /etc/systemd/system/storage-cleanup.timer

[Unit]
Description=Weekly Storage Cleanup
Requires=storage-cleanup.service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target

# Enable timer
sudo systemctl daemon-reload
sudo systemctl enable storage-cleanup.timer
sudo systemctl start storage-cleanup.timer
```

## Best Practices

### Pre-Cleanup Planning
1. **Run storage-analyzer first**: Understand what's consuming space
2. **Test with dry run**: Always preview changes first
3. **Check system load**: Run during low-usage periods
4. **Verify backups**: Ensure important data is backed up

### Safety Guidelines
1. **Incremental approach**: Clean one category at a time if unsure
2. **Monitor results**: Check disk usage after each operation
3. **Keep logs**: Maintain cleanup logs for troubleshooting
4. **Test recovery**: Verify backup restoration procedures

### Maintenance Schedule
1. **Weekly**: Package cache and log cleanup
2. **Monthly**: VM backup cleanup and analysis
3. **Quarterly**: Comprehensive cleanup with thin pool optimization
4. **As needed**: Emergency cleanup when disk space is critical

The `storage-cleanup.sh` script provides safe, comprehensive storage cleanup for Proxmox systems with robust safety features and detailed reporting.
