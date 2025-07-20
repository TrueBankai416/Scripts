#!/bin/bash

# Proxmox Firmware Scanner Script
# Scans for NVMe and HDD firmware updates on Proxmox systems
# Usage: ./firmware-scanner.sh

# Configuration
LOG_FILE="/var/log/firmware-scanner.log"
REPORT_FILE="/tmp/firmware-report.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to check if we have root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Function to check required tools
check_required_tools() {
    echo -e "${BLUE}=== Checking Required Tools ===${NC}"
    
    local tools_missing=false
    local required_tools=("lsblk" "smartctl" "nvme")
    local optional_tools=("hdparm" "lshw" "dmidecode")
    
    echo "Checking required tools..."
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            echo -e "${GREEN}✓ $tool is available${NC}"
        else
            echo -e "${RED}✗ $tool is not available${NC}"
            tools_missing=true
        fi
    done
    
    echo ""
    echo "Checking optional tools..."
    for tool in "${optional_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            echo -e "${GREEN}✓ $tool is available${NC}"
        else
            echo -e "${YELLOW}⚠ $tool is not available (optional)${NC}"
        fi
    done
    
    if [[ "$tools_missing" == true ]]; then
        echo ""
        echo -e "${YELLOW}Installing missing tools...${NC}"
        apt update -qq
        apt install -y smartmontools nvme-cli hdparm lshw dmidecode
    fi
    
    echo ""
}

# Function to scan system storage overview
scan_storage_overview() {
    echo -e "${BLUE}=== Storage System Overview ===${NC}"
    
    echo "Block devices:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL,SERIAL 2>/dev/null || lsblk -d
    echo ""
    
    echo "Storage controllers:"
    if command -v lshw &> /dev/null; then
        lshw -c storage -short 2>/dev/null | grep -v "^H/W" || echo "Unable to get storage controller info"
    else
        echo "lshw not available - install with: apt install lshw"
    fi
    echo ""
    
    echo "PCI storage devices:"
    lspci | grep -i "storage\|raid\|ahci\|nvme" || echo "No storage controllers found in lspci output"
    echo ""
}

# Function to scan NVMe drives
scan_nvme_drives() {
    echo -e "${BLUE}=== Scanning NVMe Drives ===${NC}"
    
    local nvme_drives=($(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print $1}' | grep -E '^nvme'))
    
    if [[ ${#nvme_drives[@]} -eq 0 ]]; then
        echo "No NVMe drives detected"
        return 0
    fi
    
    echo "Found ${#nvme_drives[@]} NVMe drive(s):"
    echo ""
    
    for drive in "${nvme_drives[@]}"; do
        local device="/dev/$drive"
        echo -e "${CYAN}--- NVMe Drive: $device ---${NC}"
        
        # Basic drive information
        if command -v nvme &> /dev/null; then
            echo "Device information:"
            nvme id-ctrl "$device" 2>/dev/null | head -20 || echo "Unable to get NVMe controller info"
            echo ""
            
            echo "Current firmware version:"
            local firmware_version=$(nvme id-ctrl "$device" 2>/dev/null | grep "^fr " | awk '{print $3}' || echo "Unknown")
            echo "  Firmware Revision: $firmware_version"
            log_message "INFO" "NVMe drive $device firmware version: $firmware_version"
            
            echo "Model and serial:"
            local model=$(nvme id-ctrl "$device" 2>/dev/null | grep "^mn " | cut -d':' -f2 | tr -d ' ' || echo "Unknown")
            local serial=$(nvme id-ctrl "$device" 2>/dev/null | grep "^sn " | cut -d':' -f2 | tr -d ' ' || echo "Unknown")
            echo "  Model: $model"
            echo "  Serial: $serial"
            
            # Provide specific guidance for common Samsung models
            if [[ "$model" =~ "990 PRO" ]]; then
                echo "  → Samsung 990 PRO detected - Known high-performance NVMe drive"
                echo "  → Check Samsung website for thermal/performance firmware updates"
                echo "  → Model variations: MZ-V9P1T0CW (1TB), MZ-V9P2T0CW (2TB), MZ-V9P4T0CW (4TB)"
            elif [[ "$model" =~ "980 PRO" ]]; then
                echo "  → Samsung 980 PRO detected - Check for latest performance optimizations"
            elif [[ "$model" =~ "Samsung" ]]; then
                echo "  → Samsung NVMe drive detected - Firmware updates typically available via Samsung Magician"
            fi
            
            echo "Namespace information:"
            nvme list-ns "$device" 2>/dev/null || echo "Unable to list namespaces"
        else
            echo -e "${YELLOW}nvme-cli not available - install with: apt install nvme-cli${NC}"
        fi
        
        # SMART data
        if command -v smartctl &> /dev/null; then
            echo ""
            echo "SMART attributes (key indicators):"
            smartctl -A "$device" 2>/dev/null | grep -E "Temperature|Power_On_Hours|Wear_Leveling|Program_Fail|Erase_Fail|Available_Spare" | head -10 || echo "Unable to get SMART data"
        fi
        
        echo ""
        echo "----------------------------------------"
        echo ""
    done
}

# Function to scan SATA/HDD drives
scan_sata_hdd_drives() {
    echo -e "${BLUE}=== Scanning SATA/HDD Drives ===${NC}"
    
    local sata_drives=($(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print $1}' | grep -v -E '^nvme|^loop|^sr'))
    
    if [[ ${#sata_drives[@]} -eq 0 ]]; then
        echo "No SATA/HDD drives detected"
        return 0
    fi
    
    echo "Found ${#sata_drives[@]} SATA/HDD drive(s):"
    echo ""
    
    for drive in "${sata_drives[@]}"; do
        local device="/dev/$drive"
        echo -e "${CYAN}--- SATA/HDD Drive: $device ---${NC}"
        
        # Basic drive information using smartctl
        if command -v smartctl &> /dev/null; then
            echo "Device information:"
            local smart_info=$(smartctl -i "$device" 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                echo "$smart_info" | grep -E "Model|Serial|Firmware|Capacity|Sector"
                
                local firmware_version=$(echo "$smart_info" | grep "Firmware Version" | cut -d':' -f2 | tr -d ' ' || echo "Unknown")
                local model=$(echo "$smart_info" | grep "Device Model" | cut -d':' -f2 | tr -d ' ' || echo "Unknown")
                local serial=$(echo "$smart_info" | grep "Serial Number" | cut -d':' -f2 | tr -d ' ' || echo "Unknown")
                
                echo ""
                echo "Key information:"
                echo "  Model: $model"
                echo "  Serial: $serial"
                echo "  Firmware: $firmware_version"
                
                log_message "INFO" "SATA drive $device - Model: $model, Firmware: $firmware_version"
            else
                echo "Unable to get SMART information for $device"
            fi
            
            # SMART attributes
            echo ""
            echo "SMART attributes (key indicators):"
            smartctl -A "$device" 2>/dev/null | grep -E "Start_Stop_Count|Power_On_Hours|Temperature_Celsius|Reallocated_Sector|Current_Pending_Sector|Offline_Uncorrectable" | head -10 || echo "Unable to get SMART attributes"
        fi
        
        # Try hdparm for additional info
        if command -v hdparm &> /dev/null; then
            echo ""
            echo "Drive identification (hdparm):"
            hdparm -I "$device" 2>/dev/null | grep -E "Model Number|Serial Number|Firmware Revision|device size" | head -5 || echo "Unable to get hdparm info"
        fi
        
        echo ""
        echo "----------------------------------------"
        echo ""
    done
}

# Function to check firmware update resources
check_firmware_update_resources() {
    echo -e "${BLUE}=== Firmware Update Resources ===${NC}"
    
    echo "Common firmware update resources and procedures:"
    echo ""
    
    echo -e "${CYAN}NVMe Drives:${NC}"
    echo "• Check manufacturer websites for firmware updates:"
    echo "  - Samsung: Samsung Magician software or manual download"
    echo "  - Intel: Intel Memory and Storage Tool (intel-mas)"
    echo "  - Western Digital: WD Dashboard or manual download"
    echo "  - Crucial/Micron: Crucial Storage Executive"
    echo "  - Kingston: SSD Manager"
    echo ""
    echo "• Use nvme-cli for updates (if supported):"
    echo "  nvme fw-download /dev/nvmeXn1 --fw=firmware.bin"
    echo "  nvme fw-commit /dev/nvmeXn1 --slot=1 --action=1"
    echo ""
    
    echo -e "${CYAN}SATA/HDD Drives:${NC}"
    echo "• Manufacturer tools:"
    echo "  - Seagate: SeaTools for Linux or firmware downloads"
    echo "  - Western Digital: WD Drive Utilities (Linux version)"
    echo "  - Toshiba: Toshiba HDD/SSD Utility"
    echo "  - HGST: HGST Drive Fitness Test"
    echo ""
    echo "• General approach:"
    echo "  1. Identify exact model and current firmware version"
    echo "  2. Check manufacturer website for latest firmware"
    echo "  3. Download appropriate firmware update tool"
    echo "  4. Backup important data before updating"
    echo "  5. Follow manufacturer's update procedure"
    echo ""
}

# Function to analyze firmware status
analyze_firmware_status() {
    echo -e "${BLUE}=== Firmware Status Analysis ===${NC}"
    
    echo "Analysis of detected drives:"
    echo ""
    
    # Count drives by type
    local nvme_count=$(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print $1}' | grep -E '^nvme' | wc -l)
    local sata_count=$(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print $1}' | grep -v -E '^nvme|^loop|^sr' | wc -l)
    
    echo "Drive summary:"
    echo "  NVMe drives: $nvme_count"
    echo "  SATA/HDD drives: $sata_count"
    echo "  Total storage drives: $((nvme_count + sata_count))"
    echo ""
    
    echo -e "${YELLOW}Firmware Update Recommendations:${NC}"
    echo ""
    echo "1. ${CYAN}Document Current State${NC}"
    echo "   • Record all drive models, serials, and firmware versions"
    echo "   • Save this report for comparison after updates"
    echo ""
    echo "2. ${CYAN}Check for Updates${NC}"
    echo "   • Visit each manufacturer's website or use their tools"
    echo "   • Look for firmware updates released in the last 12 months"
    echo "   • Check release notes for bug fixes and performance improvements"
    echo ""
    echo "3. ${CYAN}Update Prioritization${NC}"
    echo "   • Critical: Security vulnerabilities or data corruption fixes"
    echo "   • High: Performance improvements or stability fixes"
    echo "   • Medium: Feature additions or minor bug fixes"
    echo ""
    echo "4. ${CYAN}Update Procedure${NC}"
    echo "   • Always backup important data first"
    echo "   • Update during maintenance windows"
    echo "   • Test one drive at a time in RAID configurations"
    echo "   • Verify system stability after each update"
    echo ""
    echo "5. ${CYAN}Post-Update Verification${NC}"
    echo "   • Re-run this scanner to verify firmware versions"
    echo "   • Check SMART attributes for any changes"
    echo "   • Monitor system logs for any new errors"
    echo "   • Run storage performance benchmarks if critical"
    echo ""
}

# Function to provide specific manufacturer guidance
provide_manufacturer_guidance() {
    echo -e "${BLUE}=== Manufacturer-Specific Guidance ===${NC}"
    
    echo "Based on detected drives, here are specific update procedures:"
    echo ""
    
    # Scan for common manufacturers and provide specific guidance
    local drives=$(lsblk -d -n -o NAME,MODEL 2>/dev/null)
    
    if echo "$drives" | grep -qi "samsung"; then
        echo -e "${CYAN}Samsung NVMe Drives Detected:${NC}"
        echo "• Method 1: Samsung Magician for Linux (preferred if available)"
        echo "  - Check: https://semiconductor.samsung.com/consumer-storage/support/tools/"
        echo "  - May require Windows/bootable environment for some models"
        echo ""
        echo "• Method 2: Manual firmware extraction and nvme-cli update"
        echo "  - Download firmware from Samsung support site"
        echo "  - Extract .bin file from downloaded package"
        echo "  - Use: nvme fw-download /dev/nvmeXn1 --fw=firmware.bin"
        echo "  - Then: nvme fw-commit /dev/nvmeXn1 --slot=1 --action=1"
        echo ""
        echo "• Method 3: Bootable update media (most compatible)"
        echo "  - Create bootable USB with Samsung firmware updater"
        echo "  - Boot from USB and run update (safest for critical systems)"
        echo ""
        echo "• Samsung 990 PRO series specific notes:"
        echo "  - Model MZ-V9P2T0CW: Check for performance/thermal firmware updates"
        echo "  - Forum reference: https://forum.proxmox.com/threads/update-samsung-consumer-ssd-nvme-firmware-in-proxmox.149324/"
        echo "  - Always backup data before firmware updates"
        echo ""
    fi
    
    if echo "$drives" | grep -qi "intel"; then
        echo -e "${CYAN}Intel Drives Detected:${NC}"
        echo "• Use Intel Memory and Storage Tool (intel-mas)"
        echo "• Command: intelmas show -intelssd"
        echo "• URL: https://www.intel.com/content/www/us/en/support/products/65296/memory-and-storage.html"
        echo ""
    fi
    
    if echo "$drives" | grep -qi "western\|wd"; then
        echo -e "${CYAN}Western Digital Drives Detected:${NC}"
        echo "• Use WD Dashboard (may have Linux version)"
        echo "• Check WD support site for specific model firmware"
        echo "• URL: https://support.wdc.com/"
        echo ""
    fi
    
    if echo "$drives" | grep -qi "seagate"; then
        echo -e "${CYAN}Seagate Drives Detected:${NC}"
        echo "• Use SeaTools for Linux"
        echo "• Download from Seagate support site"
        echo "• URL: https://www.seagate.com/support/downloads/seatools/"
        echo ""
    fi
    
    if echo "$drives" | grep -qi "crucial\|micron"; then
        echo -e "${CYAN}Crucial/Micron Drives Detected:${NC}"
        echo "• Use Crucial Storage Executive (check Linux compatibility)"
        echo "• URL: https://www.crucial.com/support/storage-executive"
        echo ""
    fi
    
    echo -e "${YELLOW}Note: Always verify Linux compatibility before downloading manufacturer tools.${NC}"
    echo ""
    
    # Provide detailed Samsung update procedure
    if echo "$drives" | grep -qi "samsung"; then
        echo -e "${BLUE}=== Detailed Samsung Firmware Update Procedure ===${NC}"
        echo ""
        echo -e "${CYAN}Step-by-Step Samsung NVMe Firmware Update:${NC}"
        echo ""
        echo "1. ${YELLOW}Preparation:${NC}"
        echo "   • Stop all VMs and containers using the NVMe drive"
        echo "   • Backup critical data to external storage"
        echo "   • Note current firmware version from this scan"
        echo ""
        echo "2. ${YELLOW}Download Firmware:${NC}"
        echo "   • Visit: https://semiconductor.samsung.com/consumer-storage/support/tools/"
        echo "   • Search for your exact model (e.g., MZ-V9P2T0CW for 990 PRO 2TB)"
        echo "   • Download the Linux firmware update tool or firmware binary"
        echo ""
        echo "3. ${YELLOW}Linux Update Methods:${NC}"
        echo ""
        echo "   Method A - Using Samsung's Linux tool (if available):"
        echo "   • Extract downloaded package"
        echo "   • Run: sudo ./samsung_magician_installer"
        echo "   • Follow on-screen instructions"
        echo ""
        echo "   Method B - Manual nvme-cli update (advanced):"
        echo "   • Extract firmware .bin file from download"
        echo "   • Identify your drive: lsblk | grep nvme"
        echo "   • Download: sudo nvme fw-download /dev/nvmeXn1 --fw=firmware.bin"
        echo "   • Commit: sudo nvme fw-commit /dev/nvmeXn1 --slot=1 --action=1"
        echo "   • Reboot and verify with: nvme id-ctrl /dev/nvmeXn1 | grep fr"
        echo ""
        echo "   Method C - Bootable USB (most reliable):"
        echo "   • Download Samsung firmware updater ISO"
        echo "   • Create bootable USB: dd if=samsung_updater.iso of=/dev/sdX bs=4M"
        echo "   • Boot from USB and run updater (safest for production systems)"
        echo ""
        echo "4. ${YELLOW}Post-Update Verification:${NC}"
        echo "   • Reboot the system completely"
        echo "   • Re-run this firmware scanner to verify new version"
        echo "   • Check system logs: journalctl -b | grep nvme"
        echo "   • Test storage performance if critical"
        echo ""
        echo "5. ${YELLOW}Troubleshooting:${NC}"
        echo "   • If update fails, try different firmware slot (0-6)"
        echo "   • Some drives require multiple reboot cycles"
        echo "   • Contact Samsung support for critical systems"
        echo ""
    fi
    echo ""
}

# Function to generate detailed report
generate_report() {
    echo -e "${BLUE}=== Generating Detailed Report ===${NC}"
    
    {
        echo "Proxmox Firmware Scanner Report"
        echo "Generated: $(date)"
        echo "==============================="
        echo ""
        
        echo "SYSTEM INFORMATION:"
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo "Proxmox Version: $(pveversion 2>/dev/null | head -1 || echo "Not available")"
        echo ""
        
        echo "STORAGE OVERVIEW:"
        lsblk -d -o NAME,SIZE,TYPE,MODEL,SERIAL 2>/dev/null
        echo ""
        
        echo "NVME DRIVES DETECTED:"
        local nvme_drives=($(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print $1}' | grep -E '^nvme'))
        if [[ ${#nvme_drives[@]} -gt 0 ]]; then
            for drive in "${nvme_drives[@]}"; do
                local device="/dev/$drive"
                echo "Device: $device"
                if command -v nvme &> /dev/null; then
                    nvme id-ctrl "$device" 2>/dev/null | grep -E "^mn |^sn |^fr " || echo "  Info not available"
                fi
                echo ""
            done
        else
            echo "None detected"
        fi
        echo ""
        
        echo "SATA/HDD DRIVES DETECTED:"
        local sata_drives=($(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print $1}' | grep -v -E '^nvme|^loop|^sr'))
        if [[ ${#sata_drives[@]} -gt 0 ]]; then
            for drive in "${sata_drives[@]}"; do
                local device="/dev/$drive"
                echo "Device: $device"
                if command -v smartctl &> /dev/null; then
                    smartctl -i "$device" 2>/dev/null | grep -E "Model|Serial|Firmware" || echo "  Info not available"
                fi
                echo ""
            done
        else
            echo "None detected"
        fi
        echo ""
        
        echo "RECOMMENDATIONS:"
        echo "1. Compare current firmware versions with manufacturer websites"
        echo "2. Prioritize security and stability updates"
        echo "3. Plan updates during maintenance windows"
        echo "4. Always backup data before firmware updates"
        echo "5. Test thoroughly after updates"
        echo ""
        
        echo "NEXT STEPS:"
        echo "1. Visit manufacturer websites for your specific drive models"
        echo "2. Check for firmware updates released in the last 12 months"
        echo "3. Download appropriate update tools"
        echo "4. Schedule maintenance window for updates"
        echo "5. Re-run this scanner after updates to verify"
        
    } > "$REPORT_FILE"
    
    echo "Detailed report saved to: $REPORT_FILE"
    echo ""
}

# Function to provide quick scan mode
quick_scan() {
    echo -e "${CYAN}=== Quick Firmware Scan ===${NC}"
    echo ""
    
    check_required_tools
    
    echo -e "${BLUE}Storage Summary:${NC}"
    lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null | grep -v "^loop\|^sr"
    echo ""
    
    echo -e "${BLUE}NVMe Firmware Versions:${NC}"
    local nvme_drives=($(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print $1}' | grep -E '^nvme'))
    if [[ ${#nvme_drives[@]} -gt 0 ]]; then
        for drive in "${nvme_drives[@]}"; do
            local device="/dev/$drive"
            local model=$(nvme id-ctrl "$device" 2>/dev/null | grep "^mn " | cut -d':' -f2 | xargs || echo "Unknown")
            local firmware=$(nvme id-ctrl "$device" 2>/dev/null | grep "^fr " | awk '{print $3}' || echo "Unknown")
            echo "  $device: $model (FW: $firmware)"
        done
    else
        echo "  No NVMe drives detected"
    fi
    echo ""
    
    echo -e "${BLUE}SATA/HDD Firmware Versions:${NC}"
    local sata_drives=($(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print $1}' | grep -v -E '^nvme|^loop|^sr'))
    if [[ ${#sata_drives[@]} -gt 0 ]]; then
        for drive in "${sata_drives[@]}"; do
            local device="/dev/$drive"
            local model=$(smartctl -i "$device" 2>/dev/null | grep "Device Model" | cut -d':' -f2 | xargs || echo "Unknown")
            local firmware=$(smartctl -i "$device" 2>/dev/null | grep "Firmware Version" | cut -d':' -f2 | xargs || echo "Unknown")
            echo "  $device: $model (FW: $firmware)"
        done
    else
        echo "  No SATA/HDD drives detected"
    fi
    echo ""
    
    echo -e "${YELLOW}Run full scan for detailed analysis and update guidance.${NC}"
}

# Main function
main() {
    local scan_mode="${1:-full}"
    
    echo -e "${CYAN}=== Proxmox Firmware Scanner ===${NC}"
    echo ""
    
    # Check if running as root
    check_root
    
    # Create log file
    touch "$LOG_FILE"
    log_message "INFO" "Firmware scan started - mode: $scan_mode"
    
    if [[ "$scan_mode" == "quick" ]]; then
        quick_scan
    else
        # Full scan mode
        check_required_tools
        scan_storage_overview
        scan_nvme_drives
        scan_sata_hdd_drives
        check_firmware_update_resources
        provide_manufacturer_guidance
        analyze_firmware_status
        generate_report
        
        echo -e "${GREEN}Firmware scan completed!${NC}"
        echo "Check the detailed report at: $REPORT_FILE"
        echo "Log file: $LOG_FILE"
    fi
    
    log_message "INFO" "Firmware scan completed"
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [mode]"
    echo ""
    echo "Proxmox Firmware Scanner"
    echo "Scans for NVMe and HDD firmware versions and provides update guidance"
    echo ""
    echo "Modes:"
    echo "  (no args)  - Full scan with detailed analysis and recommendations"
    echo "  full       - Full scan with detailed analysis and recommendations"
    echo "  quick      - Quick scan showing only current firmware versions"
    echo ""
    echo "The script will:"
    echo "  - Detect NVMe and SATA/HDD drives"
    echo "  - Report current firmware versions"
    echo "  - Provide manufacturer-specific update guidance"
    echo "  - Generate detailed report with recommendations"
    echo ""
    echo "Output files:"
    echo "  Report: $REPORT_FILE"
    echo "  Log: $LOG_FILE"
    echo ""
    echo "Examples:"
    echo "  $0           # Full scan"
    echo "  $0 full      # Full scan"
    echo "  $0 quick     # Quick firmware version check"
    echo ""
    echo "Note: This script requires root privileges to access drive information"
    exit 0
fi

# Run main function
main "$@"
