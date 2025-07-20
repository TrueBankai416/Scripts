# storage-config-fix.sh - Storage Configuration Repair

A comprehensive tool for diagnosing and fixing storage configuration issues in Proxmox systems. Addresses display inconsistencies, expands storage components, and optimizes LVM configurations.

## Overview

The `storage-config-fix.sh` script provides:

- **Storage discrepancy diagnosis** between different Proxmox views
- **Physical volume expansion** to use full disk capacity
- **Volume group and logical volume expansion** with free space utilization
- **Thin pool configuration fixes** and expansion
- **Proxmox storage service refresh** for updated display
- **Interactive and automated modes** for different use cases

## Quick Start

```bash
# Diagnose and fix all storage issues
sudo storage-config-fix

# Automated fix mode (minimal prompts)
sudo AUTO_FIX=true storage-config-fix

# Show help
./storage-config-fix.sh --help
```

## Common Problems Solved

### 1. Storage Display Inconsistencies
- **Proxmox summary vs. actual disk size**: Different views showing different capacities
- **Unallocated disk space**: Physical disks larger than configured storage
- **VG free space**: Volume groups with unused space not reflected in Proxmox

### 2. Post-Upgrade Storage Issues
- **Disk cloning leftovers**: Old size limits after cloning to larger disks
- **Upgrade remnants**: Storage not expanded after hardware upgrades
- **Partition misalignment**: Partitions not using full disk capacity

### 3. LVM Configuration Problems
- **PV size mismatches**: Physical volumes smaller than actual disks
- **Thin pool utilization**: High usage with available expansion space
- **Storage hierarchy issues**: Disconnected LVM components

## Usage

### Interactive Mode (Default)
```bash
sudo storage-config-fix
```

Provides step-by-step guidance:
1. **Display current overview**: Shows all storage components
2. **Diagnose issues**: Identifies specific problems
3. **Propose fixes**: Suggests appropriate solutions
4. **Execute repairs**: Applies fixes with user confirmation

### Automated Mode
```bash
# Enable automated fixes
sudo AUTO_FIX=true storage-config-fix

# Or set environment variable
export AUTO_FIX=true
sudo storage-config-fix
```

### Specific Operations
```bash
# Check only (no fixes)
sudo storage-config-fix diagnose

# Fix specific components
sudo storage-config-fix expand-pv      # Expand physical volumes only
sudo storage-config-fix expand-vg      # Expand volume groups only
sudo storage-config-fix fix-thin       # Fix thin pools only
```

## Diagnosis Process

### Storage Overview Display
Shows comprehensive current state:
```
Proxmox Version: pve-manager/8.1.4
Physical Disks:
NAME   SIZE   TYPE MOUNTPOINT
sda    500G   disk 
├─sda1   1M   part 
├─sda2 512M   part /boot/efi
└─sda3 400G   part   <-- Should be 499.5G

LVM Physical Volumes:
PV         VG   Fmt  Attr PSize   PFree
/dev/sda3  pve  lvm2 a--  400.00g  50.00g  <-- 100G unallocated

LVM Logical Volumes:
LV   VG   Attr       LSize   Pool Origin Data%
root pve  -wi-ao---- 96.00g                    
data pve  twi-aotz-- 250.00g              85.50
```

### Discrepancy Detection
Identifies specific issues:
```
Checking Physical Volume vs Disk Size discrepancies:
  Device: /dev/sda3
    Disk size: 500GB
    PV size: 400GB
    Difference: 100GB
    ⚠ Significant size difference detected!

Checking Volume Group space allocation:
  VG: pve
    Total: 400GB
    Free: 50GB
    ⚠ Significant free space available for expansion

Checking Thin Pool utilization:
  Thin Pool: pve/data
    Size: 250GB
    Data Usage: 85.50%
    ⚠ High thin pool utilization
```

## Fix Categories

### 1. Physical Volume Expansion
**Problem**: Physical volumes smaller than actual disk size
**Solution**: Expand partitions and physical volumes

```bash
# Operations performed:
parted /dev/sda resizepart 3 100%     # Expand partition
partprobe /dev/sda                    # Inform kernel
pvresize /dev/sda3                    # Expand physical volume
```

**Before/After**:
```
Before: /dev/sda3  400GB  →  After: /dev/sda3  499.5GB
PV size: 400GB           →  PV size: 499.5GB
```

### 2. Volume Group Expansion  
**Problem**: Volume groups with significant free space
**Solution**: Expand logical volumes to use available space

```bash
# Interactive selection of LV to expand
Available Logical Volumes in VG 'pve':
Num  Name     Size      Type
---  -------- --------- --------
1    root     96GB      Regular
2    data     250GB     ThinPool

# Expansion options:
lvextend -l +100%FREE /dev/pve/data   # Expand specific LV
# OR
lvextend -L +50G /dev/pve/root        # Expand by specific amount
```

### 3. Thin Pool Configuration Fix
**Problem**: Thin pools with high utilization but expandable
**Solution**: Expand thin pools with available VG space

```bash
# Thin pool expansion
lvextend -l +100%FREE /dev/pve/data   # Expand thin pool

# Metadata pool expansion (if needed)
lvextend --poolmetadatasize +10G /dev/pve/data
```

### 4. Proxmox Storage Service Refresh
**Problem**: Proxmox GUI showing outdated storage information
**Solution**: Restart storage-related services

```bash
# Services restarted:
systemctl restart pvestatd            # Storage statistics daemon
systemctl restart pvedaemon           # Main Proxmox daemon
systemctl restart pveproxy            # Web interface proxy
```

## Interactive Workflow

### Step 1: Overview and Diagnosis
```
=== Current Storage Overview ===
[Displays comprehensive storage state]

=== Diagnosing Storage Discrepancies ===
Found 3 potential storage configuration issues
```

### Step 2: Fix Planning
```
=== Physical Volume Expansion ===
Physical volumes that can be expanded:
  /dev/sda3 can be expanded by approximately 100GB

Would you like to expand these physical volumes? [y/N]:
```

### Step 3: Expansion Execution
```
Expanding PV: /dev/sda3
✓ Successfully expanded /dev/sda3

=== Volume Group and Logical Volume Expansion ===
Volume Group: pve has 150.00g free space
  Logical volumes in pve:
    root: 96.00g
    data: 250.00g

Would you like to expand logical volumes in pve? [y/N]:
```

### Step 4: Service Refresh
```
=== Refreshing Proxmox Storage Configuration ===
Refreshing Proxmox storage information...
✓ Restarted pvestatd
✓ Restarted pvedaemon
✓ Restarted pveproxy
```

## Configuration

### Configurable Variables
```bash
LOG_FILE="/var/log/storage-config-fix.log"    # Log file location
AUTO_FIX=false                                # Automated mode flag
```

### Environment Variables
```bash
# Enable automated fixes
export AUTO_FIX=true

# Custom log location
export LOG_FILE="/var/log/custom-storage-fix.log"
```

## Advanced Features

### Custom LV Sizing
When expanding logical volumes, supports:
- **Percentage-based**: `+100%FREE` (use all available space)
- **Size-based**: `+50G` (add specific amount)
- **Interactive selection**: Choose which LVs to expand
- **Proportional expansion**: Expand multiple LVs proportionally

### Thin Pool Management
Specialized handling for thin pools:
- **Data pool expansion**: Increase storage capacity
- **Metadata pool expansion**: Handle metadata space issues
- **Usage monitoring**: Track data and metadata percentages
- **Performance optimization**: Align with storage best practices

### Error Recovery
Robust error handling:
- **Pre-flight checks**: Validate system state before changes
- **Backup recommendations**: Suggests data backup before expansion
- **Rollback capabilities**: Can revert changes if issues occur
- **Service recovery**: Restarts failed services automatically

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Must run as root
sudo ./storage-config-fix.sh
```

**2. LVM Commands Not Found**
```bash
# Install LVM tools
sudo apt install lvm2
```

**3. Partition in Use Errors**
```bash
# Ensure no active operations
sudo fuser -v /dev/sda3
sudo umount /dev/sda3  # If mounted separately
```

**4. Service Restart Failures**
```bash
# Check service status
sudo systemctl status pvestatd pvedaemon pveproxy

# Manual service management
sudo systemctl stop pveproxy
sudo systemctl start pveproxy
```

### Advanced Troubleshooting

#### Expansion Failures
```bash
# Check disk alignment
sudo parted /dev/sda print

# Verify partition table
sudo fdisk -l /dev/sda

# Check LVM metadata
sudo vgdisplay pve
sudo lvdisplay pve
```

#### Service Issues
```bash
# Check Proxmox cluster status
sudo pvecm status

# Verify storage configuration
sudo cat /etc/pve/storage.cfg

# Check for storage locks
sudo find /var/lock -name "*pve*"
```

## Integration with Other Tools

### Pre-Fix Analysis
```bash
# Run storage analyzer first
sudo storage-analyzer

# Then run configuration fixes
sudo storage-config-fix
```

### Post-Fix Verification
```bash
# Verify fixes with analyzer
sudo storage-config-fix
sudo storage-analyzer

# Check Proxmox GUI
# Navigate to Datacenter → Storage to verify display
```

### Automated Workflows
```bash
#!/bin/bash
# Complete storage maintenance workflow

echo "=== Starting Storage Maintenance ==="

# 1. Analyze current state
/usr/local/bin/storage-analyzer > pre-fix-analysis.txt

# 2. Fix configuration issues
/usr/local/bin/storage-config-fix

# 3. Clean up if space was freed
/usr/local/bin/storage-cleanup

# 4. Final analysis
/usr/local/bin/storage-analyzer > post-fix-analysis.txt

echo "=== Storage Maintenance Complete ==="
```

## Best Practices

### Pre-Fix Preparation
1. **Backup critical data**: Always backup before expanding storage
2. **Document current state**: Save current LVM configuration
3. **Test in non-production**: Validate procedures in test environment
4. **Plan downtime**: Schedule during maintenance windows

### Post-Fix Verification
1. **Check Proxmox GUI**: Verify storage displays correctly
2. **Test VM operations**: Ensure VMs start and operate normally
3. **Monitor thin pools**: Watch thin pool usage after expansion
4. **Review logs**: Check for any warnings or errors

### Maintenance Integration
1. **Regular checks**: Run monthly to catch issues early
2. **Post-upgrade routine**: Run after hardware or system upgrades
3. **Monitoring integration**: Include in automated monitoring
4. **Documentation**: Keep records of storage changes

The `storage-config-fix.sh` script provides comprehensive solutions for Proxmox storage configuration issues, ensuring optimal storage utilization and display consistency.
