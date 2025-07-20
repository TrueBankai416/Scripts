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
        
        # Also install Samsung ISO decryption tools for complete functionality
        echo "Installing Samsung ISO decryption tools..."
        apt install -y p7zip-full openssl xxd binutils
        echo -e "${GREEN}✓ Samsung ISO decryption tools installed${NC}"
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

# Samsung Magician / DC Toolkit update function
samsung_magician_update() {
    local device="$1"
    local model="$2"
    
    echo -e "${BLUE}Samsung DC Toolkit / Magician Update${NC}"
    echo ""
    echo "Samsung DC Toolkit is the recommended tool for Samsung NVMe firmware updates."
    echo "This will search for and download the latest version from Samsung's website."
    echo ""
    
    if confirm_action "Proceed with DC Toolkit and firmware search and download?"; then
        search_and_download_samsung_complete "$device" "$model"
    else
        echo "DC Toolkit search cancelled. Use other methods or manual download."
        samsung_download_links "$model"
    fi
}

# Function to search and download both DC Toolkit and firmware
search_and_download_samsung_complete() {
    local device="$1"
    local model="$2"
    
    echo -e "${CYAN}Samsung Complete Update Package Search${NC}"
    echo ""
    echo "This will search for and download both:"
    echo "1. Samsung DC Toolkit (update tool) - automatically made executable"
    echo "2. Latest firmware for your $model - including ISO decryption if needed"
    echo ""
    
    # Check for ISO decryption tools early
    check_iso_decryption_tools
    echo ""
    
    local base_url="https://semiconductor.samsung.com/consumer-storage/support/tools/"
    local temp_dir="/tmp/samsung_complete_$$"
    
    mkdir -p "$temp_dir"
    cd "$temp_dir" || exit 1
    
    echo "Step 1: Searching for DC Toolkit and firmware..."
    log_message "INFO" "Starting complete Samsung update package search for $model"
    
    # Search for both DC Toolkit and firmware simultaneously
    search_dc_toolkit_and_firmware "$device" "$model" "$base_url" "$temp_dir"
    
    # Cleanup
    cd - >/dev/null 2>&1
    # Don't remove temp_dir yet as it contains downloaded files
}

# Function to search for both DC Toolkit and model-specific firmware
search_dc_toolkit_and_firmware() {
    local device="$1"
    local model="$2"
    local base_url="$3"
    local temp_dir="$4"
    
    echo "Downloading Samsung tools and firmware pages..."
    
    # Download main tools page
    local tools_page="$temp_dir/tools_page.html"
    local toolkit_found=false
    local firmware_found=false
    
    if curl -L -s -o "$tools_page" "$base_url" 2>/dev/null; then
        echo -e "${GREEN}✓ Downloaded tools page${NC}"
        
        # Search for DC Toolkit
        echo "Step 2a: Searching for DC Toolkit..."
        search_for_dc_toolkit "$tools_page" "$device" "$model" "$temp_dir"
        toolkit_found=$?
        
        # Search for firmware
        echo "Step 2b: Searching for model-specific firmware..."  
        search_for_firmware "$tools_page" "$device" "$model" "$temp_dir"
        firmware_found=$?
        
        # Also try firmware-specific URL patterns
        search_firmware_additional_sources "$device" "$model" "$temp_dir"
        
    else
        echo -e "${RED}✗ Could not access Samsung tools page${NC}"
        manual_complete_download "$device" "$model"
        return 1
    fi
    
    # Process results
    if [[ $toolkit_found -eq 0 || $firmware_found -eq 0 ]]; then
        echo ""
        echo "=== Download Summary ==="
        [[ $toolkit_found -eq 0 ]] && echo -e "${GREEN}✓ DC Toolkit: Found and downloaded${NC}"
        [[ $toolkit_found -ne 0 ]] && echo -e "${YELLOW}⚠ DC Toolkit: Not found automatically${NC}"
        [[ $firmware_found -eq 0 ]] && echo -e "${GREEN}✓ Firmware: Found and downloaded${NC}"
        [[ $firmware_found -ne 0 ]] && echo -e "${YELLOW}⚠ Firmware: Not found automatically${NC}"
        echo ""
        
        prepare_samsung_update_package "$device" "$model" "$temp_dir"
    else
        echo -e "${YELLOW}Neither DC Toolkit nor firmware found automatically${NC}"
        manual_complete_download "$device" "$model"
    fi
}

# Function to search for DC Toolkit specifically
search_for_dc_toolkit() {
    local tools_page="$1"
    local device="$2"
    local model="$3"
    local temp_dir="$4"
    
    # DC Toolkit search patterns
    local dc_toolkit_patterns=(
        "DC.*[Tt]oolkit.*Linux"
        "DC.*[Tt]oolkit.*linux"
        "dcToolkit.*linux"
        "Samsung.*DC.*Toolkit"
        "magician.*linux"
        "nvme.*tool.*linux"
        "firmware.*update.*tool"
    )
    
    local found_links=()
    for pattern in "${dc_toolkit_patterns[@]}"; do
        local links=$(grep -io 'href="[^"]*"[^>]*'"$pattern" "$tools_page" 2>/dev/null | sed 's/href="//;s/".*//' | head -3)
        if [[ -n "$links" ]]; then
            while IFS= read -r link; do
                # Filter out invalid JavaScript links and empty/invalid URLs
                if [[ -n "$link" && ! "$link" =~ javascript:|void\(0\)|^#|^$ ]]; then
                    found_links+=("$link")
                fi
            done <<< "$links"
        fi
    done
    
    # Search for direct download links to Samsung tools (bypass popups)
    local direct_links=$(grep -io 'href="[^"]*download[^"]*\(magician\|toolkit\|dc.*tool\)[^"]*"' "$tools_page" 2>/dev/null | sed 's/href="//' | sed 's/"//')
    if [[ -n "$direct_links" ]]; then
        while IFS= read -r link; do
            [[ -n "$link" && ! "$link" =~ javascript:|void\(0\) ]] && found_links+=("$link")
        done <<< "$direct_links"
    fi
    
    # Also search for Samsung download domain links
    local samsung_download_links=$(grep -io 'https://download\.semiconductor\.samsung\.com[^"]*\(toolkit\|magician\|DC\)[^"]*' "$tools_page" 2>/dev/null)
    if [[ -n "$samsung_download_links" ]]; then
        while IFS= read -r link; do
            [[ -n "$link" ]] && found_links+=("$link")
        done <<< "$samsung_download_links"
    fi
    
    # Search for known Samsung DC Toolkit patterns
    local known_patterns=(
        "Samsung_SSD_DC_Toolkit.*Linux.*V[0-9]"
        "Samsung_Magician_DC_Linux"
        "dc.*toolkit.*linux"
    )
    
    for pattern in "${known_patterns[@]}"; do
        local toolkit_links=$(grep -io 'https://[^"]*'"$pattern"'[^"]*' "$tools_page" 2>/dev/null)
        if [[ -n "$toolkit_links" ]]; then
            while IFS= read -r link; do
                [[ -n "$link" ]] && found_links+=("$link")
            done <<< "$toolkit_links"
        fi
    done
    
    if [[ ${#found_links[@]} -gt 0 ]]; then
        echo -e "${GREEN}Found DC Toolkit download links:${NC}"
        for link in "${found_links[@]}"; do
            # Make sure link is absolute
            if [[ "$link" =~ ^/ ]]; then
                link="https://semiconductor.samsung.com$link"
            elif [[ ! "$link" =~ ^https?:// ]]; then
                link="https://semiconductor.samsung.com/consumer-storage/support/tools/$link"
            fi
            echo "  • $link"
        done
        
        # Download the first promising link
        local download_link="${found_links[0]}"
        if [[ "$download_link" =~ ^/ ]]; then
            download_link="https://semiconductor.samsung.com$download_link"
        elif [[ ! "$download_link" =~ ^https?:// ]]; then
            download_link="https://semiconductor.samsung.com/consumer-storage/support/tools/$download_link"
        fi
        
        download_dc_toolkit_file "$download_link" "$temp_dir"
        return $?
    else
        echo -e "${YELLOW}No DC Toolkit links found in tools page - trying known direct URLs${NC}"
        try_known_dc_toolkit_urls "$temp_dir"
        return $?
    fi
}

# Function to try known Samsung DC Toolkit direct URLs with version detection
try_known_dc_toolkit_urls() {
    local temp_dir="$1"
    
    echo "Trying Samsung DC Toolkit direct download URLs with version detection..."
    
    # Base URL pattern for Samsung DC Toolkit
    local base_url="https://download.semiconductor.samsung.com/resources/software-resources"
    
    # Try different version patterns based on the known naming scheme
    local version_patterns=(
        "Samsung_SSD_DC_Toolkit_Brand_for_Linux_V4.0"
        "Samsung_SSD_DC_Toolkit_Brand_for_Linux_V3.1"
        "Samsung_SSD_DC_Toolkit_Brand_for_Linux_V3.2"
        "Samsung_SSD_DC_Toolkit_Brand_for_Linux_V3.0"
        "Samsung_SSD_DC_Toolkit_Linux_64bit.tar.gz"
        "Samsung_Magician_DC_Linux_64bit.zip"
        "Samsung_SSD_DC_Toolkit_for_Linux_V3.0"
        "Samsung_DC_Toolkit_Linux_V3.0"
    )
    
    echo "Probing for latest version..."
    local found_version=""
    local found_url=""
    
    for pattern in "${version_patterns[@]}"; do
        local test_url="$base_url/$pattern"
        echo "Testing: $(basename "$pattern")"
        
        # Try a HEAD request to check if the URL exists
        local http_code=$(curl -I -L -s -w "%{http_code}" -o /dev/null "$test_url" 2>/dev/null)
        
        if [[ "$http_code" == "200" ]]; then
            echo -e "  ${GREEN}✓ HTTP $http_code - Available${NC}"
            found_version="$pattern"
            found_url="$test_url"
            log_message "INFO" "Found available Samsung DC Toolkit: $pattern"
            
            # Download the first available version (they're ordered by preference)
            download_dc_toolkit_file "$found_url" "$temp_dir"
            return $?
        else
            echo "  HTTP $http_code - Not available"
        fi
    done
    
    # If no versioned URLs work, try some additional patterns
    echo ""
    echo "Trying additional Samsung tool patterns..."
    local additional_patterns=(
        "Samsung_Magician_Linux.tar.gz"
        "Samsung_NVMe_Tools_Linux.zip"
        "DC_Toolkit_Linux.tar.gz"
    )
    
    for pattern in "${additional_patterns[@]}"; do
        local test_url="$base_url/$pattern"
        echo "Testing: $(basename "$pattern")"
        
        local http_code=$(curl -I -L -s -w "%{http_code}" -o /dev/null "$test_url" 2>/dev/null)
        
        if [[ "$http_code" == "200" ]]; then
            echo -e "  ${GREEN}✓ HTTP $http_code - Available${NC}"
            found_url="$test_url"
            
            download_dc_toolkit_file "$found_url" "$temp_dir"
            return $?
        else
            echo "  HTTP $http_code - Not available"
        fi
    done
    
    echo -e "${RED}✗ No Samsung DC Toolkit found at known direct URLs${NC}"
    echo "This might mean:"
    echo "• Samsung has changed their download URL structure"
    echo "• New version with different naming scheme"
    echo "• Download requires authentication or newer access method"
    echo ""
    echo "Manual download suggestion:"
    echo "• Visit: https://semiconductor.samsung.com/consumer-storage/support/tools/"
    echo "• Look for DC Toolkit or Magician downloads"
    echo "• Check popup dialogs for direct download links"
    
    return 1
}

# Function to search for model-specific firmware
search_for_firmware() {
    local tools_page="$1"
    local device="$2"
    local model="$3"
    local temp_dir="$4"
    
    # Extract model number/series for firmware search
    local model_clean=$(echo "$model" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]//g')
    local model_series=""
    
    # Identify Samsung series
    if [[ "$model" =~ 990.*PRO ]]; then
        model_series="990PRO"
    elif [[ "$model" =~ 980.*PRO ]]; then
        model_series="980PRO" 
    elif [[ "$model" =~ 970.*PRO ]]; then
        model_series="970PRO"
    elif [[ "$model" =~ 970.*EVO ]]; then
        model_series="970EVO"
    elif [[ "$model" =~ 980 ]]; then
        model_series="980"
    elif [[ "$model" =~ 990 ]]; then
        model_series="990"
    fi
    
    echo "Searching firmware for model: $model (series: $model_series)"
    log_message "INFO" "Searching firmware for Samsung model: $model, series: $model_series"
    
    # Firmware search patterns
    local firmware_patterns=(
        "$model_series.*firmware"
        "$model_series.*update"
        "firmware.*$model_series"  
        "$model_clean.*firmware"
        "$model_clean.*update"
        "990.*PRO.*firmware"
        "980.*PRO.*firmware"
        "970.*firmware"
    )
    
    local firmware_links=()
    for pattern in "${firmware_patterns[@]}"; do
        local links=$(grep -io 'href="[^"]*"[^>]*'"$pattern" "$tools_page" 2>/dev/null | sed 's/href="//;s/".*//' | head -5)
        if [[ -n "$links" ]]; then
            while IFS= read -r link; do
                # Filter out JavaScript links and only include actual file downloads
                if [[ -n "$link" && ! "$link" =~ javascript:|void\(0\)|^#|^$ ]] && [[ "$link" =~ \.(iso|bin|zip|tar\.gz)$ ]]; then
                    firmware_links+=("$link")
                fi
            done <<< "$links"
        fi
    done
    
    # Also search for direct Samsung firmware ISO links
    local iso_links=$(grep -io 'href="[^"]*samsung.*\(990\|980\|970\).*\.\(iso\|bin\)"' "$tools_page" 2>/dev/null | sed 's/href="//' | sed 's/"//')
    if [[ -n "$iso_links" ]]; then
        while IFS= read -r link; do
            [[ -n "$link" && ! "$link" =~ javascript:|void\(0\) ]] && firmware_links+=("$link")
        done <<< "$iso_links"
    fi
    
    if [[ ${#firmware_links[@]} -gt 0 ]]; then
        echo -e "${GREEN}Found potential firmware downloads:${NC}"
        for link in "${firmware_links[@]}"; do
            # Make sure link is absolute
            if [[ "$link" =~ ^/ ]]; then
                link="https://semiconductor.samsung.com$link"
            elif [[ ! "$link" =~ ^https?:// ]]; then
                link="https://semiconductor.samsung.com/consumer-storage/support/tools/$link"
            fi
            echo "  • $link"
        done
        
        # Download the most promising firmware link
        local firmware_link="${firmware_links[0]}"
        if [[ "$firmware_link" =~ ^/ ]]; then
            firmware_link="https://semiconductor.samsung.com$firmware_link"
        elif [[ ! "$firmware_link" =~ ^https?:// ]]; then
            firmware_link="https://semiconductor.samsung.com/consumer-storage/support/tools/$firmware_link"
        fi
        
        download_firmware_file "$firmware_link" "$model_series" "$temp_dir"
        return $?
    else
        echo -e "${YELLOW}No firmware links found for $model in tools page${NC}"
        return 1
    fi
}

# Function to search additional firmware sources
search_firmware_additional_sources() {
    local device="$1"
    local model="$2"
    local temp_dir="$3"
    
    echo "Step 2c: Checking additional firmware sources..."
    
    # Try common Samsung firmware URL patterns
    local additional_urls=(
        "https://semiconductor.samsung.com/consumer-storage/support/downloads/"
        "https://semiconductor.samsung.com/consumer-storage/support/firmware/"
        "https://semiconductor.samsung.com/consumer-storage/ssd/firmware/"
    )
    
    for url in "${additional_urls[@]}"; do
        echo "Checking: $url"
        local page_file="$temp_dir/additional_$(basename "$url").html"
        
        if curl -L -s -o "$page_file" "$url" 2>/dev/null; then
            search_for_firmware "$page_file" "$device" "$model" "$temp_dir"
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}✓ Found firmware in additional source${NC}"
                return 0
            fi
        fi
    done
    
    echo -e "${YELLOW}No firmware found in additional sources${NC}"
    return 1
}

# Function to download DC Toolkit file
download_dc_toolkit_file() {
    local download_url="$1"
    local temp_dir="$2"
    
    echo "Downloading DC Toolkit from: $download_url"
    
    local filename=$(basename "$download_url")
    [[ -z "$filename" || "$filename" == "/" ]] && filename="samsung_dc_toolkit.tar.gz"
    local toolkit_file="$temp_dir/$filename"
    
    if curl -L -o "$toolkit_file" "$download_url" 2>/dev/null; then
        local file_size=$(stat -c%s "$toolkit_file" 2>/dev/null || echo "0")
        
        if [[ $file_size -gt 1024 ]]; then
            echo -e "${GREEN}✓ Downloaded DC Toolkit: $filename ($file_size bytes)${NC}"
            log_message "INFO" "Successfully downloaded Samsung DC Toolkit: $filename"
            
            # Make executable if it's a direct executable
            if file "$toolkit_file" | grep -q "executable"; then
                chmod +x "$toolkit_file"
                echo -e "${GREEN}✓ Made DC Toolkit executable${NC}"
            fi
            
            return 0
        else
            echo -e "${RED}✗ Downloaded toolkit file is too small${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ DC Toolkit download failed${NC}"
        return 1
    fi
}

# Function to download firmware file
download_firmware_file() {
    local download_url="$1"
    local model_series="$2"
    local temp_dir="$3"
    
    echo "Downloading firmware from: $download_url"
    
    local filename=$(basename "$download_url")
    [[ -z "$filename" || "$filename" == "/" ]] && filename="samsung_${model_series}_firmware.bin"
    local firmware_file="$temp_dir/$filename"
    
    if curl -L -o "$firmware_file" "$download_url" 2>/dev/null; then
        local file_size=$(stat -c%s "$firmware_file" 2>/dev/null || echo "0")
        
        if [[ $file_size -gt 1024 ]]; then
            echo -e "${GREEN}✓ Downloaded firmware: $filename ($file_size bytes)${NC}"
            log_message "INFO" "Successfully downloaded Samsung firmware: $filename for $model_series"
            
            # Check if it's a Samsung ISO that needs decryption
            if [[ "$filename" =~ \.iso$ ]] || file "$firmware_file" | grep -qi "iso.*9660"; then
                echo "Step 2c: Detected Samsung firmware ISO - attempting decryption..."
                decrypt_samsung_iso "$firmware_file" "$temp_dir" "$model_series"
                local decrypt_result=$?
                
                if [[ $decrypt_result -eq 0 ]]; then
                    echo -e "${GREEN}✓ Samsung ISO decrypted and .bin files extracted${NC}"
                else
                    echo -e "${YELLOW}⚠ ISO decryption failed or not needed - continuing with original file${NC}"
                fi
            fi
            
            return 0
        else
            echo -e "${RED}✗ Downloaded firmware file is too small${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Firmware download failed${NC}"
        return 1
    fi
}

# Function to decrypt Samsung firmware ISO and extract .bin files
decrypt_samsung_iso() {
    local iso_file="$1"
    local temp_dir="$2"
    local model_series="$3"
    
    echo "Samsung ISO Decryption Process"
    echo "ISO file: $(basename "$iso_file")"
    
    # Check for required tools
    local missing_tools=()
    if ! command -v 7z &> /dev/null; then
        missing_tools+=("7z (p7zip-full)")
    fi
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    if ! command -v xxd &> /dev/null; then
        missing_tools+=("xxd")
    fi
    if ! command -v strings &> /dev/null; then
        missing_tools+=("strings (binutils)")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Missing required tools for Samsung ISO decryption:${NC}"
        for tool in "${missing_tools[@]}"; do
            echo "  • $tool"
        done
        echo ""
        echo "Install missing tools:"
        echo "  Ubuntu/Debian: sudo apt install p7zip-full openssl xxd binutils"
        echo "  CentOS/RHEL: sudo yum install p7zip openssl xxd binutils"
        echo ""
        echo "Skipping ISO decryption - firmware will remain as ISO file"
        return 1
    fi
    
    local iso_work_dir="$temp_dir/samsung_iso_work_$$"
    mkdir -p "$iso_work_dir"
    cd "$iso_work_dir" || return 1
    
    echo "Step 1: Extracting Samsung ISO..."
    log_message "INFO" "Starting Samsung ISO decryption for $(basename "$iso_file")"
    
    # Extract the ISO
    if ! 7z x -y -otmp "$iso_file" >/dev/null 2>&1; then
        echo -e "${RED}✗ Failed to extract ISO file${NC}"
        cleanup_iso_work "$iso_work_dir"
        return 1
    fi
    echo -e "${GREEN}✓ ISO extracted${NC}"
    
    # Extract initrd
    echo "Step 2: Extracting initrd..."
    if [[ -f "tmp/initrd" ]]; then
        if ! 7z x -y -otmp/ tmp/initrd >/dev/null 2>&1; then
            echo -e "${RED}✗ Failed to extract initrd${NC}"
            cleanup_iso_work "$iso_work_dir"
            return 1
        fi
        echo -e "${GREEN}✓ initrd extracted${NC}"
    else
        echo -e "${RED}✗ initrd not found in ISO${NC}"
        cleanup_iso_work "$iso_work_dir"
        return 1
    fi
    
    # Extract fumagician
    echo "Step 3: Extracting fumagician..."
    if [[ -f "tmp/initrd~" ]]; then
        if ! 7z x -y -otmp/ tmp/initrd~ root/fumagician >/dev/null 2>&1; then
            echo -e "${RED}✗ Failed to extract fumagician${NC}"
            cleanup_iso_work "$iso_work_dir"
            return 1
        fi
        echo -e "${GREEN}✓ fumagician extracted${NC}"
    else
        echo -e "${RED}✗ initrd~ not found${NC}"
        cleanup_iso_work "$iso_work_dir"
        return 1
    fi
    
    # Extract decryption key
    echo "Step 4: Extracting decryption key..."
    local fumagician_binary="tmp/root/fumagician/fumagician"
    
    if [[ ! -f "$fumagician_binary" ]]; then
        echo -e "${RED}✗ fumagician binary not found${NC}"
        cleanup_iso_work "$iso_work_dir"
        return 1
    fi
    
    # Get the key using the same method as the reference script
    local key_raw=$(strings "$fumagician_binary" | grep -A 2 printk | tail -1 | base64 -d 2>/dev/null | xxd -p -c 100 2>/dev/null)
    
    if [[ -z "$key_raw" ]]; then
        echo -e "${RED}✗ Failed to extract decryption key from fumagician${NC}"
        cleanup_iso_work "$iso_work_dir"
        return 1
    fi
    
    echo -e "${GREEN}✓ Decryption key extracted${NC}"
    log_message "INFO" "Samsung decryption key extracted successfully"
    
    # Decrypt .enc files
    echo "Step 5: Decrypting firmware files..."
    local decrypted_count=0
    local bin_files=()
    
    for enc_file in tmp/root/fumagician/*.enc; do
        if [[ -f "$enc_file" ]]; then
            local base_name=$(basename "${enc_file%.enc}")
            local bin_file="$temp_dir/${base_name}.bin"
            local magic_file="$temp_dir/${base_name}.magic"
            
            echo "Decrypting: $base_name.enc"
            
            # Decrypt main firmware data (skip first 32 bytes, decrypt with AES-256-ECB)
            if dd if="$enc_file" bs=32 skip=1 status=none 2>/dev/null | \
               openssl enc -aes-256-ecb -d -out "$bin_file" -nopad -K "$key_raw" 2>/dev/null; then
                
                # Also decrypt the magic/header (first 32 bytes)
                dd if="$enc_file" bs=32 count=1 status=none 2>/dev/null | \
                   openssl enc -aes-256-ecb -d -out "$magic_file" -nopad -K "$key_raw" 2>/dev/null
                
                local bin_size=$(stat -c%s "$bin_file" 2>/dev/null || echo "0")
                if [[ $bin_size -gt 0 ]]; then
                    echo -e "  ${GREEN}✓ $base_name.bin ($bin_size bytes)${NC}"
                    bin_files+=("$bin_file")
                    ((decrypted_count++))
                    log_message "INFO" "Decrypted Samsung firmware: $base_name.bin"
                else
                    echo -e "  ${RED}✗ $base_name.bin (decryption failed)${NC}"
                    rm -f "$bin_file" "$magic_file"
                fi
            else
                echo -e "  ${RED}✗ Failed to decrypt $base_name.enc${NC}"
            fi
        fi
    done
    
    # Cleanup temporary extraction files
    cleanup_iso_work "$iso_work_dir"
    
    if [[ $decrypted_count -gt 0 ]]; then
        echo ""
        echo -e "${GREEN}Samsung ISO decryption completed successfully!${NC}"
        echo "Decrypted $decrypted_count firmware file(s):"
        for bin_file in "${bin_files[@]}"; do
            echo "  • $(basename "$bin_file")"
        done
        echo ""
        return 0
    else
        echo -e "${RED}✗ No firmware files were successfully decrypted${NC}"
        return 1
    fi
}

# Function to cleanup ISO extraction working directory
cleanup_iso_work() {
    local work_dir="$1"
    cd / 2>/dev/null
    rm -rf "$work_dir" 2>/dev/null
}

# Function to check for ISO decryption tools availability
check_iso_decryption_tools() {
    echo "Checking Samsung ISO decryption tools..."
    
    local missing_tools=()
    local available_tools=()
    
    if command -v 7z &> /dev/null; then
        available_tools+=("7z")
    else
        missing_tools+=("7z (p7zip-full)")
    fi
    
    if command -v openssl &> /dev/null; then
        available_tools+=("openssl")
    else
        missing_tools+=("openssl")
    fi
    
    if command -v xxd &> /dev/null; then
        available_tools+=("xxd")
    else
        missing_tools+=("xxd")
    fi
    
    if command -v strings &> /dev/null; then
        available_tools+=("strings")
    else
        missing_tools+=("strings (binutils)")
    fi
    
    if [[ ${#available_tools[@]} -eq 4 ]]; then
        echo -e "${GREEN}✓ All ISO decryption tools available: ${available_tools[*]}${NC}"
        echo "Samsung firmware ISOs can be automatically decrypted and .bin files extracted"
    else
        echo -e "${YELLOW}⚠ Some ISO decryption tools missing: ${missing_tools[*]}${NC}"
        echo ""
        
        if confirm_action "Install missing Samsung ISO decryption tools now?"; then
            echo "Installing missing tools..."
            log_message "INFO" "Installing Samsung ISO decryption tools: ${missing_tools[*]}"
            
            # Detect package manager and install
            if command -v apt &> /dev/null; then
                apt update -qq
                apt install -y p7zip-full openssl xxd binutils
                echo -e "${GREEN}✓ Samsung ISO decryption tools installed${NC}"
            elif command -v yum &> /dev/null; then
                yum install -y p7zip openssl xxd binutils
                echo -e "${GREEN}✓ Samsung ISO decryption tools installed${NC}"
            elif command -v dnf &> /dev/null; then
                dnf install -y p7zip openssl xxd binutils  
                echo -e "${GREEN}✓ Samsung ISO decryption tools installed${NC}"
            else
                echo -e "${RED}Unable to auto-install - manual installation required${NC}"
                echo "Install missing tools manually:"
                echo "  Ubuntu/Debian: sudo apt install p7zip-full openssl xxd binutils"
                echo "  CentOS/RHEL: sudo yum install p7zip openssl xxd binutils"
                echo "  Fedora: sudo dnf install p7zip openssl xxd binutils"
                return
            fi
            
            echo "Samsung firmware ISOs can now be automatically decrypted"
            log_message "INFO" "Samsung ISO decryption tools installation completed"
        else
            echo "If Samsung firmware is downloaded as encrypted ISO, manual decryption will be needed"
            echo ""
            echo "Install missing tools manually:"
            echo "  Ubuntu/Debian: sudo apt install p7zip-full openssl xxd binutils"
            echo "  CentOS/RHEL: sudo yum install p7zip openssl xxd binutils"
            echo "  Fedora: sudo dnf install p7zip openssl xxd binutils"
        fi
    fi
}

# Function to prepare the complete Samsung update package
prepare_samsung_update_package() {
    local device="$1"
    local model="$2"
    local temp_dir="$3"
    
    echo ""
    echo -e "${BLUE}=== Preparing Samsung Update Package ===${NC}"
    echo ""
    
    # List downloaded files
    echo "Downloaded files:"
    ls -la "$temp_dir"/ | grep -v "^total\|^d" | while read -r line; do
        echo "  $line"
    done
    echo ""
    
    # Find toolkit executable
    local toolkit_exec=""
    local firmware_file=""
    
    # Look for toolkit executables or archives
    for file in "$temp_dir"/*; do
        if [[ -f "$file" ]]; then
            local basename_file=$(basename "$file")
            
            # Check if it's a toolkit
            if [[ "$basename_file" =~ dc.*toolkit|magician|samsung.*tool ]] || file "$file" | grep -q "executable"; then
                toolkit_exec="$file"
                # Make sure it's executable
                chmod +x "$file" 2>/dev/null
                echo -e "${GREEN}✓ Found and made executable: $basename_file${NC}"
            fi
            
            # Check if it's firmware (.bin, .rom, etc.) - exclude HTML files
            if [[ "$basename_file" =~ \.bin$|\.rom$|\.fw$|\.iso$ ]] && [[ ! "$basename_file" =~ \.html?$ ]]; then
                # Double-check it's not an HTML file by checking file type
                if ! file "$file" | grep -qi "html\|text"; then
                    firmware_file="$file"
                    echo -e "${GREEN}✓ Found firmware file: $basename_file${NC}"
                fi
            elif [[ "$basename_file" =~ firmware ]] && [[ "$basename_file" =~ \.iso$|\.bin$ ]]; then
                # Only accept firmware-named files if they're ISO or BIN and not HTML
                if ! file "$file" | grep -qi "html\|text"; then
                    firmware_file="$file"
                    echo -e "${GREEN}✓ Found firmware file: $basename_file${NC}"
                fi
            fi
        fi
    done
    
    # Extract archives if needed
    if [[ -z "$toolkit_exec" ]]; then
        echo "No direct executable found, checking for archives to extract..."
        extract_samsung_packages "$temp_dir"
        
        # Re-scan for executables after extraction with better filtering
        echo "Searching for DC Toolkit executables after extraction..."
        local potential_execs=$(find "$temp_dir" -type f \( -name "*toolkit*" -o -name "*magician*" -o -name "*samsung*" \) 2>/dev/null)
        
        if [[ -n "$potential_execs" ]]; then
            echo "Found potential executable files:"
            while IFS= read -r exec_file; do
                echo "  • $(basename "$exec_file")"
                
                # Check if it's a real executable file (not directory)
                if [[ -f "$exec_file" ]] && (file "$exec_file" | grep -qi "executable\|elf" || [[ "$exec_file" =~ \.(sh|run)$ ]]); then
                    toolkit_exec="$exec_file"
                    chmod +x "$toolkit_exec"
                    echo -e "${GREEN}✓ Found and made executable: $(basename "$toolkit_exec")${NC}"
                    break
                fi
            done <<< "$potential_execs"
        fi
        
        # If still no executable found, look more broadly
        if [[ -z "$toolkit_exec" ]]; then
            echo "Searching for any executable files in extracted content..."
            toolkit_exec=$(find "$temp_dir" -type f -executable 2>/dev/null | head -1)
            if [[ -n "$toolkit_exec" ]]; then
                echo -e "${GREEN}✓ Found executable: $(basename "$toolkit_exec")${NC}"
                chmod +x "$toolkit_exec"
            fi
        fi
    fi
    
    # Re-scan for firmware files after extraction and ISO decryption
    if [[ -z "$firmware_file" ]]; then
        # First priority: Look for decrypted .bin files
        firmware_file=$(find "$temp_dir" -name "*.bin" -o -name "*.rom" -o -name "*.fw" 2>/dev/null | grep -v "\.html" | head -1)
        if [[ -n "$firmware_file" ]] && ! file "$firmware_file" | grep -qi "html\|text"; then
            echo -e "${GREEN}✓ Found decrypted firmware file: $(basename "$firmware_file")${NC}"
        else
            # Second priority: Look for Samsung ISO files (if decryption failed)
            firmware_file=$(find "$temp_dir" -name "*.iso" 2>/dev/null | grep -E "Samsung|990|980|970" | head -1)
            if [[ -n "$firmware_file" ]] && ! file "$firmware_file" | grep -qi "html\|text"; then
                echo -e "${GREEN}✓ Found Samsung firmware ISO: $(basename "$firmware_file")${NC}"
                echo "  Note: ISO file will be used as-is (decryption failed or was skipped)"
            else
                # Third priority: Any legitimate firmware files
                firmware_file=$(find "$temp_dir" -name "*firmware*" -o -name "*DSRD*" -o -name "*990PRO*" -o -name "*980PRO*" 2>/dev/null | grep -v "\.html" | head -1)
                if [[ -n "$firmware_file" ]] && ! file "$firmware_file" | grep -qi "html\|text"; then
                    echo -e "${GREEN}✓ Found Samsung firmware package: $(basename "$firmware_file")${NC}"
                fi
            fi
        fi
    fi
    
    echo ""
    echo "=== Update Package Ready ==="
    echo "Device: $device"
    echo "Model: $model"
    [[ -n "$toolkit_exec" ]] && echo "DC Toolkit: $(basename "$toolkit_exec")" || echo "DC Toolkit: Not found"
    [[ -n "$firmware_file" ]] && echo "Firmware: $(basename "$firmware_file")" || echo "Firmware: Not found" 
    echo "Location: $temp_dir"
    echo ""
    
    # Offer to proceed with update
    launch_complete_samsung_update "$device" "$model" "$toolkit_exec" "$firmware_file" "$temp_dir"
}

# Function to extract Samsung packages
extract_samsung_packages() {
    local temp_dir="$1"
    
    for file in "$temp_dir"/*; do
        if [[ -f "$file" ]]; then
            local basename_file=$(basename "$file")
            
            if [[ "$basename_file" =~ \.tar\.gz$|\.tgz$ ]]; then
                echo "Extracting TAR.GZ: $basename_file"
                tar -xzf "$file" -C "$temp_dir" 2>/dev/null && echo -e "${GREEN}✓ Extracted${NC}"
            elif [[ "$basename_file" =~ \.zip$ ]] && command -v unzip &> /dev/null; then
                echo "Extracting ZIP: $basename_file"
                unzip -q "$file" -d "$temp_dir" 2>/dev/null && echo -e "${GREEN}✓ Extracted${NC}"
            fi
        fi
    done
}

# Function to launch complete Samsung update
launch_complete_samsung_update() {
    local device="$1"
    local model="$2"
    local toolkit_exec="$3"
    local firmware_file="$4"
    local temp_dir="$5"
    
    if [[ -n "$toolkit_exec" && -n "$firmware_file" ]]; then
        echo -e "${CYAN}Complete Samsung Update Package Ready!${NC}"
        echo ""
        echo "Both DC Toolkit and firmware are available:"
        echo "• Toolkit: $(basename "$toolkit_exec")"
        echo "• Firmware: $(basename "$firmware_file")"
        echo ""
        # Detect firmware file type and adjust options accordingly
        local is_iso=false
        if [[ "$firmware_file" =~ \.iso$ ]]; then
            is_iso=true
        fi
        
        echo "Update options:"
        echo "1. Launch DC Toolkit GUI (recommended for .iso files)"
        if [[ "$is_iso" == true ]]; then
            echo "2. Use nvme-cli with automatic ISO decryption"
        else
            echo "2. Use nvme-cli with downloaded firmware"
        fi
        echo "3. Manual instructions"
        echo ""
        
        if [[ "$is_iso" == true ]]; then
            echo -e "${BLUE}Note: Samsung firmware is in ISO format${NC}"
            echo "• DC Toolkit can handle ISOs natively"
            echo "• nvme-cli requires ISO decryption first (automatic)"
        fi
        echo ""
        echo -n "Select option (1-3): "
        read -r choice
        
        case "$choice" in
            1)
                launch_dc_toolkit_with_firmware "$device" "$model" "$toolkit_exec" "$firmware_file"
                ;;
            2)
                use_nvme_cli_with_downloaded_firmware "$device" "$model" "$firmware_file"
                ;;
            3)
                provide_manual_update_instructions "$device" "$model" "$toolkit_exec" "$firmware_file" "$temp_dir"
                ;;
            *)
                echo "Invalid option, providing manual instructions"
                provide_manual_update_instructions "$device" "$model" "$toolkit_exec" "$firmware_file" "$temp_dir"
                ;;
        esac
        
    elif [[ -n "$toolkit_exec" ]]; then
        echo -e "${YELLOW}DC Toolkit found but firmware not downloaded automatically${NC}"
        echo "You can still use the DC Toolkit to search for and download firmware"
        launch_dc_toolkit_standalone "$device" "$model" "$toolkit_exec"
        
    elif [[ -n "$firmware_file" ]]; then
        echo -e "${YELLOW}Firmware found but DC Toolkit not downloaded automatically${NC}"
        echo "You can use nvme-cli with the downloaded firmware"
        use_nvme_cli_with_downloaded_firmware "$device" "$model" "$firmware_file"
        
    else
        echo -e "${RED}Neither DC Toolkit nor firmware could be downloaded automatically${NC}"
        manual_complete_download "$device" "$model"
    fi
}

# Function to launch DC Toolkit with firmware
launch_dc_toolkit_with_firmware() {
    local device="$1"
    local model="$2"
    local toolkit_exec="$3"
    local firmware_file="$4"
    
    echo -e "${CYAN}Launching Samsung DC Toolkit with Firmware${NC}"
    echo ""
    echo "Pre-update checklist:"
    echo "✓ DC Toolkit executable: $(basename "$toolkit_exec")"
    echo "✓ Firmware file: $(basename "$firmware_file")"
    echo "• Target device: $device ($model)"
    echo ""
    
    echo -e "${YELLOW}CRITICAL PRE-UPDATE STEPS:${NC}"
    echo "1. Stop all VMs and containers using $device"
    echo "2. Backup important data"
    echo "3. Ensure UPS power if available"
    echo ""
    
    if confirm_action "Proceed with DC Toolkit launch?"; then
        log_message "INFO" "Launching Samsung DC Toolkit with firmware for $device"
        
        echo "Starting DC Toolkit..."
        echo "Toolkit path: $toolkit_exec"
        echo "Note: Point DC Toolkit to firmware file: $(basename "$firmware_file")"
        echo ""
        
        # Validate toolkit executable before trying to run it
        if [[ ! -f "$toolkit_exec" ]]; then
            echo -e "${RED}✗ Error: DC Toolkit path is not a file: $toolkit_exec${NC}"
            if [[ -d "$toolkit_exec" ]]; then
                echo "Path is a directory - searching for executables within it..."
                local dir_exec=$(find "$toolkit_exec" -type f -executable 2>/dev/null | head -1)
                if [[ -n "$dir_exec" ]]; then
                    toolkit_exec="$dir_exec"
                    echo -e "${GREEN}✓ Found executable in directory: $(basename "$toolkit_exec")${NC}"
                else
                    echo -e "${RED}✗ No executable found in directory${NC}"
                    echo "Directory contents:"
                    ls -la "$toolkit_exec"/ 2>/dev/null || echo "Cannot list directory contents"
                    return 1
                fi
            else
                echo -e "${RED}✗ Invalid toolkit path${NC}"
                return 1
            fi
        fi
        
        # Make sure it's executable
        chmod +x "$toolkit_exec" 2>/dev/null
        
        # Try to run DC Toolkit
        echo "Executing: $toolkit_exec"
        
        # Check if it's a 32-bit binary that needs 32-bit libraries
        local arch_info=$(file "$toolkit_exec" 2>/dev/null)
        if echo "$arch_info" | grep -qi "32-bit"; then
            echo -e "${YELLOW}⚠ 32-bit executable detected${NC}"
            echo "This may require 32-bit libraries on 64-bit systems"
            echo "Install with: apt install libc6:i386 lib32stdc++6"
        fi
        
        if "$toolkit_exec" 2>&1; then
            echo -e "${GREEN}✓ DC Toolkit session completed${NC}"
            post_update_verification "$device" "$model"
        else
            local exit_code=$?
            echo -e "${RED}✗ DC Toolkit execution failed (exit code: $exit_code)${NC}"
            
            # Check if we have decrypted .bin files as fallback
            local temp_dir=$(dirname "$toolkit_exec")
            local bin_files=$(find "$temp_dir" -name "*.bin" 2>/dev/null | head -5)
            
            if [[ -n "$bin_files" ]]; then
                echo ""
                echo -e "${CYAN}Good news: Found decrypted Samsung firmware .bin files!${NC}"
                echo "Available firmware files:"
                while IFS= read -r bin_file; do
                    [[ -n "$bin_file" ]] && echo "  • $(basename "$bin_file")"
                done <<< "$bin_files"
                echo ""
                
                # Suggest using nvme-cli instead
                echo -e "${YELLOW}DC Toolkit GUI failed, but we can use nvme-cli with the decrypted firmware${NC}"
                if confirm_action "Would you like to use nvme-cli with the decrypted .bin files instead?"; then
                    
                    # Let user choose which firmware file to use
                    local firmware_choice=""
                    local bin_array=()
                    while IFS= read -r bin_file; do
                        [[ -n "$bin_file" ]] && bin_array+=("$bin_file")
                    done <<< "$bin_files"
                    
                    if [[ ${#bin_array[@]} -eq 1 ]]; then
                        # Only one file, use it
                        firmware_choice="${bin_array[0]}"
                        echo "Using firmware file: $(basename "$firmware_choice")"
                    else
                        # Multiple files, let user choose
                        echo ""
                        echo "Multiple firmware files available:"
                        local iso_name=$(find "$temp_dir" -name "*.iso" 2>/dev/null | head -1)
                        local iso_version=""
                        if [[ -n "$iso_name" ]]; then
                            iso_version=$(basename "$iso_name" | grep -o '[A-Z0-9]\{8\}' | head -1)
                        fi
                        
                        for i in "${!bin_array[@]}"; do
                            local bin_name=$(basename "${bin_array[i]}")
                            local recommendation=""
                            
                            # Check if this firmware matches the ISO version
                            if [[ -n "$iso_version" && "$bin_name" =~ $iso_version ]]; then
                                recommendation=" ${GREEN}← Recommended (matches ISO: $iso_version)${NC}"
                            elif [[ "$bin_name" =~ ^[A-Z0-9]{8}\.bin$ ]]; then
                                recommendation=" ${BLUE}← Main firmware${NC}"
                            fi
                            
                            echo "$((i+1)). $bin_name$recommendation"
                        done
                        
                        echo ""
                        echo -n "Select firmware file (1-${#bin_array[@]}): "
                        read -r choice
                        
                        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le ${#bin_array[@]} ]]; then
                            firmware_choice="${bin_array[$((choice-1))]}"
                            echo "Selected firmware file: $(basename "$firmware_choice")"
                        else
                            echo "Invalid choice. Using first file: $(basename "${bin_array[0]}")"
                            firmware_choice="${bin_array[0]}"
                        fi
                    fi
                    
                    use_nvme_cli_with_downloaded_firmware "$device" "$model" "$firmware_choice"
                    return
                fi
            fi
            
            echo ""
            echo "DC Toolkit execution failed. This could be due to:"
            echo "• Missing 32-bit libraries (if 32-bit executable)"
            echo "• Missing dependencies or wrong architecture"
            echo "• GUI environment requirements not met"
            echo ""
            echo "Manual troubleshooting:"
            echo "1. Check file type: file $toolkit_exec"
            echo "2. Check dependencies: ldd $toolkit_exec"
            echo "3. Install 32-bit support: apt install libc6:i386 lib32stdc++6"
            echo ""
            post_update_verification "$device" "$model"
        fi
    fi
}

# Function to use nvme-cli with downloaded firmware
use_nvme_cli_with_downloaded_firmware() {
    local device="$1"
    local model="$2"
    local firmware_file="$3"
    
    echo -e "${CYAN}Using nvme-cli with Downloaded Firmware${NC}"
    echo ""
    echo "Firmware file: $(basename "$firmware_file")"
    echo "Target device: $device ($model)"
    echo ""
    
    # Check if firmware file is an encrypted ISO that needs special handling
    if [[ "$firmware_file" =~ \.iso$ ]]; then
        echo -e "${YELLOW}Samsung firmware ISO detected${NC}"
        echo "Note: nvme-cli cannot directly use ISO files for firmware updates"
        echo ""
        echo "Options:"
        echo "1. Install ISO decryption tools and retry (7z, openssl, xxd, binutils)"
        echo "2. Use Samsung DC Toolkit GUI to handle the ISO"
        echo "3. Manually decrypt the ISO and extract .bin files"
        echo ""
        
        if confirm_action "Do you want to install ISO decryption tools and retry automatically?"; then
            echo "Installing ISO decryption tools..."
            
            # Install tools based on package manager
            if command -v apt &> /dev/null; then
                apt update -qq
                apt install -y p7zip-full openssl xxd binutils
            elif command -v yum &> /dev/null; then
                yum install -y p7zip openssl xxd binutils
            elif command -v dnf &> /dev/null; then
                dnf install -y p7zip openssl xxd binutils
            fi
            
            echo -e "${GREEN}✓ Tools installed. Attempting ISO decryption...${NC}"
            
            # Try to decrypt the ISO
            local temp_iso_dir=$(dirname "$firmware_file")
            decrypt_samsung_iso "$firmware_file" "$temp_iso_dir" "990PRO"
            
            # Look for decrypted .bin files
            local bin_file=$(find "$temp_iso_dir" -name "*.bin" 2>/dev/null | head -1)
            if [[ -n "$bin_file" ]]; then
                echo -e "${GREEN}✓ ISO decrypted successfully${NC}"
                firmware_file="$bin_file"
                echo "Using decrypted firmware: $(basename "$firmware_file")"
            else
                echo -e "${RED}✗ ISO decryption failed${NC}"
                echo "Please use Samsung DC Toolkit GUI or manually decrypt the ISO"
                return 1
            fi
        else
            echo "ISO firmware cannot be used directly with nvme-cli"
            echo "Please use Samsung DC Toolkit GUI or decrypt the ISO manually"
            return 1
        fi
    fi
    
    # This is similar to the existing nvme-cli update but with pre-downloaded firmware
    echo -e "${RED}CRITICAL WARNING:${NC}"
    echo "• Firmware update will begin - DO NOT interrupt or power off!"
    echo "• Ensure UPS power backup if available"
    echo "• Stop all VMs using this drive"
    echo "• This process may take several minutes"
    echo ""
    
    if confirm_action "Proceed with nvme-cli firmware update using downloaded firmware?"; then
        log_message "INFO" "Starting nvme-cli firmware update for $device with downloaded $firmware_file"
        
        echo "Step 1: Downloading firmware to drive..."
        if nvme fw-download "$device" --fw="$firmware_file"; then
            echo -e "${GREEN}✓ Firmware download successful${NC}"
            
            echo ""
            echo "Step 2: Committing firmware (this will reboot the drive)..."
            if nvme fw-commit "$device" --slot=1 --action=1; then
                echo -e "${GREEN}✓ Firmware commit successful${NC}"
                post_update_verification "$device" "$model"
            else
                echo -e "${RED}✗ Firmware commit failed${NC}"
                log_message "ERROR" "nvme-cli firmware commit failed for $device"
            fi
        else
            echo -e "${RED}✗ Firmware download failed${NC}"
            log_message "ERROR" "nvme-cli firmware download failed for $device"
        fi
    fi
}

# Function to launch DC Toolkit standalone (when firmware not found)
launch_dc_toolkit_standalone() {
    local device="$1"
    local model="$2"
    local toolkit_exec="$3"
    
    echo -e "${CYAN}Launching Samsung DC Toolkit (Standalone)${NC}"
    echo ""
    echo "DC Toolkit executable: $(basename "$toolkit_exec")"
    echo "Target device: $device ($model)"
    echo ""
    echo "Note: Use DC Toolkit to search for and download the correct firmware"
    echo "for your $model before updating."
    echo ""
    
    if confirm_action "Launch DC Toolkit now?"; then
        log_message "INFO" "Launching Samsung DC Toolkit standalone for $device"
        
        echo "Starting DC Toolkit..."
        echo ""
        
        # Try to run DC Toolkit
        if "$toolkit_exec" 2>&1; then
            echo -e "${GREEN}✓ DC Toolkit session completed${NC}"
            post_update_verification "$device" "$model"
        else
            echo -e "${RED}✗ DC Toolkit exited with error or completed${NC}"
            echo "This may be normal - check if firmware was updated"
            post_update_verification "$device" "$model"
        fi
    fi
}

# Function for post-update verification guidance
post_update_verification() {
    local device="$1"
    local model="$2"
    
    echo ""
    echo -e "${BLUE}=== Post-Update Verification ===${NC}"
    echo ""
    echo -e "${YELLOW}Next steps after firmware update:${NC}"
    echo "1. Reboot the system completely"
    echo "2. Re-run this firmware scanner to verify new version:"
    echo "   sudo firmware-scanner scan"
    echo "3. Check system logs for any issues:"
    echo "   journalctl -b | grep nvme"
    echo "4. Verify drive is detected and working:"
    echo "   lsblk | grep $(basename "$device")"
    echo "5. Test storage performance if critical"
    echo ""
    log_message "INFO" "Samsung firmware update process completed for $device ($model)"
}

# Function to provide manual update instructions for complete package  
provide_manual_update_instructions() {
    local device="$1"
    local model="$2"
    local toolkit_exec="$3"
    local firmware_file="$4"
    local temp_dir="$5"
    
    echo -e "${BLUE}Manual Samsung Update Instructions${NC}"
    echo ""
    echo "Downloaded files are located in: $temp_dir"
    echo ""
    
    if [[ -n "$toolkit_exec" ]]; then
        echo "DC Toolkit executable: $toolkit_exec"
        echo "To run manually: sudo $toolkit_exec"
        echo ""
    fi
    
    if [[ -n "$firmware_file" ]]; then
        echo "Firmware file: $firmware_file"
        echo "To update manually with nvme-cli:"
        echo "  sudo nvme fw-download $device --fw=$firmware_file"
        echo "  sudo nvme fw-commit $device --slot=1 --action=1"
        echo ""
    fi
    
    echo "Manual update steps:"
    echo "1. Stop all VMs using $device"
    echo "2. Backup important data"
    echo "3. Use either DC Toolkit GUI or nvme-cli commands above"
    echo "4. Reboot after update"
    echo "5. Verify with: sudo firmware-scanner scan"
}

# Function for manual complete download fallback
manual_complete_download() {
    local device="$1"
    local model="$2"
    
    echo -e "${BLUE}Manual Complete Download Instructions${NC}"
    echo ""
    echo "Automated search didn't find both DC Toolkit and firmware."
    echo "Manual download steps:"
    echo ""
    echo "1. Visit: https://semiconductor.samsung.com/consumer-storage/support/tools/"
    echo "2. Search for 'DC Toolkit' or 'Samsung Magician'"
    echo "3. Search for firmware for your model: $model"
    echo "4. Download both the toolkit and firmware"
    echo ""
    echo "Common search terms:"
    echo "• 'DC Toolkit Linux'"
    echo "• '$model firmware'"
    echo "• 'Samsung firmware update'"
    echo ""
    echo "After downloading, you can use either:"
    echo "• DC Toolkit GUI for guided update"
    echo "• nvme-cli commands with firmware .bin file"
}

# Function to search and download Samsung DC Toolkit (legacy function for compatibility)
search_and_download_dc_toolkit() {
    local device="$1"
    local model="$2"
    
    echo -e "${CYAN}Searching for Samsung DC Toolkit...${NC}"
    echo ""
    
    local base_url="https://semiconductor.samsung.com/consumer-storage/support/tools/"
    local temp_dir="/tmp/samsung_firmware_$$"
    local download_success=false
    
    mkdir -p "$temp_dir"
    cd "$temp_dir" || exit 1
    
    echo "Step 1: Searching Samsung tools website..."
    log_message "INFO" "Searching for Samsung DC Toolkit from $base_url"
    
    # Try to get the tools page and search for DC Toolkit links
    local tools_page="$temp_dir/tools_page.html"
    if curl -L -s -o "$tools_page" "$base_url" 2>/dev/null; then
        echo -e "${GREEN}✓ Downloaded tools page${NC}"
        
        # Search for DC Toolkit download links
        echo "Step 2: Parsing for DC Toolkit download links..."
        
        # Common Samsung DC Toolkit patterns
        local dc_toolkit_patterns=(
            "DC.*[Tt]oolkit.*Linux"
            "DC.*[Tt]oolkit.*linux"  
            "dcToolkit.*linux"
            "Samsung.*DC.*Toolkit"
            "magician.*linux"
            "nvme.*tool.*linux"
        )
        
        local found_links=()
        for pattern in "${dc_toolkit_patterns[@]}"; do
            local links=$(grep -io 'href="[^"]*"[^>]*'"$pattern" "$tools_page" 2>/dev/null | sed 's/href="//;s/".*//' | head -3)
            if [[ -n "$links" ]]; then
                while IFS= read -r link; do
                    [[ -n "$link" ]] && found_links+=("$link")
                done <<< "$links"
            fi
        done
        
        if [[ ${#found_links[@]} -gt 0 ]]; then
            echo -e "${GREEN}Found potential DC Toolkit downloads:${NC}"
            for i in "${!found_links[@]}"; do
                local link="${found_links[i]}"
                # Make sure link is absolute
                if [[ "$link" =~ ^/ ]]; then
                    link="https://semiconductor.samsung.com$link"
                elif [[ ! "$link" =~ ^https?:// ]]; then
                    link="$base_url$link"
                fi
                echo "$((i+1)). $link"
            done
            echo ""
            
            # Try to download the first promising link
            local download_link="${found_links[0]}"
            if [[ "$download_link" =~ ^/ ]]; then
                download_link="https://semiconductor.samsung.com$download_link"
            fi
            
            attempt_dc_toolkit_download "$download_link" "$device" "$model"
        else
            echo -e "${YELLOW}No direct DC Toolkit downloads found on tools page${NC}"
            manual_dc_toolkit_search "$device" "$model"
        fi
    else
        echo -e "${YELLOW}Could not access tools page directly${NC}"
        manual_dc_toolkit_search "$device" "$model"
    fi
    
    # Cleanup
    cd - >/dev/null 2>&1
    rm -rf "$temp_dir"
}

# Function to attempt DC Toolkit download
attempt_dc_toolkit_download() {
    local download_url="$1"
    local device="$2"
    local model="$3"
    
    echo "Step 3: Attempting to download DC Toolkit..."
    echo "URL: $download_url"
    
    local filename=$(basename "$download_url")
    [[ -z "$filename" || "$filename" == "/" ]] && filename="samsung_dc_toolkit.tar.gz"
    
    if curl -L -o "$filename" "$download_url" 2>/dev/null; then
        local file_size=$(stat -c%s "$filename" 2>/dev/null || echo "0")
        
        if [[ $file_size -gt 1024 ]]; then  # At least 1KB
            echo -e "${GREEN}✓ Downloaded: $filename ($file_size bytes)${NC}"
            log_message "INFO" "Successfully downloaded Samsung DC Toolkit: $filename"
            
            # Try to extract and run
            extract_and_run_dc_toolkit "$filename" "$device" "$model"
        else
            echo -e "${RED}✗ Downloaded file is too small or empty${NC}"
            manual_dc_toolkit_search "$device" "$model"
        fi
    else
        echo -e "${RED}✗ Download failed${NC}"
        manual_dc_toolkit_search "$device" "$model"
    fi
}

# Function to extract and run DC Toolkit
extract_and_run_dc_toolkit() {
    local filename="$1"
    local device="$2"
    local model="$3"
    
    echo "Step 4: Extracting DC Toolkit..."
    
    local extract_dir="samsung_dc_toolkit_extracted"
    mkdir -p "$extract_dir"
    
    # Try different extraction methods
    if [[ "$filename" =~ \.tar\.gz$ ]] || [[ "$filename" =~ \.tgz$ ]]; then
        if tar -xzf "$filename" -C "$extract_dir" 2>/dev/null; then
            echo -e "${GREEN}✓ Extracted TAR.GZ archive${NC}"
            find_and_run_dc_toolkit "$extract_dir" "$device" "$model"
        else
            echo -e "${RED}✗ Failed to extract TAR.GZ${NC}"
            manual_dc_toolkit_instructions "$filename" "$device" "$model"
        fi
    elif [[ "$filename" =~ \.zip$ ]]; then
        if command -v unzip &> /dev/null && unzip -q "$filename" -d "$extract_dir" 2>/dev/null; then
            echo -e "${GREEN}✓ Extracted ZIP archive${NC}"
            find_and_run_dc_toolkit "$extract_dir" "$device" "$model"
        else
            echo -e "${RED}✗ Failed to extract ZIP (unzip may not be installed)${NC}"
            manual_dc_toolkit_instructions "$filename" "$device" "$model"
        fi
    elif file "$filename" | grep -q "executable"; then
        echo -e "${GREEN}✓ Downloaded executable file${NC}"
        chmod +x "$filename"
        run_dc_toolkit_executable "$filename" "$device" "$model"
    else
        echo -e "${YELLOW}Unknown file format, providing manual instructions${NC}"
        manual_dc_toolkit_instructions "$filename" "$device" "$model"
    fi
}

# Function to find and run DC Toolkit in extracted directory
find_and_run_dc_toolkit() {
    local extract_dir="$1"
    local device="$2"
    local model="$3"
    
    echo "Step 5: Looking for DC Toolkit executable..."
    
    # Look for common DC Toolkit executable names
    local executables=$(find "$extract_dir" -type f \( -name "*dc*toolkit*" -o -name "*magician*" -o -name "*samsung*" \) -executable 2>/dev/null)
    
    if [[ -n "$executables" ]]; then
        echo "Found potential DC Toolkit executables:"
        echo "$executables"
        echo ""
        
        local first_exec=$(echo "$executables" | head -1)
        echo "Using: $first_exec"
        
        run_dc_toolkit_executable "$first_exec" "$device" "$model"
    else
        echo -e "${YELLOW}No obvious DC Toolkit executable found${NC}"
        echo "Contents of extracted directory:"
        ls -la "$extract_dir"
        echo ""
        manual_dc_toolkit_instructions "$extract_dir" "$device" "$model"
    fi
}

# Function to run DC Toolkit executable
run_dc_toolkit_executable() {
    local executable="$1"
    local device="$2"
    local model="$3"
    
    echo -e "${CYAN}Running Samsung DC Toolkit...${NC}"
    echo ""
    echo "Executable: $executable"
    echo "Target device: $device"
    echo "Model: $model"
    echo ""
    
    echo -e "${YELLOW}IMPORTANT: Follow these guidelines when using DC Toolkit:${NC}"
    echo "1. Stop all VMs using the target drive"
    echo "2. Backup important data"
    echo "3. Follow DC Toolkit's firmware update wizard"
    echo "4. Do not interrupt the update process"
    echo ""
    
    if confirm_action "Launch Samsung DC Toolkit now?"; then
        log_message "INFO" "Launching Samsung DC Toolkit: $executable"
        
        echo "Launching DC Toolkit..."
        echo "Note: DC Toolkit may require a GUI environment or specific dependencies"
        echo ""
        
        # Try to run the executable
        if "$executable" 2>&1; then
            echo -e "${GREEN}✓ DC Toolkit completed${NC}"
            echo ""
            echo "After firmware update:"
            echo "1. Reboot the system"
            echo "2. Run firmware scanner to verify new version"
            echo "3. Check system logs for any issues"
            log_message "INFO" "Samsung DC Toolkit completed successfully"
        else
            echo -e "${RED}✗ DC Toolkit encountered an error or exited${NC}"
            echo ""
            echo "This might be normal if DC Toolkit requires:"
            echo "• GUI environment (X11/Wayland)"
            echo "• Specific libraries or dependencies"
            echo "• Different execution method"
            log_message "WARN" "Samsung DC Toolkit execution completed with non-zero exit"
        fi
    else
        echo "DC Toolkit launch cancelled."
        manual_dc_toolkit_instructions "$executable" "$device" "$model"
    fi
}

# Function to provide manual DC Toolkit instructions
manual_dc_toolkit_instructions() {
    local file_or_dir="$1"
    local device="$2"
    local model="$3"
    
    echo -e "${BLUE}Manual DC Toolkit Usage Instructions${NC}"
    echo ""
    echo "Downloaded/extracted: $file_or_dir"
    echo ""
    echo "Manual steps to use Samsung DC Toolkit:"
    echo ""
    echo "1. Navigate to the downloaded/extracted location"
    echo "2. Look for executable files (usually named with 'dc', 'toolkit', or 'samsung')"
    echo "3. Run the executable with: sudo ./executable_name"
    echo "4. Follow the firmware update wizard"
    echo ""
    echo "Common DC Toolkit executables:"
    echo "• dcToolkit"
    echo "• samsung_dc_toolkit"
    echo "• magician_linux"
    echo "• Samsung_Magician_installer"
    echo ""
    echo "If no executable found:"
    echo "• Check for .deb or .rpm packages"
    echo "• Look for installation scripts"
    echo "• Check README or documentation files"
    echo ""
    echo "Target device for update: $device ($model)"
}

# Function for manual DC Toolkit search fallback
manual_dc_toolkit_search() {
    local device="$1"
    local model="$2"
    
    echo -e "${BLUE}Manual DC Toolkit Search${NC}"
    echo ""
    echo "Automated search didn't find direct downloads. Manual steps:"
    echo ""
    echo "1. Visit: https://semiconductor.samsung.com/consumer-storage/support/tools/"
    echo "2. Look for 'DC Toolkit' or 'Samsung Magician' Linux version"
    echo "3. Search for your model: $model"
    echo "4. Download the Linux-compatible version"
    echo ""
    echo "Alternative search terms to use on Samsung's site:"
    echo "• 'DC Toolkit Linux'"
    echo "• 'Samsung Magician Linux'"
    echo "• 'NVMe firmware update tool'"
    echo "• '$model firmware update'"
    echo ""
    echo "Once downloaded, you can:"
    echo "• Extract and run the installer"
    echo "• Use the firmware update wizard to update $device"
    echo "• Or return to this tool and use the nvme-cli method instead"
    echo ""
    
    if confirm_action "Would you like guidance for alternative update methods?"; then
        echo ""
        echo "Alternative update methods available:"
        echo "1. Return to nvme-cli method (recommended)"
        echo "2. Create bootable update media"
        echo "3. Get direct firmware download links"
        echo ""
        echo -n "Select option (1-3): "
        read -r alt_choice
        
        case "$alt_choice" in
            1)
                samsung_nvme_cli_update "$device" "$model"
                ;;
            2)
                samsung_bootable_update "$device" "$model"
                ;;
            3)
                samsung_download_links "$model"
                ;;
            *)
                echo "Invalid option selected."
                ;;
        esac
    fi
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
    echo "  - Multiple update methods (nvme-cli, DC Toolkit, bootable)"
    echo "  - Automated DC Toolkit and firmware download from Samsung website"
    echo "  - Automatic Samsung ISO decryption and .bin file extraction"
    echo "  - Step-by-step guided updates with safety checks"
    echo "  - Support for 990 PRO, 980 PRO and other Samsung NVMe drives"
    echo ""
    echo "Note: This script requires root privileges to access drive information"
    echo "      Firmware updates are potentially risky - always backup data first!"
    exit 0
fi

# Run main function
main "$@"
