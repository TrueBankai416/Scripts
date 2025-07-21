#!/bin/bash

# Proxmox Subscription Popup Fix Script
# Removes the "no valid subscription" popup that appears on login
# Usage: ./subscription-popup-fix.sh

# Configuration
LOG_FILE="/var/log/subscription-popup-fix.log"
BACKUP_DIR="/var/backups/subscription-popup-fix"

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

# Function to confirm action
confirm_action() {
    local message="$1"
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

# Function to display help
show_help() {
    echo "Proxmox Subscription Popup Fix Script"
    echo ""
    echo "DESCRIPTION:"
    echo "    This script removes the 'no valid subscription' popup warning"
    echo "    that appears when logging into Proxmox web interface without"
    echo "    an enterprise subscription."
    echo ""
    echo "USAGE:"
    echo "    sudo ./subscription-popup-fix.sh [OPTION]"
    echo ""
    echo "OPTIONS:"
    echo "    --help          Show this help message"
    echo "    --status        Check if popup is currently disabled"
    echo "    --restore       Restore original popup functionality"
    echo "    --backup        Create backup only (no modification)"
    echo ""
    echo "EXAMPLES:"
    echo "    sudo ./subscription-popup-fix.sh           # Remove popup with confirmation"
    echo "    sudo ./subscription-popup-fix.sh --status  # Check current status"
    echo "    sudo ./subscription-popup-fix.sh --restore # Restore original popup"
    echo ""
    echo "SAFETY:"
    echo "    - Creates automatic backups before any changes"
    echo "    - Changes can be reverted with --restore option"
    echo "    - Only modifies JavaScript files, no system changes"
    echo ""
}

# Function to find Proxmox widget toolkit path
find_proxmox_js_path() {
    local possible_paths=(
        "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
        "/usr/share/pve-manager/js/pvemanagerlib.js"
        "/usr/share/javascript/proxmox-widget-toolkit/proxmox-widget-toolkit.js"
        "/usr/share/pve-manager/js/proxmox-widget-toolkit.js"
    )
    
    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    # Search for files containing subscription check
    local found_files=$(find /usr/share -name "*.js" -type f -exec grep -l "No valid subscription" {} \; 2>/dev/null | head -1)
    if [[ -n "$found_files" ]]; then
        echo "$found_files"
        return 0
    fi
    
    return 1
}

# Function to check current popup status
check_popup_status() {
    echo -e "${BLUE}=== Checking Subscription Popup Status ===${NC}"
    
    local js_file
    js_file=$(find_proxmox_js_path)
    
    if [[ -z "$js_file" ]]; then
        echo -e "${RED}✗ Could not find Proxmox JavaScript files${NC}"
        log_message "ERROR" "Could not find Proxmox JavaScript files"
        return 1
    fi
    
    echo "Found Proxmox JS file: $js_file"
    
    # Check if popup is disabled (looking for our modification)
    if grep -q "// POPUP DISABLED" "$js_file" 2>/dev/null; then
        echo -e "${GREEN}✓ Subscription popup is currently DISABLED${NC}"
        log_message "INFO" "Subscription popup is disabled"
        
        # Check if there's a backup
        local backup_file="$BACKUP_DIR/$(basename "$js_file").backup"
        if [[ -f "$backup_file" ]]; then
            echo -e "${CYAN}  Backup available: $backup_file${NC}"
        fi
        return 0
    elif grep -q "No valid subscription" "$js_file" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Subscription popup is currently ENABLED${NC}"
        log_message "INFO" "Subscription popup is enabled"
        return 2
    else
        echo -e "${RED}✗ Could not determine popup status${NC}"
        log_message "WARN" "Could not determine popup status"
        return 1
    fi
}

# Function to create backup
create_backup() {
    local js_file="$1"
    
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/$(basename "$js_file").backup"
    
    if [[ ! -f "$backup_file" ]]; then
        if cp "$js_file" "$backup_file"; then
            echo -e "${GREEN}✓ Created backup: $backup_file${NC}"
            log_message "INFO" "Created backup: $backup_file"
            return 0
        else
            echo -e "${RED}✗ Failed to create backup${NC}"
            log_message "ERROR" "Failed to create backup: $backup_file"
            return 1
        fi
    else
        echo -e "${CYAN}  Backup already exists: $backup_file${NC}"
        log_message "INFO" "Backup already exists: $backup_file"
        return 0
    fi
}

# Function to disable subscription popup
disable_subscription_popup() {
    echo -e "${BLUE}=== Disabling Subscription Popup ===${NC}"
    
    local js_file
    js_file=$(find_proxmox_js_path)
    
    if [[ -z "$js_file" ]]; then
        echo -e "${RED}✗ Could not find Proxmox JavaScript files${NC}"
        log_message "ERROR" "Could not find Proxmox JavaScript files"
        return 1
    fi
    
    echo "Target file: $js_file"
    
    # Check if already disabled
    if grep -q "// POPUP DISABLED" "$js_file" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Subscription popup is already disabled${NC}"
        log_message "INFO" "Subscription popup already disabled"
        return 0
    fi
    
    # Create backup
    if ! create_backup "$js_file"; then
        return 1
    fi
    
    # Disable the popup by modifying the subscription check
    log_message "INFO" "Disabling subscription popup in $js_file"
    
    # Method 1: Replace subscription check with empty function
    if grep -q "Ext\.Msg\.show" "$js_file" && grep -q "No valid subscription" "$js_file"; then
        # Create a temporary file with our modifications
        local temp_file=$(mktemp)
        
        # Use sed to replace the subscription popup code
        sed '/No valid subscription/,/Ext\.Msg\.show/c\
// POPUP DISABLED - Original subscription check replaced\
void(0);' "$js_file" > "$temp_file"
        
        if [[ -s "$temp_file" ]]; then
            if mv "$temp_file" "$js_file"; then
                echo -e "${GREEN}✓ Successfully disabled subscription popup${NC}"
                log_message "INFO" "Successfully disabled subscription popup"
            else
                echo -e "${RED}✗ Failed to apply changes${NC}"
                log_message "ERROR" "Failed to apply changes"
                rm -f "$temp_file"
                return 1
            fi
        else
            echo -e "${RED}✗ Failed to create modified file${NC}"
            log_message "ERROR" "Failed to create modified file"
            rm -f "$temp_file"
            return 1
        fi
    else
        # Method 2: More targeted approach - replace specific function calls
        if sed -i.tmp 's/Ext\.Msg\.show({[^}]*No valid subscription[^}]*});/\/\/ POPUP DISABLED - subscription check removed/g' "$js_file"; then
            rm -f "$js_file.tmp"
            echo -e "${GREEN}✓ Successfully disabled subscription popup${NC}"
            log_message "INFO" "Successfully disabled subscription popup using targeted replacement"
        else
            echo -e "${RED}✗ Failed to modify subscription popup${NC}"
            log_message "ERROR" "Failed to modify subscription popup"
            return 1
        fi
    fi
    
    # Restart pveproxy to reload changes
    echo "Restarting pveproxy to apply changes..."
    if systemctl restart pveproxy; then
        echo -e "${GREEN}✓ pveproxy restarted successfully${NC}"
        log_message "INFO" "pveproxy restarted successfully"
    else
        echo -e "${YELLOW}⚠ Failed to restart pveproxy, changes may not be active${NC}"
        log_message "WARN" "Failed to restart pveproxy"
    fi
    
    return 0
}

# Function to restore original popup
restore_subscription_popup() {
    echo -e "${BLUE}=== Restoring Original Subscription Popup ===${NC}"
    
    local js_file
    js_file=$(find_proxmox_js_path)
    
    if [[ -z "$js_file" ]]; then
        echo -e "${RED}✗ Could not find Proxmox JavaScript files${NC}"
        log_message "ERROR" "Could not find Proxmox JavaScript files"
        return 1
    fi
    
    local backup_file="$BACKUP_DIR/$(basename "$js_file").backup"
    
    if [[ ! -f "$backup_file" ]]; then
        echo -e "${RED}✗ No backup file found: $backup_file${NC}"
        log_message "ERROR" "No backup file found: $backup_file"
        return 1
    fi
    
    if confirm_action "Restore original subscription popup from backup"; then
        if cp "$backup_file" "$js_file"; then
            echo -e "${GREEN}✓ Original subscription popup restored${NC}"
            log_message "INFO" "Original subscription popup restored from backup"
            
            # Restart pveproxy
            echo "Restarting pveproxy to apply changes..."
            if systemctl restart pveproxy; then
                echo -e "${GREEN}✓ pveproxy restarted successfully${NC}"
                log_message "INFO" "pveproxy restarted after restore"
            else
                echo -e "${YELLOW}⚠ Failed to restart pveproxy${NC}"
                log_message "WARN" "Failed to restart pveproxy after restore"
            fi
            return 0
        else
            echo -e "${RED}✗ Failed to restore from backup${NC}"
            log_message "ERROR" "Failed to restore from backup"
            return 1
        fi
    fi
}

# Function to display system information
display_system_info() {
    echo -e "${BLUE}=== System Information ===${NC}"
    
    echo "Proxmox Version:"
    pveversion 2>/dev/null || echo "Unable to determine version"
    echo ""
    
    echo "Web Interface URL:"
    local hostname=$(hostname -f 2>/dev/null || hostname)
    echo "https://$hostname:8006"
    echo ""
    
    echo "Current Date/Time:"
    date
    echo ""
}

# Main script logic
main() {
    # Parse command line arguments
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --status)
            check_root
            check_proxmox
            display_system_info
            check_popup_status
            exit $?
            ;;
        --restore)
            check_root
            check_proxmox
            restore_subscription_popup
            exit $?
            ;;
        --backup)
            check_root
            check_proxmox
            local js_file
            js_file=$(find_proxmox_js_path)
            if [[ -n "$js_file" ]]; then
                create_backup "$js_file"
            else
                echo -e "${RED}✗ Could not find Proxmox JavaScript files${NC}"
                exit 1
            fi
            exit $?
            ;;
        "")
            # Default action - disable popup
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    
    # Check prerequisites
    check_root
    check_proxmox
    
    # Display system information
    display_system_info
    
    # Check current status
    local status_result
    check_popup_status
    status_result=$?
    
    if [[ $status_result -eq 0 ]]; then
        echo -e "${CYAN}The subscription popup is already disabled.${NC}"
        echo "Use --restore to re-enable it, or --status to check again."
        exit 0
    elif [[ $status_result -eq 1 ]]; then
        echo -e "${RED}Unable to determine popup status. Continuing anyway...${NC}"
    fi
    
    echo ""
    if confirm_action "Disable the 'No valid subscription' popup warning"; then
        if disable_subscription_popup; then
            echo ""
            echo -e "${GREEN}=== Success! ===${NC}"
            echo "The subscription popup has been disabled."
            echo "You should no longer see the subscription warning when logging in."
            echo ""
            echo "To restore the original popup:"
            echo "  sudo $(basename "$0") --restore"
            echo ""
            echo "To check status:"
            echo "  sudo $(basename "$0") --status"
        else
            echo ""
            echo -e "${RED}=== Failed! ===${NC}"
            echo "Could not disable the subscription popup."
            echo "Check the log file for details: $LOG_FILE"
            exit 1
        fi
    else
        echo "Operation cancelled."
        exit 0
    fi
}

# Run main function
main "$@"
