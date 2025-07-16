#!/bin/bash

# Proxmox Storage Analyzer Script
# Analyzes storage usage and identifies what's consuming space
# Usage: ./storage-analyzer.sh

# Configuration
LOG_FILE="/var/log/storage-analyzer.log"
REPORT_FILE="/tmp/storage-report.txt"

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

# Function to format bytes to human readable
format_bytes() {
    local bytes=$1
    if [[ $bytes -gt 1073741824 ]]; then
        echo "$(( bytes / 1073741824 ))GB"
    elif [[ $bytes -gt 1048576 ]]; then
        echo "$(( bytes / 1048576 ))MB"
    elif [[ $bytes -gt 1024 ]]; then
        echo "$(( bytes / 1024 ))KB"
    else
        echo "${bytes}B"
    fi
}

# Function to get disk usage summary
get_disk_usage() {
    echo -e "${BLUE}=== Disk Usage Summary ===${NC}"
    echo "Overall filesystem usage:"
    df -h | grep -E '^/dev|^tmpfs' | sort -k 5 -hr
    echo ""
    
    echo "LVM Information:"
    echo "Physical Volumes:"
    pvs 2>/dev/null || echo "No PVs found or LVM not available"
    echo ""
    echo "Volume Groups:"
    vgs 2>/dev/null || echo "No VGs found or LVM not available"
    echo ""
    echo "Logical Volumes:"
    lvs 2>/dev/null || echo "No LVs found or LVM not available"
    echo ""
}

# Function to analyze directory usage
analyze_directory_usage() {
    echo -e "${BLUE}=== Directory Usage Analysis ===${NC}"
    
    echo "Top 10 largest directories in root filesystem:"
    du -h /* 2>/dev/null | sort -hr | head -10
    echo ""
    
    # Analyze common Proxmox directories
    local directories=(
        "/var/lib/vz/images"
        "/var/lib/vz/dump"
        "/var/lib/vz/template"
        "/var/log"
        "/var/cache"
        "/tmp"
        "/var/tmp"
        "/root"
        "/home"
        "/usr"
        "/opt"
    )
    
    echo "Analysis of common Proxmox directories:"
    for dir in "${directories[@]}"; do
        if [[ -d "$dir" ]]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            local file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
            echo "  $dir: $size ($file_count files)"
        fi
    done
    echo ""
}

# Function to analyze VM storage
analyze_vm_storage() {
    echo -e "${BLUE}=== VM Storage Analysis ===${NC}"
    
    # Check if qm command is available
    if ! command -v qm &> /dev/null; then
        echo "qm command not found - this doesn't appear to be a Proxmox system"
        return
    fi
    
    echo "VM List and basic info:"
    qm list 2>/dev/null || echo "No VMs found or qm not available"
    echo ""
    
    echo "Storage status:"
    pvesm status 2>/dev/null || echo "pvesm not available"
    echo ""
    
    # Analyze VM disk images
    if [[ -d "/var/lib/vz/images" ]]; then
        echo "VM disk images by size:"
        find /var/lib/vz/images -name "*.qcow2" -o -name "*.raw" -o -name "*.vmdk" 2>/dev/null | \
            xargs -I {} ls -lh {} 2>/dev/null | sort -k 5 -hr | head -20
        echo ""
    fi
    
    # Analyze VM backups
    if [[ -d "/var/lib/vz/dump" ]]; then
        echo "VM backups by size:"
        find /var/lib/vz/dump -name "*.vma*" -o -name "*.tar*" 2>/dev/null | \
            xargs -I {} ls -lh {} 2>/dev/null | sort -k 5 -hr | head -10
        echo ""
    fi
}

# Function to analyze log files
analyze_log_files() {
    echo -e "${BLUE}=== Log File Analysis ===${NC}"
    
    echo "Largest log files (>10MB):"
    find /var/log -type f -size +10M -exec ls -lh {} \; 2>/dev/null | sort -k 5 -hr
    echo ""
    
    echo "Log directories by size:"
    du -sh /var/log/* 2>/dev/null | sort -hr | head -10
    echo ""
    
    # Check for specific problematic logs
    local log_files=(
        "/var/log/syslog"
        "/var/log/kern.log"
        "/var/log/daemon.log"
        "/var/log/auth.log"
        "/var/log/pveproxy/access.log"
        "/var/log/pvedaemon.log"
    )
    
    echo "Specific log file sizes:"
    for log in "${log_files[@]}"; do
        if [[ -f "$log" ]]; then
            ls -lh "$log" 2>/dev/null
        fi
    done
    echo ""
}

# Function to analyze package cache
analyze_package_cache() {
    echo -e "${BLUE}=== Package Cache Analysis ===${NC}"
    
    if [[ -d "/var/cache/apt" ]]; then
        echo "APT cache usage:"
        du -sh /var/cache/apt/* 2>/dev/null | sort -hr
        echo ""
    fi
    
    if [[ -d "/var/lib/apt" ]]; then
        echo "APT lib usage:"
        du -sh /var/lib/apt/* 2>/dev/null | sort -hr
        echo ""
    fi
}

# Function to check for large files
find_large_files() {
    echo -e "${BLUE}=== Large Files Analysis ===${NC}"
    
    echo "Files larger than 1GB:"
    find / -type f -size +1G -exec ls -lh {} \; 2>/dev/null | sort -k 5 -hr | head -20
    echo ""
    
    echo "Files larger than 500MB:"
    find / -type f -size +500M -not -path "/proc/*" -not -path "/sys/*" -not -path "/dev/*" \
        -exec ls -lh {} \; 2>/dev/null | sort -k 5 -hr | head -20
    echo ""
}

# Function to check for duplicate files
check_duplicate_files() {
    echo -e "${BLUE}=== Duplicate Files Check ===${NC}"
    
    if command -v fdupes &> /dev/null; then
        echo "Checking for duplicate files in common directories..."
        fdupes -r /var/lib/vz/dump 2>/dev/null | head -20
        echo ""
    else
        echo "fdupes not installed - skipping duplicate file check"
        echo "Install with: apt install fdupes"
        echo ""
    fi
}

# Function to analyze swap usage
analyze_swap() {
    echo -e "${BLUE}=== Swap Analysis ===${NC}"
    
    echo "Swap usage:"
    swapon --show 2>/dev/null || echo "No swap configured"
    echo ""
    
    echo "Memory usage:"
    free -h
    echo ""
}

# Function to check for core dumps
check_core_dumps() {
    echo -e "${BLUE}=== Core Dumps Check ===${NC}"
    
    echo "Looking for core dumps..."
    find / -name "core*" -type f -size +1M 2>/dev/null | head -10
    echo ""
}

# Function to analyze LVM thin pools
analyze_lvm_thin_pools() {
    echo -e "${BLUE}=== LVM Thin Pool Analysis ===${NC}"
    
    echo "Thin pool information:"
    lvs -o +lv_layout,pool_lv,data_percent,metadata_percent 2>/dev/null | grep -E 'thin|pool' || echo "No thin pools found"
    echo ""
    
    echo "Thin pool usage details:"
    lvs -o lv_name,vg_name,lv_size,data_percent,metadata_percent,pool_lv 2>/dev/null | grep -E 'data|thin' || echo "No thin volumes found"
    echo ""
}

# Function to provide cleanup recommendations
provide_recommendations() {
    echo -e "${YELLOW}=== Cleanup Recommendations ===${NC}"
    
    echo "Based on the analysis above, here are recommended cleanup actions:"
    echo ""
    
    echo "1. Log Files:"
    echo "   - Rotate and compress old logs: logrotate -f /etc/logrotate.conf"
    echo "   - Clear systemd journal: journalctl --vacuum-time=7d"
    echo "   - Clear old kernel logs manually if needed"
    echo ""
    
    echo "2. Package Cache:"
    echo "   - Clean APT cache: apt clean"
    echo "   - Remove orphaned packages: apt autoremove"
    echo ""
    
    echo "3. VM Management:"
    echo "   - Remove old VM backups in /var/lib/vz/dump/"
    echo "   - Check for unused VM disk images"
    echo "   - Consider compressing VM backups"
    echo ""
    
    echo "4. Temporary Files:"
    echo "   - Clear /tmp and /var/tmp (be careful with running processes)"
    echo "   - Check for large files that can be safely removed"
    echo ""
    
    echo "5. Thin Pool Management:"
    echo "   - Consider running fstrim on thin pools"
    echo "   - Monitor data_percent and metadata_percent"
    echo ""
    
    echo "Use the companion cleanup script for automated cleanup options."
    echo ""
}

# Function to generate summary report
generate_report() {
    echo -e "${BLUE}=== Generating Summary Report ===${NC}"
    
    {
        echo "Proxmox Storage Analysis Report"
        echo "Generated: $(date)"
        echo "==============================="
        echo ""
        
        echo "DISK USAGE SUMMARY:"
        df -h | grep -E '^/dev|^tmpfs'
        echo ""
        
        echo "TOP 10 LARGEST DIRECTORIES:"
        du -h /* 2>/dev/null | sort -hr | head -10
        echo ""
        
        echo "LARGEST FILES (>500MB):"
        find / -type f -size +500M -not -path "/proc/*" -not -path "/sys/*" -not -path "/dev/*" \
            -exec ls -lh {} \; 2>/dev/null | sort -k 5 -hr | head -10
        echo ""
        
        echo "LOG FILE SUMMARY:"
        find /var/log -type f -size +10M -exec ls -lh {} \; 2>/dev/null | sort -k 5 -hr | head -10
        echo ""
        
        echo "LVM THIN POOL STATUS:"
        lvs -o +lv_layout,pool_lv,data_percent,metadata_percent 2>/dev/null | grep -E 'thin|pool'
        echo ""
        
        echo "CLEANUP RECOMMENDATIONS:"
        echo "1. Review and remove old VM backups"
        echo "2. Clean package cache with 'apt clean'"
        echo "3. Rotate and compress log files"
        echo "4. Remove orphaned packages with 'apt autoremove'"
        echo "5. Clear temporary files from /tmp and /var/tmp"
        
    } > "$REPORT_FILE"
    
    echo "Report saved to: $REPORT_FILE"
    echo ""
}

# Main function
main() {
    echo -e "${CYAN}=== Proxmox Storage Analyzer ===${NC}"
    echo ""
    
    # Check if running as root
    check_root
    
    # Create log file
    touch "$LOG_FILE"
    log_message "INFO" "Storage analysis started"
    
    # Run all analysis functions
    get_disk_usage
    analyze_directory_usage
    analyze_vm_storage
    analyze_log_files
    analyze_package_cache
    find_large_files
    check_duplicate_files
    analyze_swap
    check_core_dumps
    analyze_lvm_thin_pools
    provide_recommendations
    generate_report
    
    echo -e "${GREEN}Storage analysis complete!${NC}"
    echo "Check the report at: $REPORT_FILE"
    echo "Log file: $LOG_FILE"
    
    log_message "INFO" "Storage analysis completed"
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0"
    echo ""
    echo "Proxmox Storage Analyzer"
    echo "Analyzes storage usage and provides cleanup recommendations"
    echo ""
    echo "The script will:"
    echo "  - Analyze disk usage and identify space consumers"
    echo "  - Check VM storage and backups"
    echo "  - Examine log files and caches"
    echo "  - Find large files and duplicates"
    echo "  - Provide cleanup recommendations"
    echo "  - Generate a summary report"
    echo ""
    echo "Output files:"
    echo "  Report: $REPORT_FILE"
    echo "  Log: $LOG_FILE"
    echo ""
    echo "Run the companion storage-cleanup.sh script for automated cleanup."
    exit 0
fi

# Run main function
main "$@"
