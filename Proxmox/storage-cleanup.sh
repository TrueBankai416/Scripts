#!/bin/bash

# Proxmox Storage Cleanup Script
# Safely cleans up common space consumers in Proxmox
# Usage: ./storage-cleanup.sh

# Configuration
LOG_FILE="/var/log/storage-cleanup.log"
BACKUP_DIR="/var/backups/storage-cleanup"
DRY_RUN=false

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

# Function to confirm action
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN] Would execute: $message${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    echo -n "Continue? [y/N]: "
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        echo "Skipped."
        return 1
    fi
}

# Function to clean package cache
clean_package_cache() {
    echo -e "${BLUE}=== Cleaning Package Cache ===${NC}"
    
    # Check current cache size
    if [[ -d "/var/cache/apt" ]]; then
        local cache_size=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
        echo "Current APT cache size: $cache_size"
        
        if confirm_action "Clean APT package cache"; then
            log_message "INFO" "Cleaning APT cache"
            if [[ "$DRY_RUN" == false ]]; then
                apt clean
                local new_size=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
                echo -e "${GREEN}APT cache cleaned. New size: $new_size${NC}"
                log_message "INFO" "APT cache cleaned successfully"
            fi
        fi
    fi
    
    # Remove orphaned packages
    if confirm_action "Remove orphaned packages"; then
        log_message "INFO" "Removing orphaned packages"
        if [[ "$DRY_RUN" == false ]]; then
            apt autoremove -y
            echo -e "${GREEN}Orphaned packages removed${NC}"
            log_message "INFO" "Orphaned packages removed successfully"
        fi
    fi
    
    echo ""
}

# Function to clean log files
clean_log_files() {
    echo -e "${BLUE}=== Cleaning Log Files ===${NC}"
    
    # Show current log usage
    echo "Current log directory usage:"
    du -sh /var/log/* 2>/dev/null | sort -hr | head -10
    echo ""
    
    # Clean systemd journal
    if confirm_action "Clean systemd journal (keep last 7 days)"; then
        log_message "INFO" "Cleaning systemd journal"
        if [[ "$DRY_RUN" == false ]]; then
            journalctl --vacuum-time=7d
            echo -e "${GREEN}Systemd journal cleaned${NC}"
            log_message "INFO" "Systemd journal cleaned successfully"
        fi
    fi
    
    # Rotate log files
    if confirm_action "Force log rotation"; then
        log_message "INFO" "Forcing log rotation"
        if [[ "$DRY_RUN" == false ]]; then
            logrotate -f /etc/logrotate.conf
            echo -e "${GREEN}Log rotation completed${NC}"
            log_message "INFO" "Log rotation completed successfully"
        fi
    fi
    
    # Clean old compressed logs
    local old_logs=$(find /var/log -name "*.gz" -mtime +30 2>/dev/null | wc -l)
    if [[ $old_logs -gt 0 ]]; then
        if confirm_action "Remove compressed log files older than 30 days ($old_logs files)"; then
            log_message "INFO" "Removing old compressed logs"
            if [[ "$DRY_RUN" == false ]]; then
                find /var/log -name "*.gz" -mtime +30 -delete
                echo -e "${GREEN}Old compressed logs removed${NC}"
                log_message "INFO" "Old compressed logs removed successfully"
            fi
        fi
    fi
    
    echo ""
}

# Function to clean VM backups
clean_vm_backups() {
    echo -e "${BLUE}=== Cleaning VM Backups ===${NC}"
    
    local backup_dir="/var/lib/vz/dump"
    
    if [[ ! -d "$backup_dir" ]]; then
        echo "No VM backup directory found"
        return
    fi
    
    # Show current backup usage
    echo "Current backup directory usage:"
    du -sh "$backup_dir" 2>/dev/null
    echo ""
    
    echo "VM backups by date:"
    find "$backup_dir" -name "*.vma*" -o -name "*.tar*" 2>/dev/null | \
        xargs -I {} ls -lh {} 2>/dev/null | sort -k 6,7
    echo ""
    
    # Remove backups older than specified days
    local days_old=30
    echo -n "Remove backups older than how many days? [30]: "
    read -r user_days
    [[ -n "$user_days" ]] && days_old="$user_days"
    
    local old_backups=$(find "$backup_dir" -name "*.vma*" -o -name "*.tar*" -mtime +$days_old 2>/dev/null | wc -l)
    
    if [[ $old_backups -gt 0 ]]; then
        if confirm_action "Remove $old_backups VM backups older than $days_old days"; then
            log_message "INFO" "Removing old VM backups (older than $days_old days)"
            if [[ "$DRY_RUN" == false ]]; then
                find "$backup_dir" -name "*.vma*" -o -name "*.tar*" -mtime +$days_old -delete
                echo -e "${GREEN}Old VM backups removed${NC}"
                log_message "INFO" "Old VM backups removed successfully"
            fi
        fi
    else
        echo "No old backups found (older than $days_old days)"
    fi
    
    echo ""
}

# Function to clean temporary files
clean_temp_files() {
    echo -e "${BLUE}=== Cleaning Temporary Files ===${NC}"
    
    # Check temp directories
    local temp_dirs=("/tmp" "/var/tmp")
    
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            echo "Current $dir usage: $size"
            
            # Show what's in temp directory
            echo "Largest items in $dir:"
            du -h "$dir"/* 2>/dev/null | sort -hr | head -5
            echo ""
            
            if confirm_action "Clean $dir (files older than 7 days)"; then
                log_message "INFO" "Cleaning $dir"
                if [[ "$DRY_RUN" == false ]]; then
                    find "$dir" -type f -mtime +7 -delete 2>/dev/null
                    find "$dir" -type d -empty -delete 2>/dev/null
                    echo -e "${GREEN}$dir cleaned${NC}"
                    log_message "INFO" "$dir cleaned successfully"
                fi
            fi
        fi
    done
    
    echo ""
}

# Function to clean VM templates
clean_vm_templates() {
    echo -e "${BLUE}=== Cleaning VM Templates ===${NC}"
    
    local template_dir="/var/lib/vz/template"
    
    if [[ ! -d "$template_dir" ]]; then
        echo "No VM template directory found"
        return
    fi
    
    # Show current template usage
    echo "Current template directory usage:"
    du -sh "$template_dir"/* 2>/dev/null | sort -hr
    echo ""
    
    # Check for ISO files
    local iso_dir="$template_dir/iso"
    if [[ -d "$iso_dir" ]]; then
        echo "ISO files:"
        find "$iso_dir" -name "*.iso" -exec ls -lh {} \; 2>/dev/null | sort -k 5 -hr
        echo ""
        
        if confirm_action "Review and potentially remove unused ISO files"; then
            echo "Review the ISO files above and remove any that are no longer needed"
            echo "ISO directory: $iso_dir"
        fi
    fi
    
    echo ""
}

# Function to optimize thin pools
optimize_thin_pools() {
    echo -e "${BLUE}=== Optimizing Thin Pools ===${NC}"
    
    # Check if LVM thin pools exist
    if ! command -v lvs &> /dev/null; then
        echo "LVM commands not available"
        return
    fi
    
    # Show current thin pool status
    echo "Current thin pool status:"
    lvs -o lv_name,vg_name,lv_size,data_percent,metadata_percent,pool_lv 2>/dev/null | grep -E 'pool|thin' || echo "No thin pools found"
    echo ""
    
    # Run fstrim on mounted filesystems
    if confirm_action "Run fstrim on all mounted filesystems"; then
        log_message "INFO" "Running fstrim on mounted filesystems"
        if [[ "$DRY_RUN" == false ]]; then
            if command -v fstrim &> /dev/null; then
                fstrim -av
                echo -e "${GREEN}fstrim completed${NC}"
                log_message "INFO" "fstrim completed successfully"
            else
                echo -e "${YELLOW}fstrim not available${NC}"
            fi
        fi
    fi
    
    echo ""
}

# Function to show space savings
show_space_savings() {
    echo -e "${BLUE}=== Space Savings Summary ===${NC}"
    
    echo "Current disk usage:"
    df -h | grep -E '^/dev|^tmpfs' | sort -k 5 -hr
    echo ""
    
    echo "To see detailed usage analysis, run: ./storage-analyzer.sh"
    echo ""
}

# Function to create cleanup report
create_cleanup_report() {
    local report_file="/tmp/storage-cleanup-report.txt"
    
    echo -e "${BLUE}=== Generating Cleanup Report ===${NC}"
    
    {
        echo "Proxmox Storage Cleanup Report"
        echo "Generated: $(date)"
        echo "==============================="
        echo ""
        
        echo "DISK USAGE AFTER CLEANUP:"
        df -h | grep -E '^/dev|^tmpfs'
        echo ""
        
        echo "CLEANUP ACTIONS PERFORMED:"
        if [[ -f "$LOG_FILE" ]]; then
            grep "INFO" "$LOG_FILE" | tail -20
        fi
        echo ""
        
        echo "RECOMMENDATIONS FOR FURTHER CLEANUP:"
        echo "1. Review VM disk images for unused or oversized disks"
        echo "2. Consider compressing old VM backups"
        echo "3. Monitor log rotation to prevent future buildup"
        echo "4. Regular maintenance with this script"
        echo ""
        
    } > "$report_file"
    
    echo "Cleanup report saved to: $report_file"
    echo ""
}

# Interactive mode function
interactive_mode() {
    echo -e "${CYAN}=== Interactive Cleanup Mode ===${NC}"
    echo ""
    
    echo "What would you like to clean?"
    echo "1. Package cache (apt clean, autoremove)"
    echo "2. Log files (journal, rotated logs)"
    echo "3. VM backups (old backup files)"
    echo "4. Temporary files (/tmp, /var/tmp)"
    echo "5. VM templates and ISOs"
    echo "6. Optimize thin pools (fstrim)"
    echo "7. All of the above"
    echo "8. Exit"
    echo ""
    
    echo -n "Enter your choice (1-8): "
    read -r choice
    
    case "$choice" in
        1) clean_package_cache ;;
        2) clean_log_files ;;
        3) clean_vm_backups ;;
        4) clean_temp_files ;;
        5) clean_vm_templates ;;
        6) optimize_thin_pools ;;
        7) 
            clean_package_cache
            clean_log_files
            clean_vm_backups
            clean_temp_files
            clean_vm_templates
            optimize_thin_pools
            ;;
        8) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
    esac
}

# Main function
main() {
    echo -e "${CYAN}=== Proxmox Storage Cleanup ===${NC}"
    echo ""
    
    # Check if running as root
    check_root
    
    # Create log file and backup directory
    touch "$LOG_FILE"
    mkdir -p "$BACKUP_DIR"
    
    log_message "INFO" "Storage cleanup started"
    
    # Show initial disk usage
    echo "Initial disk usage:"
    df -h | grep -E '^/dev|^tmpfs' | sort -k 5 -hr
    echo ""
    
    # Run interactive mode or specific cleanup
    if [[ "$1" == "interactive" || "$1" == "" ]]; then
        interactive_mode
    elif [[ "$1" == "all" ]]; then
        clean_package_cache
        clean_log_files
        clean_vm_backups
        clean_temp_files
        clean_vm_templates
        optimize_thin_pools
    else
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use 'interactive' or 'all' or run without arguments for interactive mode"
        exit 1
    fi
    
    # Show final results
    show_space_savings
    create_cleanup_report
    
    echo -e "${GREEN}Storage cleanup completed!${NC}"
    echo "Check log file: $LOG_FILE"
    
    log_message "INFO" "Storage cleanup completed"
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [mode] [options]"
    echo ""
    echo "Proxmox Storage Cleanup Script"
    echo "Safely cleans up common space consumers in Proxmox"
    echo ""
    echo "Modes:"
    echo "  (no args)     - Interactive mode with menu"
    echo "  interactive   - Interactive mode with menu"
    echo "  all           - Clean all categories automatically"
    echo ""
    echo "Options:"
    echo "  --dry-run     - Show what would be done without making changes"
    echo "  -h, --help    - Show this help message"
    echo ""
    echo "Cleanup categories:"
    echo "  1. Package cache (apt clean, autoremove)"
    echo "  2. Log files (journal, rotated logs)"
    echo "  3. VM backups (old backup files)"
    echo "  4. Temporary files (/tmp, /var/tmp)"
    echo "  5. VM templates and ISOs"
    echo "  6. Thin pool optimization (fstrim)"
    echo ""
    echo "Examples:"
    echo "  $0                  # Interactive mode"
    echo "  $0 all              # Clean all categories"
    echo "  $0 interactive      # Interactive mode"
    echo "  $0 --dry-run all    # Preview all cleanup actions"
    exit 0
fi

# Handle dry run option
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

# Run main function
main "$@"
