#!/bin/bash

# Proxmox Storage Configuration Fix Script
# Diagnoses and fixes common storage configuration issues in Proxmox
# Specifically addresses issues where storage displays incorrectly in different views
# Usage: ./storage-config-fix.sh

# Configuration
LOG_FILE="/var/log/storage-config-fix.log"

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

# Function to display current storage overview
display_storage_overview() {
    echo -e "${BLUE}=== Current Storage Overview ===${NC}"
    
    echo "Proxmox Version:"
    pveversion
    echo ""
    
    echo "Physical Disks:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk|part|lvm"
    echo ""
    
    echo "LVM Physical Volumes:"
    pvs 2>/dev/null || echo "No PVs found"
    echo ""
    
    echo "LVM Volume Groups:"
    vgs 2>/dev/null || echo "No VGs found"
    echo ""
    
    echo "LVM Logical Volumes:"
    lvs 2>/dev/null || echo "No LVs found"
    echo ""
    
    echo "Proxmox Storage Status:"
    pvesm status 2>/dev/null || echo "pvesm not available"
    echo ""
    
    echo "Filesystem Usage:"
    df -h | grep -E '^/dev'
    echo ""
}

# Function to diagnose storage discrepancies
diagnose_storage_discrepancies() {
    echo -e "${BLUE}=== Diagnosing Storage Discrepancies ===${NC}"
    
    # Check for common issues
    local issues_found=0
    
    # Check if PV size matches disk size
    echo "Checking Physical Volume vs Disk Size discrepancies:"
    while read -r device pv_size; do
        if [[ -n "$device" && -n "$pv_size" ]]; then
            local disk_size=$(lsblk -bno SIZE "$device" 2>/dev/null | head -1)
            local pv_size_bytes=$(echo "$pv_size" | sed 's/[^0-9]//g')
            
            if [[ -n "$disk_size" && -n "$pv_size_bytes" ]]; then
                # Convert to GB for comparison (allowing for some overhead)
                local disk_gb=$((disk_size / 1073741824))
                local pv_gb=$((pv_size_bytes))
                local diff=$((disk_gb - pv_gb))
                
                echo "  Device: $device"
                echo "    Disk size: ${disk_gb}GB"
                echo "    PV size: ${pv_gb}GB"
                echo "    Difference: ${diff}GB"
                
                if [[ $diff -gt 50 ]]; then
                    echo -e "    ${YELLOW}⚠ Significant size difference detected!${NC}"
                    ((issues_found++))
                fi
            fi
        fi
    done < <(pvs --noheadings -o pv_name,pv_size 2>/dev/null)
    echo ""
    
    # Check for unallocated space in VGs
    echo "Checking Volume Group space allocation:"
    while read -r vg_name vg_size vg_free; do
        if [[ -n "$vg_name" && -n "$vg_size" && -n "$vg_free" ]]; then
            echo "  VG: $vg_name"
            echo "    Total: $vg_size"
            echo "    Free: $vg_free"
            
            # Check if there's significant free space
            local free_num=$(echo "$vg_free" | sed 's/[^0-9.]//g')
            local total_num=$(echo "$vg_size" | sed 's/[^0-9.]//g')
            
            if [[ $(echo "$free_num > 10" | bc -l 2>/dev/null) == "1" ]]; then
                echo -e "    ${YELLOW}⚠ Significant free space available for expansion${NC}"
                ((issues_found++))
            fi
        fi
    done < <(vgs --noheadings -o vg_name,vg_size,vg_free 2>/dev/null)
    echo ""
    
    # Check thin pool utilization
    echo "Checking Thin Pool utilization:"
    while read -r lv_name vg_name lv_size data_percent pool_lv; do
        if [[ -n "$lv_name" && "$pool_lv" == "pool" ]]; then
            echo "  Thin Pool: $vg_name/$lv_name"
            echo "    Size: $lv_size"
            echo "    Data Usage: $data_percent%"
            
            if [[ $(echo "$data_percent > 80" | bc -l 2>/dev/null) == "1" ]]; then
                echo -e "    ${YELLOW}⚠ High thin pool utilization${NC}"
                ((issues_found++))
            fi
        fi
    done < <(lvs --noheadings -o lv_name,vg_name,lv_size,data_percent,lv_layout 2>/dev/null | grep thin)
    echo ""
    
    # Check storage configuration in Proxmox
    echo "Checking Proxmox storage configuration discrepancies:"
    local storage_info=$(pvesm status 2>/dev/null)
    if [[ -n "$storage_info" ]]; then
        echo "$storage_info" | while read -r line; do
            if [[ "$line" =~ ^local ]]; then
                echo "  $line"
            fi
        done
    fi
    echo ""
    
    if [[ $issues_found -gt 0 ]]; then
        echo -e "${YELLOW}Found $issues_found potential storage configuration issues${NC}"
        return 1
    else
        echo -e "${GREEN}No significant storage discrepancies found${NC}"
        return 0
    fi
}

# Function to expand physical volumes
expand_physical_volumes() {
    echo -e "${BLUE}=== Physical Volume Expansion ===${NC}"
    
    echo "Checking for expandable physical volumes..."
    
    local pvs_to_expand=()
    while read -r device; do
        if [[ -n "$device" ]]; then
            # Check if PV can be expanded
            local pv_size=$(pvs --noheadings -o pv_size "$device" 2>/dev/null | tr -d ' ')
            local disk_size=$(lsblk -bno SIZE "$device" 2>/dev/null | head -1)
            
            if [[ -n "$pv_size" && -n "$disk_size" ]]; then
                local pv_bytes=$(echo "$pv_size" | sed 's/[^0-9]//g')
                local disk_gb=$((disk_size / 1073741824))
                local pv_gb=$((pv_bytes))
                
                if [[ $((disk_gb - pv_gb)) -gt 10 ]]; then
                    pvs_to_expand+=("$device")
                    echo "  $device can be expanded by approximately $((disk_gb - pv_gb))GB"
                fi
            fi
        fi
    done < <(pvs --noheadings -o pv_name 2>/dev/null)
    
    if [[ ${#pvs_to_expand[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Physical volumes that can be expanded:${NC}"
        printf '  %s\n' "${pvs_to_expand[@]}"
        echo ""
        
        echo -n "Would you like to expand these physical volumes? [y/N]: "
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            for pv in "${pvs_to_expand[@]}"; do
                echo "Expanding PV: $pv"
                log_message "INFO" "Expanding physical volume: $pv"
                
                if pvresize "$pv" 2>/dev/null; then
                    echo -e "${GREEN}✓ Successfully expanded $pv${NC}"
                    log_message "INFO" "Successfully expanded PV: $pv"
                else
                    echo -e "${RED}✗ Failed to expand $pv${NC}"
                    log_message "ERROR" "Failed to expand PV: $pv"
                fi
            done
        fi
    else
        echo "No physical volumes need expansion"
    fi
    echo ""
}

# Function to expand volume groups and logical volumes
expand_volume_groups() {
    echo -e "${BLUE}=== Volume Group and Logical Volume Expansion ===${NC}"
    
    echo "Checking for expandable volume groups..."
    
    while read -r vg_name vg_free; do
        if [[ -n "$vg_name" && -n "$vg_free" ]]; then
            local free_gb=$(echo "$vg_free" | sed 's/[^0-9.]//g')
            
            if [[ $(echo "$free_gb > 5" | bc -l 2>/dev/null) == "1" ]]; then
                echo "Volume Group: $vg_name has ${vg_free} free space"
                
                # Check for logical volumes that could be expanded
                echo "  Logical volumes in $vg_name:"
                lvs --noheadings -o lv_name,lv_size -S vg_name="$vg_name" 2>/dev/null | while read -r lv_name lv_size; do
                    if [[ -n "$lv_name" && -n "$lv_size" ]]; then
                        echo "    $lv_name: $lv_size"
                    fi
                done
                
                echo ""
                echo -n "Would you like to expand logical volumes in $vg_name? [y/N]: "
                read -r response
                
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Available logical volumes to expand:"
                    lvs --noheadings -o lv_name -S vg_name="$vg_name" 2>/dev/null | while read -r lv_name; do
                        if [[ -n "$lv_name" ]]; then
                            echo "  $lv_name"
                        fi
                    done
                    
                    echo -n "Enter logical volume name to expand (or 'all' for all): "
                    read -r lv_choice
                    
                    if [[ "$lv_choice" == "all" ]]; then
                        # Expand all LVs proportionally
                        echo "Expanding all logical volumes proportionally..."
                        log_message "INFO" "Expanding all LVs in VG: $vg_name"
                        
                        while read -r lv_name; do
                            if [[ -n "$lv_name" ]]; then
                                local lv_path="/dev/$vg_name/$lv_name"
                                if lvextend -l +100%FREE "$lv_path" 2>/dev/null; then
                                    echo -e "${GREEN}✓ Expanded $lv_name${NC}"
                                    log_message "INFO" "Successfully expanded LV: $lv_name"
                                    
                                    # Try to resize filesystem
                                    if resize2fs "$lv_path" 2>/dev/null; then
                                        echo -e "${GREEN}✓ Resized filesystem on $lv_name${NC}"
                                    elif xfs_growfs "$lv_path" 2>/dev/null; then
                                        echo -e "${GREEN}✓ Resized XFS filesystem on $lv_name${NC}"
                                    fi
                                else
                                    echo -e "${RED}✗ Failed to expand $lv_name${NC}"
                                fi
                            fi
                        done < <(lvs --noheadings -o lv_name -S vg_name="$vg_name" 2>/dev/null)
                    elif [[ -n "$lv_choice" ]]; then
                        # Expand specific LV
                        local lv_path="/dev/$vg_name/$lv_choice"
                        echo "Expanding logical volume: $lv_choice"
                        log_message "INFO" "Expanding LV: $lv_choice"
                        
                        if lvextend -l +100%FREE "$lv_path" 2>/dev/null; then
                            echo -e "${GREEN}✓ Expanded $lv_choice${NC}"
                            log_message "INFO" "Successfully expanded LV: $lv_choice"
                            
                            # Try to resize filesystem
                            if resize2fs "$lv_path" 2>/dev/null; then
                                echo -e "${GREEN}✓ Resized filesystem on $lv_choice${NC}"
                            elif xfs_growfs "$lv_path" 2>/dev/null; then
                                echo -e "${GREEN}✓ Resized XFS filesystem on $lv_choice${NC}"
                            fi
                        else
                            echo -e "${RED}✗ Failed to expand $lv_choice${NC}"
                        fi
                    fi
                fi
            fi
        fi
    done < <(vgs --noheadings -o vg_name,vg_free 2>/dev/null)
    echo ""
}

# Function to fix thin pool configuration
fix_thin_pool_config() {
    echo -e "${BLUE}=== Thin Pool Configuration Fix ===${NC}"
    
    echo "Checking thin pool configuration..."
    
    local thin_pools=()
    while read -r lv_name vg_name data_percent metadata_percent; do
        if [[ -n "$lv_name" && -n "$vg_name" ]]; then
            thin_pools+=("$vg_name/$lv_name")
            echo "Thin Pool: $vg_name/$lv_name"
            echo "  Data Usage: $data_percent%"
            echo "  Metadata Usage: $metadata_percent%"
            
            # Check if thin pool needs expansion
            if [[ $(echo "$data_percent > 80" | bc -l 2>/dev/null) == "1" ]]; then
                echo -e "  ${YELLOW}⚠ High data usage - consider expanding${NC}"
            fi
            
            if [[ $(echo "$metadata_percent > 80" | bc -l 2>/dev/null) == "1" ]]; then
                echo -e "  ${YELLOW}⚠ High metadata usage - consider expanding${NC}"
            fi
        fi
    done < <(lvs --noheadings -o lv_name,vg_name,data_percent,metadata_percent -S lv_layout=thin,pool 2>/dev/null)
    
    if [[ ${#thin_pools[@]} -gt 0 ]]; then
        echo ""
        echo -n "Would you like to optimize thin pool configuration? [y/N]: "
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            for pool in "${thin_pools[@]}"; do
                echo "Optimizing thin pool: $pool"
                log_message "INFO" "Optimizing thin pool: $pool"
                
                # Run fstrim on the pool
                if fstrim -v "/dev/$pool" 2>/dev/null; then
                    echo -e "${GREEN}✓ Trimmed $pool${NC}"
                    log_message "INFO" "Successfully trimmed thin pool: $pool"
                fi
            done
        fi
    else
        echo "No thin pools found"
    fi
    echo ""
}

# Function to refresh Proxmox storage configuration
refresh_proxmox_storage() {
    echo -e "${BLUE}=== Refreshing Proxmox Storage Configuration ===${NC}"
    
    echo "Refreshing Proxmox storage information..."
    
    # Restart relevant services
    echo "Restarting Proxmox storage services..."
    log_message "INFO" "Refreshing Proxmox storage configuration"
    
    if systemctl restart pvestatd 2>/dev/null; then
        echo -e "${GREEN}✓ Restarted pvestatd${NC}"
        log_message "INFO" "Successfully restarted pvestatd"
    else
        echo -e "${YELLOW}⚠ Failed to restart pvestatd${NC}"
        log_message "WARN" "Failed to restart pvestatd"
    fi
    
    if systemctl restart pvedaemon 2>/dev/null; then
        echo -e "${GREEN}✓ Restarted pvedaemon${NC}"
        log_message "INFO" "Successfully restarted pvedaemon"
    else
        echo -e "${YELLOW}⚠ Failed to restart pvedaemon${NC}"
        log_message "WARN" "Failed to restart pvedaemon"
    fi
    
    # Wait for services to stabilize
    echo "Waiting for services to stabilize..."
    sleep 5
    
    # Update storage status
    echo "Updating storage status..."
    if pvesm status >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Storage status updated${NC}"
        log_message "INFO" "Storage status updated successfully"
    else
        echo -e "${YELLOW}⚠ Storage status update may have issues${NC}"
        log_message "WARN" "Storage status update had issues"
    fi
    
    echo ""
}

# Function to provide recommendations
provide_recommendations() {
    echo -e "${BLUE}=== Recommendations ===${NC}"
    
    echo "Based on the analysis, here are recommendations to resolve storage display issues:"
    echo ""
    
    echo "1. Physical Volume Issues:"
    echo "   - If disk size > PV size: Use 'pvresize /dev/sdX' to expand"
    echo "   - Ensure partitions are properly sized"
    echo ""
    
    echo "2. Volume Group Issues:"
    echo "   - Use free space in VGs to expand logical volumes"
    echo "   - Consider creating new LVs if needed"
    echo ""
    
    echo "3. Proxmox Display Issues:"
    echo "   - Restart Proxmox services to refresh storage info"
    echo "   - Check /etc/pve/storage.cfg for correct configuration"
    echo ""
    
    echo "4. Filesystem Issues:"
    echo "   - Resize filesystems after expanding LVs"
    echo "   - Use 'resize2fs' for ext4 or 'xfs_growfs' for XFS"
    echo ""
    
    echo "5. Thin Pool Issues:"
    echo "   - Monitor data and metadata usage"
    echo "   - Expand thin pools when usage is high"
    echo "   - Run regular fstrim operations"
    echo ""
    
    echo "To verify fixes, check:"
    echo "   - Proxmox web interface summary page"
    echo "   - 'df -h' command output"
    echo "   - 'pvs', 'vgs', 'lvs' command outputs"
    echo "   - 'pvesm status' command output"
    echo ""
}

# Function to create final report
create_final_report() {
    local report_file="/tmp/storage-config-fix-report.txt"
    
    echo -e "${BLUE}=== Generating Final Report ===${NC}"
    
    {
        echo "Proxmox Storage Configuration Fix Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo ""
        
        echo "PROXMOX VERSION:"
        pveversion
        echo ""
        
        echo "FINAL STORAGE STATUS:"
        echo "Physical Volumes:"
        pvs 2>/dev/null || echo "No PVs found"
        echo ""
        
        echo "Volume Groups:"
        vgs 2>/dev/null || echo "No VGs found"
        echo ""
        
        echo "Logical Volumes:"
        lvs 2>/dev/null || echo "No LVs found"
        echo ""
        
        echo "Filesystem Usage:"
        df -h | grep -E '^/dev'
        echo ""
        
        echo "Proxmox Storage Status:"
        pvesm status 2>/dev/null || echo "pvesm not available"
        echo ""
        
        echo "ACTIONS PERFORMED:"
        if [[ -f "$LOG_FILE" ]]; then
            grep "INFO" "$LOG_FILE" | tail -10
        fi
        echo ""
        
    } > "$report_file"
    
    echo "Final report saved to: $report_file"
    echo ""
}

# Interactive mode function
interactive_mode() {
    echo -e "${CYAN}=== Interactive Storage Configuration Fix ===${NC}"
    echo ""
    
    echo "What would you like to do?"
    echo "1. Display current storage overview"
    echo "2. Diagnose storage discrepancies"
    echo "3. Expand physical volumes"
    echo "4. Expand volume groups/logical volumes"
    echo "5. Fix thin pool configuration"
    echo "6. Refresh Proxmox storage configuration"
    echo "7. Run complete diagnostic and fix"
    echo "8. Exit"
    echo ""
    
    echo -n "Enter your choice (1-8): "
    read -r choice
    
    case "$choice" in
        1) display_storage_overview ;;
        2) diagnose_storage_discrepancies ;;
        3) expand_physical_volumes ;;
        4) expand_volume_groups ;;
        5) fix_thin_pool_config ;;
        6) refresh_proxmox_storage ;;
        7) 
            display_storage_overview
            diagnose_storage_discrepancies
            expand_physical_volumes
            expand_volume_groups
            fix_thin_pool_config
            refresh_proxmox_storage
            provide_recommendations
            create_final_report
            ;;
        8) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
    esac
}

# Main function
main() {
    echo -e "${CYAN}=== Proxmox Storage Configuration Fix ===${NC}"
    echo ""
    
    # Check if running as root
    check_root
    
    # Check if this is a Proxmox system
    check_proxmox
    
    # Create log file
    touch "$LOG_FILE"
    log_message "INFO" "Storage configuration fix started"
    
    # Run interactive mode or specific action
    if [[ "$1" == "interactive" || "$1" == "" ]]; then
        interactive_mode
    elif [[ "$1" == "diagnose" ]]; then
        display_storage_overview
        diagnose_storage_discrepancies
    elif [[ "$1" == "fix" ]]; then
        display_storage_overview
        diagnose_storage_discrepancies
        expand_physical_volumes
        expand_volume_groups
        fix_thin_pool_config
        refresh_proxmox_storage
        provide_recommendations
        create_final_report
    else
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use 'interactive', 'diagnose', 'fix' or run without arguments for interactive mode"
        exit 1
    fi
    
    echo -e "${GREEN}Storage configuration fix completed!${NC}"
    echo "Check log file: $LOG_FILE"
    
    log_message "INFO" "Storage configuration fix completed"
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [mode]"
    echo ""
    echo "Proxmox Storage Configuration Fix Script"
    echo "Diagnoses and fixes storage configuration issues in Proxmox"
    echo ""
    echo "Modes:"
    echo "  (no args)     - Interactive mode with menu"
    echo "  interactive   - Interactive mode with menu"
    echo "  diagnose      - Diagnose storage configuration issues"
    echo "  fix           - Run complete diagnostic and fix process"
    echo ""
    echo "Common Issues Fixed:"
    echo "  - Storage summary page showing wrong capacity"
    echo "  - Physical volumes smaller than actual disk size"
    echo "  - Volume groups with unallocated space"
    echo "  - Thin pools with high utilization"
    echo "  - Proxmox storage display inconsistencies"
    echo ""
    echo "Examples:"
    echo "  $0                  # Interactive mode"
    echo "  $0 diagnose         # Diagnose issues only"
    echo "  $0 fix              # Full diagnostic and fix"
    echo ""
    echo "This script specifically addresses issues where:"
    echo "  - Summary page shows 100GB but drive is 1TB"
    echo "  - LVM shows correct size but Proxmox summary doesn't"
    echo "  - Storage capacity isn't properly recognized"
    exit 0
fi

# Run main function
main "$@"
