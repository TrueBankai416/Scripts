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

# Function to update firmware interactively
interactive_firmware_updater() {
    echo -e "${CYAN}=== Interactive Firmware Updater ===${NC}"
    echo ""
    
    check_required_tools
    
    echo -e "${RED}WARNING: Firmware updates can be risky! Always backup your data first.${NC}"
    echo -e "${YELLOW}This tool will guide you through firmware updates for detected drives.${NC}"
    echo ""
    
    if ! confirm_action "Continue with firmware update process?"; then
        echo "Update cancelled."
        return 1
    fi
    
    # Scan and display drives
    echo -e "${BLUE}Scanning for drives...${NC}"
    echo ""
    
    local nvme_drives=($(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print $1}' | grep -E '^nvme'))
    local sata_drives=($(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print $1}' | grep -v -E '^nvme|^loop|^sr'))
    
    local all_drives=()
    local drive_info=()
    local counter=1
    
    # Collect NVMe drives
    for drive in "${nvme_drives[@]}"; do
        local device="/dev/$drive"
        local model="Unknown"
        local firmware="Unknown"
        
        if command -v nvme &> /dev/null; then
            model=$(nvme id-ctrl "$device" 2>/dev/null | grep "^mn " | cut -d':' -f2 | xargs || echo "Unknown")
            firmware=$(nvme id-ctrl "$device" 2>/dev/null | grep "^fr " | awk '{print $3}' || echo "Unknown")
        fi
        
        all_drives+=("$device")
        drive_info+=("NVMe: $model (FW: $firmware)")
        echo "$counter. $device - NVMe: $model (Firmware: $firmware)"
        ((counter++))
    done
    
    # Collect SATA drives
    for drive in "${sata_drives[@]}"; do
        local device="/dev/$drive"
        local model="Unknown"
        local firmware="Unknown"
        
        if command -v smartctl &> /dev/null; then
            local smart_info=$(smartctl -i "$device" 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                model=$(echo "$smart_info" | grep "Device Model" | cut -d':' -f2 | xargs || echo "Unknown")
                firmware=$(echo "$smart_info" | grep "Firmware Version" | cut -d':' -f2 | xargs || echo "Unknown")
            fi
        fi
        
        all_drives+=("$device")
        drive_info+=("SATA: $model (FW: $firmware)")
        echo "$counter. $device - SATA: $model (Firmware: $firmware)"
        ((counter++))
    done
    
    if [[ ${#all_drives[@]} -eq 0 ]]; then
        echo "No drives detected for firmware updates."
        return 1
    fi
    
    echo ""
    echo "$((counter++)). Exit updater"
    echo ""
    echo -n "Select drive to update (1-$counter): "
    read -r selection
    
    if [[ "$selection" == "$counter" || "$selection" -gt "${#all_drives[@]}" ]]; then
        echo "Exiting firmware updater."
        return 0
    fi
    
    if [[ "$selection" -lt 1 || "$selection" -gt "${#all_drives[@]}" ]]; then
        echo "Invalid selection."
        return 1
    fi
    
    local selected_drive="${all_drives[$((selection-1))]}"
    local selected_info="${drive_info[$((selection-1))]}"
    
    echo ""
    echo -e "${CYAN}Selected drive: $selected_drive${NC}"
    echo "Drive info: $selected_info"
    echo ""
    
    update_selected_drive "$selected_drive"
}

# Function to update a selected drive
update_selected_drive() {
    local device="$1"
    
    echo -e "${BLUE}=== Updating Firmware for $device ===${NC}"
    echo ""
    
    # Determine drive type and manufacturer
    local drive_type="unknown"
    local manufacturer="unknown"
    local model="unknown"
    local current_fw="unknown"
    
    if [[ "$device" =~ nvme ]]; then
        drive_type="nvme"
        if command -v nvme &> /dev/null; then
            model=$(nvme id-ctrl "$device" 2>/dev/null | grep "^mn " | cut -d':' -f2 | xargs || echo "Unknown")
            current_fw=$(nvme id-ctrl "$device" 2>/dev/null | grep "^fr " | awk '{print $3}' || echo "Unknown")
            
            if [[ "$model" =~ [Ss]amsung ]]; then
                manufacturer="samsung"
            elif [[ "$model" =~ [Ii]ntel ]]; then
                manufacturer="intel"
            elif [[ "$model" =~ [Ww]estern.*[Dd]igital|WD ]]; then
                manufacturer="wd"
            elif [[ "$model" =~ [Cc]rucial|[Mm]icron ]]; then
                manufacturer="crucial"
            fi
        fi
    else
        drive_type="sata"
        if command -v smartctl &> /dev/null; then
            local smart_info=$(smartctl -i "$device" 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                model=$(echo "$smart_info" | grep "Device Model" | cut -d':' -f2 | xargs || echo "Unknown")
                current_fw=$(echo "$smart_info" | grep "Firmware Version" | cut -d':' -f2 | xargs || echo "Unknown")
                
                if [[ "$model" =~ [Ss]eagate ]]; then
                    manufacturer="seagate"
                elif [[ "$model" =~ [Ww]estern.*[Dd]igital|WD ]]; then
                    manufacturer="wd"
                elif [[ "$model" =~ [Tt]oshiba ]]; then
                    manufacturer="toshiba"
                elif [[ "$model" =~ HGST ]]; then
                    manufacturer="hgst"
                fi
            fi
        fi
    fi
    
    echo "Drive Details:"
    echo "  Device: $device"
    echo "  Type: $drive_type"
    echo "  Model: $model"
    echo "  Current Firmware: $current_fw"
    echo "  Manufacturer: $manufacturer"
    echo ""
    
    # Provide update guidance based on manufacturer
    case "$manufacturer" in
        "samsung")
            update_samsung_drive "$device" "$model" "$current_fw"
            ;;
        "intel")
            update_intel_drive "$device" "$model" "$current_fw"
            ;;
        "wd")
            update_wd_drive "$device" "$model" "$current_fw"
            ;;
        "seagate")
            update_seagate_drive "$device" "$model" "$current_fw"
            ;;
        "crucial")
            update_crucial_drive "$device" "$model" "$current_fw"
            ;;
        *)
            update_generic_drive "$device" "$model" "$current_fw" "$drive_type"
            ;;
    esac
}

# Function to update Samsung drives
update_samsung_drive() {
    local device="$1"
    local model="$2" 
    local current_fw="$3"
    
    echo -e "${CYAN}Samsung Drive Update Process${NC}"
    echo ""
    
    echo "Current firmware: $current_fw"
    echo ""
    echo "Samsung firmware update options:"
    echo "1. Download firmware manually and use nvme-cli"
    echo "2. Use Samsung Magician (if available for Linux)"
    echo "3. Create bootable update media"
    echo "4. Get firmware download links"
    echo "5. Cancel"
    echo ""
    echo -n "Select update method (1-5): "
    read -r method
    
    case "$method" in
        1)
            samsung_nvme_cli_update "$device" "$model"
            ;;
        2)
            samsung_magician_update "$device" "$model"
            ;;
        3)
            samsung_bootable_update "$device" "$model"
            ;;
        4)
            samsung_download_links "$model"
            ;;
        5)
            echo "Samsung update cancelled."
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
}

# Function for Samsung nvme-cli update
samsung_nvme_cli_update() {
    local device="$1"
    local model="$2"
    
    echo -e "${BLUE}Samsung NVMe-CLI Update Process${NC}"
    echo ""
    echo "Steps to update firmware using nvme-cli:"
    echo ""
    echo "1. First, download the firmware:"
    echo "   - Visit: https://semiconductor.samsung.com/consumer-storage/support/tools/"
    echo "   - Search for your model: $model"
    echo "   - Download firmware package"
    echo ""
    echo "2. Extract the firmware binary (.bin file)"
    echo ""
    echo "3. When ready, I'll help you apply the update"
    echo ""
    
    if confirm_action "Do you have the firmware .bin file ready?"; then
        echo ""
        echo -n "Enter the full path to firmware .bin file: "
        read -r firmware_path
        
        if [[ ! -f "$firmware_path" ]]; then
            echo -e "${RED}Error: Firmware file not found: $firmware_path${NC}"
            return 1
        fi
        
        echo ""
        echo -e "${RED}CRITICAL WARNING:${NC}"
        echo "• Firmware update will begin - DO NOT interrupt or power off!"
        echo "• Ensure UPS power backup if available"
        echo "• Stop all VMs using this drive"
        echo "• This process may take several minutes"
        echo ""
        
        if confirm_action "Proceed with firmware update? This cannot be undone!"; then
            log_message "INFO" "Starting Samsung firmware update for $device with $firmware_path"
            
            echo "Step 1: Downloading firmware to drive..."
            if nvme fw-download "$device" --fw="$firmware_path"; then
                echo -e "${GREEN}✓ Firmware download successful${NC}"
                
                echo ""
                echo "Step 2: Committing firmware (this will reboot the drive)..."
                if nvme fw-commit "$device" --slot=1 --action=1; then
                    echo -e "${GREEN}✓ Firmware commit successful${NC}"
                    echo ""
                    echo -e "${YELLOW}Please reboot the system to complete the update.${NC}"
                    echo "After reboot, run the scanner again to verify new firmware version."
                    log_message "INFO" "Samsung firmware update completed successfully for $device"
                else
                    echo -e "${RED}✗ Firmware commit failed${NC}"
                    log_message "ERROR" "Samsung firmware commit failed for $device"
                fi
            else
                echo -e "${RED}✗ Firmware download failed${NC}"
                log_message "ERROR" "Samsung firmware download failed for $device"
            fi
        fi
    else
        samsung_download_links "$model"
    fi
}

# Function to provide Samsung download links
samsung_download_links() {
    local model="$1"
    
    echo -e "${BLUE}Samsung Firmware Download Information${NC}"
    echo ""
    echo "To download firmware for your $model:"
    echo ""
    echo "1. Visit: https://semiconductor.samsung.com/consumer-storage/support/tools/"
    echo "2. Use the search or browse function"
    echo "3. Look for your exact model: $model"
    echo ""
    echo "Common Samsung NVMe models and their firmware:"
    echo "• 990 PRO series: Look for latest thermal/performance updates"
    echo "• 980 PRO series: Performance optimization updates available"
    echo "• 970 EVO/PRO series: Stability and compatibility updates"
    echo ""
    echo "Download the Linux version if available, or extract .bin from Windows package"
    echo ""
}

# Function for other manufacturer updates (placeholder)
update_intel_drive() {
    local device="$1"
    local model="$2"
    local current_fw="$3"
    
    echo -e "${CYAN}Intel Drive Update Process${NC}"
    echo ""
    echo "Intel firmware update options:"
    echo "1. Download Intel Memory and Storage Tool (intel-mas)"
    echo "2. Manual firmware download and nvme-cli update"  
    echo "3. Get download information"
    echo ""
    echo "Visit: https://www.intel.com/content/www/us/en/support/products/65296/memory-and-storage.html"
    echo ""
    echo "Note: Intel drives often require Intel's official tools for firmware updates."
}

update_wd_drive() {
    local device="$1"
    local model="$2"
    local current_fw="$3"
    
    echo -e "${CYAN}Western Digital Drive Update Process${NC}"
    echo ""
    echo "WD firmware update information:"
    echo "• Visit WD support site: https://support.wdc.com/"
    echo "• Search for your model: $model"
    echo "• Download WD Dashboard or specific firmware updater"
    echo ""
    echo "Current firmware: $current_fw"
    echo ""
    echo "Note: WD updates often require Windows environment or bootable media."
}

update_seagate_drive() {
    local device="$1"
    local model="$2"
    local current_fw="$3"
    
    echo -e "${CYAN}Seagate Drive Update Process${NC}"
    echo ""
    echo "Seagate firmware update information:"
    echo "• Use SeaTools for Linux if available"
    echo "• Visit: https://www.seagate.com/support/downloads/seatools/"
    echo "• Search for model-specific firmware: $model"
    echo ""
    echo "Current firmware: $current_fw"
}

update_crucial_drive() {
    local device="$1"
    local model="$2"
    local current_fw="$3"
    
    echo -e "${CYAN}Crucial/Micron Drive Update Process${NC}"
    echo ""
    echo "Crucial firmware update information:"
    echo "• Use Crucial Storage Executive (check Linux compatibility)"
    echo "• Visit: https://www.crucial.com/support/storage-executive"
    echo "• Search for firmware for: $model"
    echo ""
    echo "Current firmware: $current_fw"
}

update_generic_drive() {
    local device="$1"
    local model="$2"
    local current_fw="$3"
    local drive_type="$4"
    
    echo -e "${CYAN}Generic Drive Update Process${NC}"
    echo ""
    echo "For unknown or generic drives:"
    echo "• Search manufacturer website for: $model"
    echo "• Current firmware: $current_fw"
    echo "• Drive type: $drive_type"
    echo ""
    echo "General approaches:"
    echo "1. Visit manufacturer's support website"
    echo "2. Search for firmware updates using exact model number"
    echo "3. Look for Linux-compatible update tools"
    echo "4. Consider bootable update media if available"
}

# Placeholder functions for Samsung methods
samsung_magician_update() {
    local device="$1"
    local model="$2"
    
    echo -e "${BLUE}Samsung Magician Update${NC}"
    echo ""
    echo "Samsung Magician for Linux (if available):"
    echo "1. Check Samsung's website for Linux version"
    echo "2. Install Samsung Magician"
    echo "3. Run firmware update through the GUI"
    echo ""
    echo "Note: Samsung Magician may not be available for all Linux distributions."
    echo "Consider using nvme-cli method or bootable media instead."
}

samsung_bootable_update() {
    local device="$1"
    local model="$2"
    
    echo -e "${BLUE}Samsung Bootable Update Media${NC}"
    echo ""
    echo "Creating bootable Samsung firmware updater:"
    echo "1. Download Samsung firmware ISO/updater"
    echo "2. Create bootable USB: dd if=samsung_updater.iso of=/dev/sdX bs=4M"
    echo "3. Boot from USB and follow updater instructions"
    echo ""
    echo "This is the safest method for production systems."
}

# Function to confirm action with default
confirm_action() {
    local message="$1"
    echo -e "${YELLOW}$message${NC}"
    echo -n "Continue? [y/N]: "
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
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
    local mode="${1:-menu}"
    
    echo -e "${CYAN}=== Proxmox Firmware Manager ===${NC}"
    echo ""
    
    # Check if running as root
    check_root
    
    # Create log file
    touch "$LOG_FILE"
    
    case "$mode" in
        "scan"|"full")
            log_message "INFO" "Firmware scan started - full mode"
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
            log_message "INFO" "Firmware scan completed"
            ;;
        "quick")
            log_message "INFO" "Firmware scan started - quick mode"
            quick_scan
            log_message "INFO" "Quick firmware scan completed"
            ;;
        "update"|"updater")
            log_message "INFO" "Interactive firmware updater started"
            interactive_firmware_updater
            log_message "INFO" "Interactive firmware updater completed"
            ;;
        "menu"|*)
            # Interactive menu mode
            show_main_menu
            ;;
    esac
}

# Function to show main menu
show_main_menu() {
    echo "Proxmox Firmware Management Tool"
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "1. Scan for firmware versions and get update guidance"
    echo "2. Interactive firmware updater (update selected drives)"
    echo "3. Quick scan (firmware versions only)"
    echo "4. Exit"
    echo ""
    echo -n "Select option (1-4): "
    read -r choice
    
    case "$choice" in
        1)
            echo ""
            echo -e "${BLUE}Starting firmware scan...${NC}"
            echo ""
            log_message "INFO" "Firmware scan started from menu - full mode"
            
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
            log_message "INFO" "Firmware scan completed"
            ;;
        2)
            echo ""
            echo -e "${BLUE}Starting interactive firmware updater...${NC}"
            echo ""
            log_message "INFO" "Interactive firmware updater started from menu"
            interactive_firmware_updater
            log_message "INFO" "Interactive firmware updater completed"
            ;;
        3)
            echo ""
            echo -e "${BLUE}Starting quick scan...${NC}"
            echo ""
            log_message "INFO" "Quick firmware scan started from menu"
            quick_scan
            log_message "INFO" "Quick firmware scan completed"
            ;;
        4)
            echo "Exiting firmware manager."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please select 1-4.${NC}"
            exit 1
            ;;
    esac
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [mode]"
    echo ""
    echo "Proxmox Firmware Manager"
    echo "Comprehensive tool for scanning and updating NVMe and HDD firmware"
    echo ""
    echo "Modes:"
    echo "  (no args)      - Interactive menu with all options"
    echo "  menu           - Interactive menu with all options"
    echo "  scan / full    - Full scan with detailed analysis and recommendations"
    echo "  quick          - Quick scan showing only current firmware versions"
    echo "  update         - Interactive firmware updater for selected drives"
    echo "  updater        - Interactive firmware updater for selected drives"
    echo ""
    echo "Features:"
    echo "  Option 1: Firmware Scanner"
    echo "    - Detect NVMe and SATA/HDD drives"
    echo "    - Report current firmware versions"
    echo "    - Provide manufacturer-specific update guidance"
    echo "    - Generate detailed report with recommendations"
    echo ""
    echo "  Option 2: Interactive Firmware Updater"
    echo "    - List all detected drives with current firmware"
    echo "    - Select specific drive to update"
    echo "    - Guided update process with safety checks"
    echo "    - Manufacturer-specific update procedures"
    echo "    - Built-in Samsung NVMe update support with nvme-cli"
    echo ""
    echo "Output files:"
    echo "  Report: $REPORT_FILE"
    echo "  Log: $LOG_FILE"
    echo ""
    echo "Examples:"
    echo "  $0              # Interactive menu"
    echo "  $0 menu         # Interactive menu"
    echo "  $0 scan         # Full firmware scan only"
    echo "  $0 quick        # Quick firmware version check"
    echo "  $0 update       # Interactive firmware updater"
    echo ""
    echo "Samsung NVMe Update Support:"
    echo "  - Automatic Samsung drive detection"
    echo "  - Multiple update methods (nvme-cli, Magician, bootable)"
    echo "  - Step-by-step guided updates with safety checks"
    echo "  - Support for 990 PRO, 980 PRO and other Samsung NVMe drives"
    echo ""
    echo "Note: This script requires root privileges to access drive information"
    echo "      Firmware updates are potentially risky - always backup data first!"
    exit 0
fi

# Run main function
main "$@"
