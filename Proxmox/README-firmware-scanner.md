# firmware-scanner.sh - Drive Firmware Scanner

A comprehensive firmware scanning and update guidance tool for Proxmox systems. Identifies current firmware versions on NVMe and SATA drives and provides manufacturer-specific update procedures.

## Overview

The `firmware-scanner.sh` script provides:

- **Complete drive inventory** with firmware version detection
- **NVMe and SATA/HDD support** with specialized handling for each type
- **Manufacturer-specific guidance** for firmware updates
- **Security and performance update prioritization** 
- **Detailed update procedures** including Samsung ISO decryption
- **Comprehensive reporting** with recommendations and resources

## Quick Start

```bash
# Complete firmware scan
sudo firmware-scanner

# Quick scan (basic info only)
sudo firmware-scanner quick

# Show help
./firmware-scanner.sh --help
```

## Supported Drive Types

### NVMe Drives
- **Samsung** (990 PRO, 980 PRO, etc.)
- **Intel** (Optane, SSD series)
- **Western Digital** (WD Black, Blue series)
- **Crucial/Micron** (P1, P2, P5 series)
- **Kingston** (NV1, NV2 series)
- **Generic NVMe** (universal nvme-cli support)

### SATA/HDD Drives  
- **Seagate** (Barracuda, Exos, IronWolf series)
- **Western Digital** (WD Red, Blue, Black series)
- **Toshiba/HGST** (Enterprise and consumer series)
- **Samsung** (SATA SSD series)
- **Generic SATA** (universal smartctl support)

## Features

### Automatic Detection
- **Drive enumeration**: Identifies all storage drives automatically
- **Interface detection**: Distinguishes between NVMe, SATA, USB, etc.
- **Manufacturer identification**: Recognizes drive manufacturers
- **Model classification**: Identifies specific drive models and series

### Firmware Analysis
- **Current version reporting**: Shows installed firmware versions
- **Update availability checking**: Guidance on finding updates
- **Security update prioritization**: Highlights critical security updates
- **Performance update identification**: Notes performance improvements

### Update Guidance
- **Tool recommendations**: Suggests appropriate update tools
- **Procedure documentation**: Step-by-step update instructions
- **Platform compatibility**: Linux-specific guidance
- **Risk assessment**: Update priority and risk level

## Usage

### Basic Scan
```bash
# Complete firmware analysis
sudo ./firmware-scanner.sh

# Shorter form (if installed)
sudo firmware-scanner
```

### Quick Scan Mode
```bash
# Fast scan with basic info
sudo firmware-scanner quick

# Shows only:
# - Drive models
# - Current firmware versions  
# - Basic manufacturer info
```

### Analysis Output

#### Storage System Overview
```
=== Storage System Overview ===
Block devices:
NAME   SIZE  TYPE MODEL              SERIAL
nvme0n1 1T   disk Samsung SSD 990 PRO MZ-V9P1T0BW0
sda    4T    disk WDC WD40EFRX-68N32N0 WD-WXXXXXXX

Storage controllers:
H/W path     Device     Class      Description
/0/100/17    /dev/sda   storage    SATA controller
/0/100/1c.4  /dev/nvme0 storage    NVMe SSD Controller

PCI storage devices:
00:17.0 SATA controller: Intel Corporation Device 43d3
01:00.0 Non-Volatile memory controller: Samsung Electronics Co Ltd NVMe SSD Controller SM981/PM981/PM983
```

#### NVMe Drive Analysis
```
=== Scanning NVMe Drives ===
Found 1 NVMe drive(s):

--- NVMe Drive: /dev/nvme0n1 ---
Current firmware version:
  Firmware Revision: 4B2QGXA7

Model and serial:
  Model: Samsung SSD 990 PRO 1TB
  Serial: S7L1NX0W123456X

  → Samsung 990 PRO detected - Known high-performance NVMe drive
  → Check Samsung website for thermal/performance firmware updates
  → Model variations: MZ-V9P1T0CW (1TB), MZ-V9P2T0CW (2TB)

SMART attributes (key indicators):
Temperature:                     42 Celsius
Available Spare:                 100%
Data Units Read:                 12,345,678
Data Units Written:              8,901,234
```

#### SATA Drive Analysis  
```
=== Scanning SATA/HDD Drives ===
Found 1 SATA/HDD drive(s):

--- SATA/HDD Drive: /dev/sda ---
Key information:
  Model: WDC WD40EFRX-68N32N0
  Serial: WD-WCC7K1234567
  Firmware: 82.00A82

SMART attributes (key indicators):
Start_Stop_Count:                1,234
Power_On_Hours:                  12,345 hours
Temperature_Celsius:             35 Celsius
Reallocated_Sector_Ct:           0
Current_Pending_Sector:          0
```

## Manufacturer-Specific Guidance

### Samsung NVMe Drives

#### Update Methods
```
Samsung NVMe Drives Detected:
• Method 1: Samsung Magician for Linux (preferred if available)
  - Check: https://semiconductor.samsung.com/consumer-storage/support/tools/
  - May require Windows/bootable environment for some models

• Method 2: Manual firmware extraction and nvme-cli update
  - Download firmware from Samsung support site
  - Extract .bin file from downloaded package
  - Use: nvme fw-download /dev/nvmeXn1 --fw=firmware.bin
  - Then: nvme fw-commit /dev/nvmeXn1 --slot=1 --action=1

• Method 3: Bootable update media (most compatible)
  - Create bootable USB with Samsung firmware updater
  - Boot from USB and run update (safest for critical systems)
```

#### Samsung 990 PRO Specific Notes
```
• Samsung 990 PRO series specific notes:
  - Model MZ-V9P2T0CW: Check for performance/thermal firmware updates
  - Forum reference: https://forum.proxmox.com/threads/update-samsung-consumer-ssd-nvme-firmware-in-proxmox.149324/
  - Always backup data before firmware updates
```

#### Detailed Samsung Update Procedure
```
Step-by-Step Samsung NVMe Firmware Update:

1. Preparation:
   • Stop all VMs and containers using the NVMe drive
   • Backup critical data to external storage
   • Note current firmware version from this scan

2. Download Firmware:
   • Visit Samsung support site for your specific model
   • Download latest firmware package (.iso or .exe file)
   • Verify checksum if provided

3. Extract Firmware Binary:
   • For ISO files: Mount and extract .bin file
   • For Windows executables: Use wine or extract with 7zip
   • Resulting file: typically ends with .bin or .enc

4. Decrypt if Needed (for newer Samsung models):
   • Some firmware files are encrypted
   • Use community tools for decryption
   • Verify decrypted file integrity

5. Update Process:
   • Identify exact NVMe device: ls /dev/nvme*n1
   • Download firmware: nvme fw-download /dev/nvme0n1 --fw=firmware.bin
   • Commit firmware: nvme fw-commit /dev/nvme0n1 --slot=1 --action=1
   • Reboot system to activate new firmware

6. Verification:
   • Check new firmware version: nvme id-ctrl /dev/nvme0n1
   • Run this scanner again to confirm update
   • Monitor system stability and performance
```

### Other Manufacturers

#### Intel Drives
```
Intel Drives Detected:
• Use Intel Memory and Storage Tool (intel-mas)
• Command: intelmas show -intelssd
• URL: https://www.intel.com/content/www/us/en/support/products/65296/memory-and-storage.html
```

#### Western Digital Drives
```
Western Digital Drives Detected:
• Use WD Dashboard (may have Linux version)
• Check WD support site for specific model firmware
• URL: https://support.wdc.com/
```

#### Seagate Drives
```
Seagate Drives Detected:
• Use SeaTools for Linux
• Download from Seagate support site
• URL: https://www.seagate.com/support/downloads/seatools/
```

## Update Prioritization

### Critical Priority
- **Security vulnerabilities**: Patches for known security issues
- **Data corruption fixes**: Firmware preventing data loss
- **Hardware compatibility**: Fixes for system compatibility issues

### High Priority  
- **Performance improvements**: Significant speed or efficiency gains
- **Stability fixes**: Resolves crashes or reliability issues
- **Thermal management**: Better heat management and throttling

### Medium Priority
- **Feature additions**: New functionality or capabilities
- **Minor bug fixes**: Non-critical issue resolution
- **Optimization tweaks**: Marginal performance improvements

## Installation Requirements

### Required Tools
The script checks for and installs:
- **smartmontools**: For SMART data and drive information
- **nvme-cli**: For NVMe drive management and firmware updates
- **hdparm**: For additional drive information
- **lshw**: For hardware identification
- **dmidecode**: For system information

### Optional Tools
- **p7zip-full**: For extracting firmware archives
- **openssl**: For firmware decryption
- **xxd**: For hex editing and analysis
- **binutils**: For binary file manipulation

### Installation Check
```
=== Checking Required Tools ===
Checking required tools...
✓ smartctl is available
✓ nvme is available  
✗ hdparm is not available

Installing missing tools...
[apt update and install process]
✓ All required tools installed
```

## Configuration

### Configurable Variables
```bash
LOG_FILE="/var/log/firmware-scanner.log"         # Log file location
REPORT_FILE="/tmp/firmware-report.txt"           # Report output file
```

### Environment Variables
```bash
# Quick scan mode
export FIRMWARE_SCAN_MODE=quick

# Custom report location
export REPORT_FILE="/var/reports/firmware-$(date +%Y%m%d).txt"
```

## Analysis Report

### Generated Report Location
**File**: `/tmp/firmware-report.txt`

### Report Contents
```
Proxmox Drive Firmware Analysis Report
Generated: 2024-01-15 10:30:00
==========================================

DRIVE INVENTORY:
- NVMe drives: 2
- SATA drives: 1  
- Total storage drives: 3

CURRENT FIRMWARE VERSIONS:
/dev/nvme0n1: Samsung 990 PRO - Firmware 4B2QGXA7
/dev/nvme1n1: Intel Optane - Firmware 8DV10135
/dev/sda: WD Red - Firmware 82.00A82

UPDATE RECOMMENDATIONS:
1. Samsung 990 PRO: Check for thermal optimization updates
2. Intel Optane: Review Intel MAS for latest firmware
3. WD Red: No critical updates identified

NEXT STEPS:
1. Visit manufacturer websites for each drive
2. Check for firmware updates released in last 12 months
3. Prioritize security and stability updates
4. Test in non-production environment first
```

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Must run as root for hardware access
sudo ./firmware-scanner.sh
```

**2. Missing Tools**
```bash
# Install required packages manually
sudo apt update
sudo apt install smartmontools nvme-cli hdparm lshw dmidecode
```

**3. Drive Not Detected**
```bash
# Check drive visibility
lsblk -d
ls /dev/nvme*n1
ls /dev/sd*

# Verify drive health
sudo smartctl -H /dev/nvme0n1
sudo smartctl -H /dev/sda
```

**4. Firmware Update Failures**
```bash
# Check NVMe admin commands support
sudo nvme admin-passthru /dev/nvme0n1 --help

# Verify firmware file integrity
ls -la firmware.bin
file firmware.bin
```

## Best Practices

### Regular Scanning
1. **Quarterly scans**: Check for new firmware releases
2. **Post-upgrade scans**: Scan after hardware changes
3. **Security monitoring**: Watch for security-related updates
4. **Performance tracking**: Monitor firmware update benefits

### Update Planning
1. **Test environment first**: Never update production directly
2. **Backup data**: Always backup before firmware updates
3. **Schedule downtime**: Plan maintenance windows
4. **Staged rollout**: Update one drive at a time in RAID setups

### Documentation
1. **Keep records**: Document all firmware versions and update dates
2. **Track issues**: Note any problems after updates
3. **Share knowledge**: Document procedures for team
4. **Monitor performance**: Track performance changes after updates

The `firmware-scanner.sh` script provides comprehensive firmware analysis and update guidance for Proxmox storage systems, helping maintain optimal drive performance and security.
