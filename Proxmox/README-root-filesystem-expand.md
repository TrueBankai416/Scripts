# root-filesystem-expand.sh - Root Filesystem Expansion

A comprehensive tool for expanding Proxmox root filesystems after cloning to larger drives or upgrading storage hardware. Handles LVM expansion, thin pool management, and custom sizing with safety features.

## Overview

The `root-filesystem-expand.sh` script provides:

- **Root filesystem expansion** after disk cloning or hardware upgrades
- **LVM hierarchy management** (Physical Volumes, Volume Groups, Logical Volumes)
- **Thin pool support** with advanced expansion capabilities
- **Custom sizing options** with interactive configuration
- **Safety validation** and expansion opportunity analysis
- **Step-by-step guidance** with detailed explanations

## Quick Start

```bash
# Analyze expansion opportunities
sudo root-filesystem-expand

# Custom LV expansion mode
sudo root-filesystem-expand custom

# Show help
./root-filesystem-expand.sh --help
```

## Common Scenarios

### 1. Post-Clone Expansion
**Situation**: Cloned Proxmox to a larger drive
**Problem**: Root filesystem still shows original smaller size
**Solution**: Expand partition → PV → VG → LV → filesystem

### 2. Hardware Upgrade
**Situation**: Replaced smaller disk with larger one
**Problem**: Proxmox not using full disk capacity
**Solution**: Complete storage stack expansion

### 3. Storage Optimization  
**Situation**: Want to optimize LVM layout
**Problem**: Poor space allocation between LVs
**Solution**: Custom LV sizing and thin pool optimization

## Usage

### Standard Expansion Mode
```bash
sudo root-filesystem-expand
```

**Process**:
1. **Detection**: Identifies root filesystem and LVM setup
2. **Analysis**: Checks for expansion opportunities  
3. **Planning**: Shows what can be expanded and by how much
4. **Execution**: Performs partition, PV, VG, and LV expansion
5. **Verification**: Confirms successful expansion

### Custom LV Expansion Mode
```bash  
sudo root-filesystem-expand custom
```

**Features**:
- **Interactive LV selection**: Choose specific logical volumes
- **Custom sizing**: Specify exact sizes or percentages
- **Thin pool management**: Advanced thin pool expansion
- **Multiple LV expansion**: Expand several LVs with custom allocations

## How It Works

### Detection Process
1. **Root filesystem identification**: Finds device hosting root (/)
2. **LVM validation**: Confirms LVM-based root filesystem
3. **Component mapping**: Maps PV → VG → LV hierarchy
4. **Disk analysis**: Determines parent disk device
5. **Expansion opportunity assessment**: Calculates available space

### Expansion Hierarchy
```
Physical Disk (/dev/sda - 1TB)
    ↓
Partition (/dev/sda3 - 800GB → expandable to ~999GB)
    ↓  
Physical Volume (/dev/sda3 - 800GB → expand with pvresize)
    ↓
Volume Group (pve - 800GB → inherit PV expansion)
    ↓
Logical Volume (root - 96GB, data - 200GB → expand with free space)
    ↓
Filesystem (ext4/xfs - expand with resize2fs/xfs_growfs)
```

### Expansion Steps

#### 1. Partition Expansion
```bash
# Expand partition to use full disk
parted /dev/sda resizepart 3 100%
partprobe /dev/sda                    # Inform kernel of changes
```

#### 2. Physical Volume Expansion
```bash
# Expand PV to use full partition
pvresize /dev/sda3
```

#### 3. Logical Volume Expansion
```bash
# Expand LV to use available VG space
lvextend -l +100%FREE /dev/pve/root   # Use all free space
# OR
lvextend -L +200G /dev/pve/root       # Add specific amount
```

#### 4. Filesystem Expansion
```bash
# Expand filesystem to fill LV
resize2fs /dev/pve/root               # For ext2/3/4
# OR  
xfs_growfs /dev/pve/root              # For XFS
```

## Advanced Features

### Thin Pool Management
**Special handling for thin pools**:

```bash
# Thin pool expansion
lvextend -l +100%FREE /dev/pve/data   # Expand thin pool itself

# Thin volume expansion (virtual size)
lvextend -L 500G /dev/pve/vm-100-disk-0  # Expand thin volume

# Metadata pool expansion
lvextend --poolmetadatasize +1G /dev/pve/data  # Expand metadata
```

### Custom LV Expansion

#### Interactive LV Selection
```
Available Logical Volumes in VG 'pve':
Num  Name     Size      Type
---  -------- --------- --------
1    root     96GB      Regular
2    data     200GB     ThinPool
3    swap     8GB       Regular

Enter LV name to expand (e.g., root, data):
```

#### Size Specification Options
```bash
# Percentage-based expansion
Size: +100%FREE          # Use all available free space
Size: +50%FREE           # Use half of free space

# Absolute size expansion  
Size: +100G              # Add 100GB
Size: 500G               # Resize to exactly 500GB

# Interactive sizing
Current size: 96GB
Available space: 204GB
Enter new size (or +amount): 300G
```

#### Thin Pool Expansion Dialog
```
Thin Pool: pve/data
  Current size: 200GB
  Data usage: 85.5% (171GB used)
  Metadata usage: 12.3%
  Available VG space: 204GB

Expansion options:
1. Expand by specific amount
2. Use all available space  
3. Set specific target size

Enter choice (1-3): 2
Expanding thin pool to use all 204GB free space...
```

## Current Status Display

### Root Filesystem Status
```
Current Root Filesystem Status:
Proxmox Version: pve-manager/8.1.4
Current disk usage:
Filesystem     Size  Used Avail Use% Mounted on
/dev/mapper/pve-root  94G   45G   44G  51% /

Root filesystem device: /dev/mapper/pve-root

Physical disk information:
NAME   SIZE  TYPE MOUNTPOINT
sda    1T    disk
├─sda1  1M   part
├─sda2 512M  part /boot/efi  
└─sda3 800G  part                    <-- Can expand to ~999G

LVM Physical Volumes:
PV         VG  Fmt  Attr PSize   PFree
/dev/sda3  pve lvm2 a--  800.00g  50.00g

Root LVM Logical Volume:
LV   VG  Attr       LSize Pool Origin Data%
root pve -wi-ao---- 96.00g
```

### Expansion Opportunity Analysis
```
Checking Expansion Opportunities:
Disk size: 1000GB
Partition size: 800GB  
PV size: 800GB
VG free space: 50.00g
Root LV size: 96.00g

✓ Partition can be expanded by ~200GB
✓ Physical volume can be expanded by ~200GB  
✓ Logical volume can be expanded by 50GB (currently available)
```

## Configuration

### Configurable Variables
```bash
LOG_FILE="/var/log/root-filesystem-expand.log"    # Log file location
```

### Environment Variables
```bash
# Enable automated expansion (minimal prompts)
export AUTO_EXPAND=true

# Custom log location
export LOG_FILE="/var/log/custom-root-expand.log"
```

## Safety Features

### Pre-Expansion Validation
- **LVM requirement check**: Ensures LVM-based root filesystem
- **Proxmox validation**: Confirms running on Proxmox system
- **Component verification**: Validates PV→VG→LV chain integrity
- **Space calculation**: Accurate available space computation

### Expansion Verification
- **Step-by-step validation**: Confirms each expansion step
- **Size verification**: Validates actual vs. expected sizes
- **Filesystem integrity**: Ensures filesystem consistency
- **Service health**: Checks system health after expansion

### Error Handling
- **Graceful failures**: Handles expansion errors safely
- **Rollback guidance**: Provides recovery procedures if needed
- **Detailed logging**: Comprehensive operation logging
- **User confirmation**: Requires explicit approval for changes

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Must run as root for disk operations
sudo ./root-filesystem-expand.sh
```

**2. Not LVM-Based System**
```bash
# Check if root is on LVM
findmnt -n -o SOURCE /

# Expected: /dev/mapper/vg-lv (LVM)
# If not LVM: This script is designed for LVM systems only
```

**3. No Expansion Opportunities**
```bash
# Check disk vs partition vs PV sizes
lsblk -o NAME,SIZE,TYPE
pvs
vgs
```

**4. Partition Expansion Failures**
```bash
# Check if partition is last on disk
parted /dev/sda print

# Ensure no data after partition
fdisk -l /dev/sda
```

### Advanced Troubleshooting

#### LVM Issues
```bash
# Check LVM metadata
sudo vgdisplay pve
sudo lvdisplay pve

# Verify PV status
sudo pvdisplay /dev/sda3

# Check for corruption
sudo vgck pve
```

#### Filesystem Issues
```bash
# Check filesystem type
mount | grep ' / '

# Verify filesystem integrity
sudo fsck /dev/mapper/pve-root  # Run when unmounted

# Check filesystem features
sudo tune2fs -l /dev/mapper/pve-root  # For ext filesystems
```

#### Disk Detection Issues
```bash
# Manual disk identification
lsblk -f
blkid

# Check partition table
sudo parted /dev/sda print
sudo fdisk -l /dev/sda
```

## Best Practices

### Pre-Expansion Planning
1. **Backup critical data**: Always backup before disk operations
2. **Document current state**: Record current LVM configuration
3. **Test procedures**: Validate in test environment if possible
4. **Plan downtime**: Schedule during maintenance windows

### Execution Guidelines
1. **Single operations**: Perform one expansion step at a time
2. **Verify each step**: Confirm successful completion before proceeding
3. **Monitor space**: Watch available space throughout process
4. **Check services**: Ensure Proxmox services remain healthy

### Post-Expansion Verification
1. **Confirm space increases**: Verify filesystem shows new size
2. **Test VM operations**: Ensure VMs start and operate normally
3. **Check thin pools**: Verify thin pool expansion if applicable
4. **Monitor performance**: Watch for any performance impacts

### Integration with Other Tools
```bash
#!/bin/bash
# Complete expansion workflow

echo "=== Pre-Expansion Analysis ==="
/usr/local/bin/storage-analyzer > pre-expansion.txt

echo "=== Performing Root Expansion ==="
/usr/local/bin/root-filesystem-expand

echo "=== Post-Expansion Analysis ==="
/usr/local/bin/storage-analyzer > post-expansion.txt

echo "=== Expansion Complete ==="
echo "Compare: diff pre-expansion.txt post-expansion.txt"
```

The `root-filesystem-expand.sh` script provides comprehensive root filesystem expansion capabilities for Proxmox systems, handling the complexity of LVM hierarchies while maintaining safety and providing detailed guidance throughout the process.
