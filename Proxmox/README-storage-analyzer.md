# storage-analyzer.sh - Comprehensive Storage Analysis

A comprehensive storage analysis tool designed for Proxmox systems. Analyzes disk usage, identifies space consumers, and provides detailed reports with cleanup recommendations.

## Overview

The `storage-analyzer.sh` script provides:

- **Comprehensive storage analysis** across filesystems and LVM
- **VM storage analysis** including disk images and backups
- **Large file detection** with size-based filtering
- **Log file analysis** with size reporting
- **LVM thin pool analysis** with usage metrics
- **Automated report generation** with cleanup recommendations
- **Duplicate file detection** (when fdupes is available)

## Quick Start

```bash
# Run complete storage analysis
sudo storage-analyzer

# View generated report
cat /tmp/storage-report.txt

# Check analysis log
tail -f /var/log/storage-analyzer.log
```

## Features

### Disk Usage Analysis
- **Filesystem overview**: Shows all mounted filesystems with usage
- **Directory analysis**: Identifies largest directories in root filesystem
- **LVM information**: Physical volumes, volume groups, and logical volumes
- **Usage tracking**: Monitors space consumption patterns

### VM Storage Analysis
- **VM disk images**: Analyzes .qcow2, .raw, and .vmdk files by size
- **VM backups**: Lists backup files with sizes and dates
- **Storage pools**: Shows Proxmox storage status
- **Template analysis**: Examines ISO files and templates

### Advanced Analysis
- **Large file detection**: Finds files >500MB and >1GB
- **Log file analysis**: Identifies large log files (>10MB)
- **Package cache analysis**: APT cache usage
- **Thin pool monitoring**: LVM thin pool data and metadata usage
- **Swap analysis**: Memory and swap usage
- **Core dump detection**: Finds core dump files

## Usage

### Basic Usage
```bash
# Complete analysis
sudo ./storage-analyzer.sh

# With help information
./storage-analyzer.sh --help
```

### Integration with Other Scripts
```bash
# Run analysis before cleanup
sudo storage-analyzer
sudo storage-cleanup

# Automated analysis and cleanup
sudo storage-analyzer && sudo storage-cleanup all
```

## Output Files

### Analysis Report
**Location**: `/tmp/storage-report.txt`

Contains:
- Disk usage summary
- Top 10 largest directories
- Largest files (>500MB)
- Log file summary
- LVM thin pool status
- Cleanup recommendations

### Log File  
**Location**: `/var/log/storage-analyzer.log`

Contains:
- Analysis timestamps
- Detailed operation logs
- Error messages
- Performance metrics

## Analysis Categories

### 1. Disk Usage Summary
```
Overall filesystem usage:
/dev/sda1    50G   25G   23G  53% /
/dev/sda2   100G   80G   15G  85% /var/lib/vz

LVM Information:
PV /dev/sda3   VG pve   250G / 250G
VG pve   250G   50G
LV root  30G
LV data  200G
```

### 2. Directory Usage Analysis
```
Top 10 largest directories in root filesystem:
15G    /var/lib/vz/images
8.2G   /var/lib/vz/dump
2.1G   /var/log
1.5G   /usr
```

### 3. VM Storage Analysis
```
VM disk images by size:
-rw-r--r-- 1 root root 20G Jan 15 10:00 vm-100-disk-0.qcow2
-rw-r--r-- 1 root root 15G Jan 14 09:30 vm-101-disk-0.raw

VM backups by size:
-rw-r--r-- 1 root root 5.2G Jan 10 02:00 vzdump-qemu-100-2024_01_10-02_00_15.vma.zst
```

### 4. Large Files Analysis
```
Files larger than 1GB:
-rw------- 1 root root 2.1G Jan 15 08:00 /var/log/daemon.log
-rw-r--r-- 1 root root 1.5G Jan 14 12:00 /var/cache/apt/archives/package.deb

Files larger than 500MB:
[Additional files listed...]
```

### 5. LVM Thin Pool Analysis
```
Thin pool information:
LV     VG   Attr       LSize   Pool Origin Data%  Meta%
data   pve  twi-aotz-- 200.00g             85.23  5.45
vm-100 pve  Vwi-aotz-- 20.00g  data        92.15
```

## Configuration

### Configurable Variables
Edit these variables at the top of the script:

```bash
LOG_FILE="/var/log/storage-analyzer.log"     # Log file location
REPORT_FILE="/tmp/storage-report.txt"        # Report output location
```

### Custom Configuration Examples
```bash
# Different report location
REPORT_FILE="/var/reports/storage-$(date +%Y%m%d).txt"

# Custom log location
LOG_FILE="/var/log/proxmox/storage-analyzer.log"
```

## Analysis Functions

### get_disk_usage()
- Shows filesystem usage with `df -h`
- Displays LVM physical volumes, volume groups, logical volumes
- Provides overview of storage hierarchy

### analyze_directory_usage()  
- Uses `du -h` to find largest directories
- Focuses on common Proxmox directories
- Counts files in each directory

### analyze_vm_storage()
- Lists all VMs with `qm list`
- Shows storage status with `pvesm status`
- Analyzes VM disk images by size
- Reviews VM backup files

### find_large_files()
- Searches for files >1GB and >500MB
- Excludes system directories (/proc, /sys, /dev)
- Sorts by size for easy identification

### analyze_lvm_thin_pools()
- Shows thin pool usage percentages
- Displays data and metadata utilization
- Identifies thin volumes and their pools

## Integration with Cleanup Tools

### Pre-Cleanup Analysis
```bash
# Analyze before cleanup
sudo storage-analyzer > pre-cleanup-report.txt

# Perform cleanup
sudo storage-cleanup all

# Analyze after cleanup  
sudo storage-analyzer > post-cleanup-report.txt

# Compare results
diff pre-cleanup-report.txt post-cleanup-report.txt
```

### Automated Workflows
```bash
#!/bin/bash
# Monthly storage maintenance
/usr/local/bin/storage-analyzer
if grep -q "Root filesystem usage.*[89][0-9]%" /tmp/storage-report.txt; then
    /usr/local/bin/storage-cleanup all
    /usr/local/bin/storage-analyzer  # Re-analyze after cleanup
fi
```

## Cleanup Recommendations

The script provides specific recommendations:

### 1. Log Files
```
- Rotate and compress old logs: logrotate -f /etc/logrotate.conf
- Clear systemd journal: journalctl --vacuum-time=7d
- Clear old kernel logs manually if needed
```

### 2. Package Cache
```
- Clean APT cache: apt clean
- Remove orphaned packages: apt autoremove
```

### 3. VM Management
```
- Remove old VM backups in /var/lib/vz/dump/
- Check for unused VM disk images
- Consider compressing VM backups
```

### 4. Thin Pool Management
```
- Consider running fstrim on thin pools
- Monitor data_percent and metadata_percent
```

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Must run as root for complete analysis
sudo ./storage-analyzer.sh
```

**2. Missing LVM Commands**
```bash
# Install LVM tools
sudo apt install lvm2
```

**3. Missing Proxmox Commands**
```bash
# Verify Proxmox installation
which qm pvesm
pveversion
```

**4. Large Report Files**
```bash
# Limit large file search
find / -type f -size +1G -exec ls -lh {} \; 2>/dev/null | head -20
```

### Advanced Troubleshooting

#### Performance Issues
```bash
# Run analysis on specific directories only
du -h /var/lib/vz/* | sort -hr

# Limit find operations
find /var/lib/vz -type f -size +100M -exec ls -lh {} \;
```

#### Missing Tools
```bash
# Install optional dependencies
sudo apt install fdupes  # For duplicate file detection
sudo apt install tree    # For directory tree views
```

## Automation and Scheduling

### Cron Integration
```bash
# Add to root's crontab
sudo crontab -e

# Weekly analysis
0 2 * * 0 /usr/local/bin/storage-analyzer > /var/reports/weekly-storage.txt

# Daily analysis with email
0 6 * * * /usr/local/bin/storage-analyzer | mail -s "Daily Storage Report" admin@example.com
```

### Systemd Timer
```bash
# Create timer for regular analysis
sudo nano /etc/systemd/system/storage-analyzer.timer

[Unit]
Description=Weekly Storage Analysis
Requires=storage-analyzer.service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
```

### Integration with Monitoring
```bash
# Send metrics to monitoring system
#!/bin/bash
/usr/local/bin/storage-analyzer

# Extract key metrics
ROOT_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
echo "root_filesystem_usage $ROOT_USAGE" | curl -X POST monitoring-system/metrics

# Check for critical usage
if [ $ROOT_USAGE -gt 90 ]; then
    echo "CRITICAL: Root filesystem usage at $ROOT_USAGE%" | \
    curl -X POST alert-system/alerts
fi
```

## Report Customization

### Custom Report Sections
Add custom analysis functions:

```bash
analyze_custom_directory() {
    echo -e "${BLUE}=== Custom Directory Analysis ===${NC}"
    
    local custom_dirs=("/opt" "/home" "/srv")
    
    for dir in "${custom_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "Directory: $dir"
            du -sh "$dir"/* 2>/dev/null | sort -hr | head -10
            echo ""
        fi
    done
}
```

### Report Formatting
```bash
# Generate CSV report
generate_csv_report() {
    echo "Directory,Size,Files" > /tmp/storage-report.csv
    du -s /* 2>/dev/null | while read size dir; do
        files=$(find "$dir" -type f 2>/dev/null | wc -l)
        echo "$dir,$size,$files" >> /tmp/storage-report.csv
    done
}
```

## Best Practices

### Regular Analysis
1. **Weekly reviews**: Run analysis weekly to track trends
2. **Pre-cleanup analysis**: Always analyze before major cleanup
3. **Trend monitoring**: Compare reports over time
4. **Threshold alerts**: Set up alerts for critical usage levels

### Performance Optimization
1. **Targeted analysis**: Focus on problem areas
2. **Exclude unnecessary paths**: Skip virtual filesystems
3. **Limit search depth**: Use maxdepth with find commands
4. **Schedule appropriately**: Run during low-usage periods

### Integration Planning
1. **Combine with cleanup**: Use analysis to guide cleanup efforts
2. **Monitor trends**: Track storage growth patterns
3. **Automate responses**: Set up automated cleanup triggers
4. **Document findings**: Keep records of analysis results

The `storage-analyzer.sh` script provides comprehensive insight into Proxmox storage usage, enabling informed decisions about storage management and cleanup priorities.
