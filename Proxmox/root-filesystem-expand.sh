#!/bin/bash

# Proxmox Root Filesystem Expansion Script
# Expands the root filesystem after cloning to a larger drive
# Usage: ./root-filesystem-expand.sh

# Configuration
LOG_FILE="/var/log/root-filesystem-expand.log"

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

# Function to check if this is a Proxmox system
check_proxmox() {
    if ! command -v pveversion &> /dev/null; then
        echo -e "${RED}Error: This doesn't appear to be a Proxmox system${NC}"
        exit 1
    fi
}

# Function to display current root filesystem status
display_root_status() {
    echo -e "${BLUE}=== Current Root Filesystem Status ===${NC}"
    
    echo "Proxmox Version:"
    pveversion
    echo ""
    
    echo "Current disk usage:"
    df -h /
    echo ""
    
    echo "Root filesystem device:"
    findmnt -n -o SOURCE /
    echo ""
    
    echo "Physical disk information:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "nvme|sda|sdb"
    echo ""
    
    echo "LVM Physical Volumes:"
    pvs 2>/dev/null | grep -E "pve|root"
    echo ""
    
    echo "LVM Volume Groups:"
    vgs 2>/dev/null | grep -E "pve|root"
    echo ""
    
    echo "Root LVM Logical Volume:"
    lvs 2>/dev/null | grep -E "root|pve"
    echo ""
}

# Function to detect root filesystem setup
detect_root_setup() {
    echo -e "${BLUE}=== Detecting Root Filesystem Setup ===${NC}"
    
    # Find the root filesystem device
    local root_device=$(findmnt -n -o SOURCE /)
    echo "Root filesystem device: $root_device"
    
    # Check if it's LVM
    if [[ "$root_device" =~ ^/dev/mapper/ ]]; then
        echo "Root filesystem is on LVM"
        
        # Get VG and LV names
        local vg_name=$(lvs --noheadings -o vg_name "$root_device" 2>/dev/null | tr -d ' ')
        local lv_name=$(lvs --noheadings -o lv_name "$root_device" 2>/dev/null | tr -d ' ')
        
        echo "Volume Group: $vg_name"
        echo "Logical Volume: $lv_name"
        
        # Get underlying PV
        local pv_device=$(pvs --noheadings -o pv_name -S vg_name="$vg_name" 2>/dev/null | tr -d ' ')
        echo "Physical Volume: $pv_device"
        
        # Get the actual disk device
        local disk_device=""
        
        echo "DEBUG: Starting disk detection for: $pv_device"
        
        # Try to get parent device name using lsblk
        local parent_name=$(lsblk -no PKNAME "$pv_device" 2>/dev/null | head -1 | tr -d ' ')
        echo "DEBUG: lsblk returned parent_name: '$parent_name'"
        
        # Check if lsblk returned a valid parent (different from the partition)
        if [[ -n "$parent_name" && "$parent_name" != "$(basename "$pv_device")" ]]; then
            disk_device="/dev/$parent_name"
            echo "DEBUG: Set disk_device from lsblk: $disk_device"
        else
            echo "DEBUG: lsblk didn't return valid parent, will use fallback"
        fi
        
        # If lsblk didn't work or returned empty, use multiple fallback methods
        if [[ -z "$disk_device" || "$disk_device" == "/dev/" ]]; then
            echo "DEBUG: Using fallback methods"
            # Method 1: Handle NVMe devices (nvme0n1p3 -> nvme0n1)
            if [[ "$pv_device" =~ nvme.*p[0-9]+$ ]]; then
                disk_device=$(echo "$pv_device" | sed 's/p[0-9]*$//')
                echo "DEBUG: NVMe pattern matched, set disk_device: $disk_device"
            # Method 2: Handle traditional devices (sda1 -> sda)
            elif [[ "$pv_device" =~ [0-9]+$ ]]; then
                disk_device=$(echo "$pv_device" | sed 's/[0-9]*$//')
                echo "DEBUG: Traditional pattern matched, set disk_device: $disk_device"
            else
                disk_device="$pv_device"
                echo "DEBUG: No pattern matched, using original: $disk_device"
            fi
        fi
        
        echo "DEBUG: Final disk_device value: $disk_device"
        
        # Final validation that we have a valid disk device
        if [[ ! -b "$disk_device" ]]; then
            echo -e "${RED}Error: Cannot determine parent disk for $pv_device${NC}"
            echo "Attempted disk device: $disk_device"
            echo "Debug: parent_name from lsblk = '$parent_name'"
            return 1
        fi
        
        echo "Physical disk: $disk_device"
        
        # Store for later use
        ROOT_DEVICE="$root_device"
        VG_NAME="$vg_name"
        LV_NAME="$lv_name"
        PV_DEVICE="$pv_device"
        DISK_DEVICE="$disk_device"
        
        return 0
    else
        echo -e "${RED}Error: Root filesystem is not on LVM${NC}"
        echo "This script is designed for LVM-based root filesystems"
        return 1
    fi
}

# Function to check for expansion opportunities
check_expansion_opportunities() {
    echo -e "${BLUE}=== Checking Expansion Opportunities ===${NC}"
    
    # Check if partition can be expanded
    local partition_num=$(echo "$PV_DEVICE" | sed 's/.*[^0-9]\([0-9]*\)$/\1/')
    
    echo "Checking partition $partition_num on $DISK_DEVICE..."
    
    # Get disk size (ensure single result and trim whitespace)
    local disk_size=$(lsblk -bno SIZE "$DISK_DEVICE" 2>/dev/null | head -1 | tr -d ' ')
    if [[ -z "$disk_size" || ! "$disk_size" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Could not get disk size for $DISK_DEVICE${NC}"
        echo "DEBUG: disk_size value: '$disk_size'"
        return 1
    fi
    local disk_gb=$((disk_size / 1073741824))
    
    # Get partition size (ensure single result and trim whitespace)
    local partition_size=$(lsblk -bno SIZE "$PV_DEVICE" 2>/dev/null | head -1 | tr -d ' ')
    if [[ -z "$partition_size" || ! "$partition_size" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Could not get partition size for $PV_DEVICE${NC}"
        echo "DEBUG: partition_size value: '$partition_size'"
        return 1
    fi
    local partition_gb=$((partition_size / 1073741824))
    
    # Get PV size (ensure single result and proper parsing)
    local pv_size=$(pvs --noheadings -o pv_size "$PV_DEVICE" 2>/dev/null | head -1 | tr -d ' ')
    if [[ -z "$pv_size" ]]; then
        echo -e "${RED}Error: Could not get PV size for $PV_DEVICE${NC}"
        return 1
    fi
    # Extract numeric part and convert to GB
    local pv_gb=$(echo "$pv_size" | sed 's/[^0-9.]//g' | cut -d. -f1)
    if [[ -z "$pv_gb" || ! "$pv_gb" =~ ^[0-9]+$ ]]; then
        pv_gb=0
    fi
    
    # Get VG free space (ensure single result)
    local vg_free=$(vgs --noheadings -o vg_free "$VG_NAME" 2>/dev/null | head -1 | tr -d ' ')
    if [[ -z "$vg_free" ]]; then
        vg_free="0"
    fi
    
    # Get LV size (ensure single result)
    local lv_size=$(lvs --noheadings -o lv_size "$VG_NAME/$LV_NAME" 2>/dev/null | head -1 | tr -d ' ')
    if [[ -z "$lv_size" ]]; then
        echo -e "${RED}Error: Could not get LV size for $VG_NAME/$LV_NAME${NC}"
        return 1
    fi
    
    echo "Disk size: ${disk_gb}GB"
    echo "Partition size: ${partition_gb}GB"
    echo "PV size: ${pv_gb}GB"
    echo "VG free space: $vg_free"
    echo "Root LV size: $lv_size"
    echo ""
    
    # Check what can be expanded
    local can_expand_partition=false
    local can_expand_pv=false
    local can_expand_lv=false
    
    # Check partition expansion
    if [[ $((disk_gb - partition_gb)) -gt 5 ]]; then
        echo -e "${YELLOW}✓ Partition can be expanded by ~$((disk_gb - partition_gb))GB${NC}"
        can_expand_partition=true
    fi
    
    # Check PV expansion
    if [[ $((partition_gb - pv_gb)) -gt 1 ]]; then
        echo -e "${YELLOW}✓ Physical volume can be expanded by ~$((partition_gb - pv_gb))GB${NC}"
        can_expand_pv=true
    fi
    
    # Check LV expansion
    if [[ "$vg_free" != "0" ]]; then
        echo -e "${YELLOW}✓ Logical volume can be expanded by $vg_free${NC}"
        can_expand_lv=true
    fi
    
    if [[ "$can_expand_partition" == false && "$can_expand_pv" == false && "$can_expand_lv" == false ]]; then
        echo -e "${GREEN}No expansion opportunities found - system is already using full disk${NC}"
        return 1
    fi
    
    # Store expansion flags
    CAN_EXPAND_PARTITION="$can_expand_partition"
    CAN_EXPAND_PV="$can_expand_pv"
    CAN_EXPAND_LV="$can_expand_lv"
    
    return 0
}

# Function to expand partition
expand_partition() {
    echo -e "${BLUE}=== Expanding Partition ===${NC}"
    
    local partition_num=$(echo "$PV_DEVICE" | sed 's/.*[^0-9]\([0-9]*\)$/\1/')
    
    echo "Expanding partition $partition_num on $DISK_DEVICE..."
    log_message "INFO" "Expanding partition $partition_num on $DISK_DEVICE"
    
    # Use parted to expand the partition
    if parted "$DISK_DEVICE" resizepart "$partition_num" 100% 2>/dev/null; then
        echo -e "${GREEN}✓ Partition expanded successfully${NC}"
        log_message "INFO" "Partition $partition_num expanded successfully"
        
        # Inform kernel of partition changes
        partprobe "$DISK_DEVICE" 2>/dev/null || true
        sleep 2
        
        return 0
    else
        echo -e "${RED}✗ Failed to expand partition${NC}"
        log_message "ERROR" "Failed to expand partition $partition_num"
        return 1
    fi
}

# Function to expand physical volume
expand_pv() {
    echo -e "${BLUE}=== Expanding Physical Volume ===${NC}"
    
    echo "Expanding PV: $PV_DEVICE"
    log_message "INFO" "Expanding physical volume: $PV_DEVICE"
    
    if pvresize "$PV_DEVICE" 2>/dev/null; then
        echo -e "${GREEN}✓ Physical volume expanded successfully${NC}"
        log_message "INFO" "Physical volume $PV_DEVICE expanded successfully"
        return 0
    else
        echo -e "${RED}✗ Failed to expand physical volume${NC}"
        log_message "ERROR" "Failed to expand physical volume $PV_DEVICE"
        return 1
    fi
}

# Function to expand logical volume and filesystem
expand_lv_and_fs() {
    echo -e "${BLUE}=== Expanding Logical Volume and Filesystem ===${NC}"
    
    echo "Expanding LV: $VG_NAME/$LV_NAME"
    log_message "INFO" "Expanding logical volume: $VG_NAME/$LV_NAME"
    
    # Expand LV to use all free space
    if lvextend -l +100%FREE "$VG_NAME/$LV_NAME" 2>/dev/null; then
        echo -e "${GREEN}✓ Logical volume expanded successfully${NC}"
        log_message "INFO" "Logical volume $VG_NAME/$LV_NAME expanded successfully"
        
        # Expand filesystem
        echo "Expanding filesystem..."
        log_message "INFO" "Expanding filesystem on $ROOT_DEVICE"
        
        # Detect filesystem type
        local fs_type=$(blkid -o value -s TYPE "$ROOT_DEVICE" 2>/dev/null)
        
        case "$fs_type" in
            ext2|ext3|ext4)
                if resize2fs "$ROOT_DEVICE" 2>/dev/null; then
                    echo -e "${GREEN}✓ Filesystem expanded successfully${NC}"
                    log_message "INFO" "Filesystem expanded successfully (ext)"
                    return 0
                else
                    echo -e "${RED}✗ Failed to expand filesystem${NC}"
                    log_message "ERROR" "Failed to expand filesystem (ext)"
                    return 1
                fi
                ;;
            xfs)
                if xfs_growfs / 2>/dev/null; then
                    echo -e "${GREEN}✓ Filesystem expanded successfully${NC}"
                    log_message "INFO" "Filesystem expanded successfully (xfs)"
                    return 0
                else
                    echo -e "${RED}✗ Failed to expand filesystem${NC}"
                    log_message "ERROR" "Failed to expand filesystem (xfs)"
                    return 1
                fi
                ;;
            *)
                echo -e "${YELLOW}Unknown filesystem type: $fs_type${NC}"
                echo "Attempting generic resize..."
                if resize2fs "$ROOT_DEVICE" 2>/dev/null; then
                    echo -e "${GREEN}✓ Filesystem expanded successfully${NC}"
                    log_message "INFO" "Filesystem expanded successfully (generic)"
                    return 0
                else
                    echo -e "${RED}✗ Failed to expand filesystem${NC}"
                    log_message "ERROR" "Failed to expand filesystem (generic)"
                    return 1
                fi
                ;;
        esac
    else
        echo -e "${RED}✗ Failed to expand logical volume${NC}"
        log_message "ERROR" "Failed to expand logical volume $VG_NAME/$LV_NAME"
        return 1
    fi
}

# Function to run complete expansion
run_complete_expansion() {
    echo -e "${BLUE}=== Running Complete Root Filesystem Expansion ===${NC}"
    
    local steps_completed=0
    local total_steps=0
    
    # Count steps needed
    [[ "$CAN_EXPAND_PARTITION" == true ]] && ((total_steps++))
    [[ "$CAN_EXPAND_PV" == true ]] && ((total_steps++))
    [[ "$CAN_EXPAND_LV" == true ]] && ((total_steps++))
    
    if [[ $total_steps -eq 0 ]]; then
        echo -e "${GREEN}No expansion needed - system is already using full disk${NC}"
        return 0
    fi
    
    echo "Will perform $total_steps expansion steps..."
    echo ""
    
    # Confirm before proceeding
    if [[ "${AUTO_EXPAND:-false}" != "true" ]]; then
        echo -e "${YELLOW}⚠ This will modify your disk partitions and filesystems${NC}"
        echo -n "Are you sure you want to proceed? [y/N]: "
        read -r response </dev/tty
        
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Expansion cancelled by user"
            return 1
        fi
    fi
    
    # Step 1: Expand partition if needed
    if [[ "$CAN_EXPAND_PARTITION" == true ]]; then
        echo -e "${YELLOW}Step $((steps_completed + 1))/$total_steps: Expanding partition${NC}"
        if expand_partition; then
            ((steps_completed++))
            echo ""
        else
            echo -e "${RED}Partition expansion failed - stopping${NC}"
            return 1
        fi
    fi
    
    # Step 2: Expand PV if needed
    if [[ "$CAN_EXPAND_PV" == true ]]; then
        echo -e "${YELLOW}Step $((steps_completed + 1))/$total_steps: Expanding physical volume${NC}"
        if expand_pv; then
            ((steps_completed++))
            echo ""
        else
            echo -e "${RED}Physical volume expansion failed - stopping${NC}"
            return 1
        fi
    fi
    
    # Step 3: Expand LV and filesystem if needed
    if [[ "$CAN_EXPAND_LV" == true ]]; then
        echo -e "${YELLOW}Step $((steps_completed + 1))/$total_steps: Expanding logical volume and filesystem${NC}"
        if expand_lv_and_fs; then
            ((steps_completed++))
            echo ""
        else
            echo -e "${RED}Logical volume expansion failed - stopping${NC}"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✓ All expansion steps completed successfully! ($steps_completed/$total_steps)${NC}"
    return 0
}

# Function for interactive mode
interactive_mode() {
    echo -e "${CYAN}=== Interactive Root Filesystem Expansion ===${NC}"
    echo ""
    
    echo "What would you like to do?"
    echo "1. Display current root filesystem status"
    echo "2. Check expansion opportunities"
    echo "3. Expand partition only"
    echo "4. Expand physical volume only"
    echo "5. Expand logical volume and filesystem only"
    echo "6. Run complete expansion (all steps)"
    echo "7. Exit"
    echo ""
    
    echo -n "Enter your choice (1-7): "
    read -r choice
    
    case "$choice" in
        1) display_root_status ;;
        2) 
            if detect_root_setup; then
                check_expansion_opportunities
            fi
            ;;
        3)
            if detect_root_setup && check_expansion_opportunities; then
                if [[ "$CAN_EXPAND_PARTITION" == true ]]; then
                    expand_partition
                else
                    echo -e "${YELLOW}Partition expansion not needed${NC}"
                fi
            fi
            ;;
        4)
            if detect_root_setup && check_expansion_opportunities; then
                if [[ "$CAN_EXPAND_PV" == true ]]; then
                    expand_pv
                else
                    echo -e "${YELLOW}Physical volume expansion not needed${NC}"
                fi
            fi
            ;;
        5)
            if detect_root_setup && check_expansion_opportunities; then
                if [[ "$CAN_EXPAND_LV" == true ]]; then
                    expand_lv_and_fs
                else
                    echo -e "${YELLOW}Logical volume expansion not needed${NC}"
                fi
            fi
            ;;
        6)
            if detect_root_setup && check_expansion_opportunities; then
                run_complete_expansion
            fi
            ;;
        7) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
    esac
}

# Main function
main() {
    echo -e "${CYAN}=== Proxmox Root Filesystem Expansion ===${NC}"
    echo ""
    
    # Check if running as root
    check_root
    
    # Check if this is a Proxmox system
    check_proxmox
    
    # Create log file
    touch "$LOG_FILE"
    log_message "INFO" "Root filesystem expansion started"
    
    # Run interactive mode or specific action
    if [[ "$1" == "auto" ]]; then
        AUTO_EXPAND="true"
        display_root_status
        if detect_root_setup && check_expansion_opportunities; then
            run_complete_expansion
        fi
    elif [[ "$1" == "check" ]]; then
        display_root_status
        if detect_root_setup; then
            check_expansion_opportunities
        fi
    elif [[ "$1" == "expand" ]]; then
        if detect_root_setup && check_expansion_opportunities; then
            run_complete_expansion
        fi
    else
        interactive_mode
    fi
    
    log_message "INFO" "Root filesystem expansion completed"
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [mode]"
    echo ""
    echo "Proxmox Root Filesystem Expansion Script"
    echo "Expands root filesystem after cloning to a larger drive"
    echo ""
    echo "Modes:"
    echo "  (no args)   - Interactive mode with menu"
    echo "  auto        - Automatic expansion of all components"
    echo "  check       - Check expansion opportunities only"
    echo "  expand      - Run complete expansion with confirmation"
    echo ""
    echo "Examples:"
    echo "  $0          # Interactive mode"
    echo "  $0 check    # Check what can be expanded"
    echo "  $0 expand   # Expand with confirmation"
    echo "  $0 auto     # Automatic expansion"
    echo ""
    echo "This script is designed for Proxmox systems with LVM root filesystems"
    echo "Run after cloning to a larger drive to utilize the additional space"
    exit 0
fi

# Run main function
main "$@"
