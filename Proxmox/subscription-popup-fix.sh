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
    echo "    an enterprise subscription. It also configures repositories to"
    echo "    use the free no-subscription repository instead of enterprise."
    echo ""
    echo "USAGE:"
    echo "    sudo ./subscription-popup-fix.sh [OPTION]"
    echo ""
    echo "OPTIONS:"
    echo "    --help          Show this help message"
    echo "    --status        Check popup and repository status"
    echo "    --restore       Restore original popup and repositories"
    echo "    --backup        Create backup only (no modification)"
    echo "    --repo-only     Configure repositories only (no popup changes)"
    echo ""
    echo "EXAMPLES:"
    echo "    sudo ./subscription-popup-fix.sh           # Remove popup and configure repos"
    echo "    sudo ./subscription-popup-fix.sh --status  # Check current status"
    echo "    sudo ./subscription-popup-fix.sh --restore # Restore everything"
    echo "    sudo ./subscription-popup-fix.sh --repo-only # Fix repositories only"
    echo ""
    echo "WHAT IT DOES:"
    echo "    - Disables subscription popup warning"
    echo "    - Disables enterprise repository (pve-enterprise)"
    echo "    - Enables no-subscription repository (pve-no-subscription)"
    echo "    - Creates backups for easy restoration"
    echo ""
    echo "SAFETY:"
    echo "    - Creates automatic backups before any changes"
    echo "    - Validates JavaScript syntax before and after modifications"
    echo "    - Uses safer modification methods to prevent GUI loading issues"
    echo "    - Changes can be reverted with --restore option"
    echo "    - Repository changes are reversible"
    echo ""
    echo "IMPORTANT NOTES:"
    echo "    - JavaScript modifications can sometimes cause web interface issues"
    echo "    - If GUI loading problems occur, run: sudo ./gui-fix.sh"
    echo "    - The gui-fix.sh script can detect and repair popup-related issues"
    echo "    - Always test web interface functionality after running this script"
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
    
    # Check if popup is disabled - multiple detection methods
    
    # Method 1: Check for comment-based modifications
    if grep -q "// POPUP DISABLED\|/\* POPUP DISABLED" "$js_file" 2>/dev/null; then
        echo -e "${GREEN}✓ Subscription popup is currently DISABLED (comment method)${NC}"
        log_message "INFO" "Subscription popup is disabled via comment method"
        
        # Check if there's a backup
        local backup_file="$BACKUP_DIR/$(basename "$js_file").backup"
        if [[ -f "$backup_file" ]]; then
            echo -e "${CYAN}  Backup available: $backup_file${NC}"
        fi
        return 0
    fi
    
    # Method 2: Check for condition bypass (hardcoded false)
    # Look for the specific pattern where subscription check was replaced with false
    local subscription_condition_area=$(sed -n '610,620p' "$js_file" 2>/dev/null)
    if echo "$subscription_condition_area" | grep -q "res === null" && echo "$subscription_condition_area" | grep -q "false" && ! echo "$subscription_condition_area" | grep -q "res\.data\.status"; then
        echo -e "${GREEN}✓ Subscription popup is currently DISABLED (condition bypass)${NC}"
        log_message "INFO" "Subscription popup is disabled via condition bypass"
        
        # Check if there's a backup
        local backup_file="$BACKUP_DIR/$(basename "$js_file").backup"
        if [[ -f "$backup_file" ]]; then
            echo -e "${CYAN}  Backup available: $backup_file${NC}"
        fi
        return 0
    fi
    
    # Method 3: Check if subscription popup text still exists (enabled state)
    if grep -q "No valid subscription" "$js_file" 2>/dev/null; then
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
            # Ensure backup has correct permissions for future restoration
            chmod 644 "$backup_file"
            chown root:root "$backup_file"
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

# Function to validate JavaScript syntax
validate_javascript_syntax() {
    local js_file="$1"
    
    # Try to validate with node if available (most reliable)
    if command -v node &> /dev/null; then
        if node -c "$js_file" 2>/dev/null; then
            echo -e "${GREEN}✓ JavaScript syntax validated with Node.js${NC}"
            return 0
        else
            echo -e "${RED}✗ JavaScript syntax validation failed with Node.js${NC}"
            log_message "ERROR" "JavaScript syntax validation failed for $js_file"
            return 1
        fi
    else
        # Relaxed validation when Node.js is not available
        echo -e "${CYAN}⚠ Node.js not available, using relaxed validation${NC}"
        
        # Check for obvious syntax issues
        local file_size=$(wc -c < "$js_file")
        
        # File should be reasonable size (not empty, not huge)
        if [[ $file_size -lt 100 ]]; then
            echo -e "${RED}✗ JavaScript file appears to be empty or too small${NC}"
            return 1
        fi
        
        if [[ $file_size -gt 10000000 ]]; then
            echo -e "${RED}✗ JavaScript file appears to be unusually large${NC}"
            return 1
        fi
        
        # Check for basic JavaScript structure
        if ! grep -q "function\|var\|let\|const" "$js_file"; then
            echo -e "${RED}✗ File doesn't appear to contain JavaScript code${NC}"
            return 1
        fi
        
        # Check that file ends reasonably (not truncated)
        local last_chars=$(tail -c 10 "$js_file" | tr -d '\n\r\t ')
        if [[ ${#last_chars} -eq 0 ]]; then
            echo -e "${RED}✗ File appears to end unexpectedly${NC}"
            return 1
        fi
        
        echo -e "${GREEN}✓ Basic JavaScript structure validation passed${NC}"
        log_message "INFO" "Relaxed validation passed for $js_file"
        return 0
    fi
}

# Function to create safer popup modifications
create_safe_popup_modification() {
    local original_file="$1"
    local temp_file="$2"
    
    # More targeted and safer approach - only modify specific subscription popup calls
    # This approach is less likely to break other JavaScript functionality
    
    # Method 1: Direct condition bypass - most reliable for Proxmox 8.4.5+
    if sed 's/res\.data\.status\.toLowerCase() !== '\''active'\''/false/' "$original_file" > "$temp_file"; then
        if validate_javascript_syntax "$temp_file"; then
            echo -e "${GREEN}✓ Created safe popup modification (Method 1 - condition bypass)${NC}"
            return 0
        fi
    fi
    
    # Method 2: Replace gettext title with empty string
    cp "$original_file" "$temp_file"
    if sed -i "s/title: gettext('No valid subscription'),/\/\* POPUP DISABLED \*\/ title: '',/" "$temp_file"; then
        if validate_javascript_syntax "$temp_file"; then
            echo -e "${GREEN}✓ Created safe popup modification (Method 2 - empty title)${NC}"
            return 0
        fi
    fi
    
    # Method 3: Replace specific subscription warning patterns (legacy)
    cp "$original_file" "$temp_file"
    if sed -i 's/Ext\.Msg\.show({[^}]*title[^}]*subscription[^}]*});/\/\* POPUP DISABLED - subscription warning removed \*\//gi' "$temp_file"; then
        if validate_javascript_syntax "$temp_file"; then
            echo -e "${GREEN}✓ Created safe popup modification (Method 3 - pattern replacement)${NC}"
            return 0
        fi
    fi
    
    # Method 4: More conservative approach - comment out popup code
    cp "$original_file" "$temp_file"
    if sed -i 's/\(Ext\.Msg\.show({[^}]*[Nn]o valid subscription[^}]*})\)/\/\* POPUP DISABLED: \1 \*\//g' "$temp_file"; then
        if validate_javascript_syntax "$temp_file"; then
            echo -e "${GREEN}✓ Created safe popup modification (Method 4 - comment out)${NC}"
            return 0
        fi
    fi
    
    # Method 5: Fallback - minimal targeted replacement
    cp "$original_file" "$temp_file"
    if sed -i '/No valid subscription/s/Ext\.Msg\.show/\/\/ POPUP DISABLED - Ext.Msg.show/' "$temp_file"; then
        if validate_javascript_syntax "$temp_file"; then
            echo -e "${GREEN}✓ Created safe popup modification (Method 5 - minimal)${NC}"
            return 0
        fi
    fi
    
    echo -e "${RED}✗ All safe modification methods failed${NC}"
    return 1
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
    if grep -q "// POPUP DISABLED\|/\* POPUP DISABLED" "$js_file" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Subscription popup is already disabled${NC}"
        log_message "INFO" "Subscription popup already disabled"
        return 0
    fi
    
    # Validate original file syntax
    echo "Validating original file syntax..."
    if ! validate_javascript_syntax "$js_file"; then
        echo -e "${RED}✗ Original JavaScript file has syntax errors${NC}"
        echo "Cannot safely modify file with existing syntax errors."
        echo "Try running the GUI fix script first: ./gui-fix.sh"
        return 1
    fi
    
    # Create backup
    if ! create_backup "$js_file"; then
        return 1
    fi
    
    # Warning about potential GUI conflicts
    echo ""
    echo -e "${YELLOW}IMPORTANT SAFETY WARNING:${NC}"
    echo "Modifying JavaScript files can sometimes cause web interface loading issues."
    echo "If you experience problems after this modification:"
    echo "  1. Run: sudo ./gui-fix.sh"
    echo "  2. Or restore with: sudo ./subscription-popup-fix.sh --restore"
    echo ""
    
    if ! confirm_action "Continue with popup modification (understanding the risks)"; then
        return 1
    fi
    
    # Disable the popup using safer methods
    log_message "INFO" "Disabling subscription popup in $js_file with safer methods"
    
    # Create temporary file for safe modifications
    local temp_file=$(mktemp)
    
    # Use the safe modification function
    if create_safe_popup_modification "$js_file" "$temp_file"; then
        # Apply the safe modifications
        if mv "$temp_file" "$js_file"; then
            # Ensure correct file permissions
            chmod 644 "$js_file"
            chown root:root "$js_file"
            echo -e "${GREEN}✓ Successfully disabled subscription popup with safe method${NC}"
            log_message "INFO" "Successfully disabled subscription popup with safe method"
        else
            echo -e "${RED}✗ Failed to apply safe modifications${NC}"
            log_message "ERROR" "Failed to apply safe modifications"
            rm -f "$temp_file"
            return 1
        fi
    else
        echo -e "${RED}✗ All safe modification methods failed${NC}"
        echo "The JavaScript file structure may be incompatible with safe modification."
        echo "This could indicate:"
        echo "  1. The file has already been modified by another tool"
        echo "  2. The Proxmox version uses a different popup mechanism"  
        echo "  3. There are existing syntax errors in the file"
        log_message "ERROR" "Failed to create safe popup modifications"
        rm -f "$temp_file"
        return 1
    fi
    
    # Final validation of the modified file
    echo "Validating modified file..."
    if ! validate_javascript_syntax "$js_file"; then
        echo -e "${RED}✗ Modified file failed syntax validation${NC}"
        echo "Restoring from backup..."
        
        # Restore from backup
        local backup_file="$BACKUP_DIR/$(basename "$js_file").backup"
        if [[ -f "$backup_file" ]]; then
            cp "$backup_file" "$js_file"
            chmod 644 "$js_file"
            chown root:root "$js_file"
            echo -e "${YELLOW}⚠ Restored original file due to syntax errors${NC}"
            log_message "ERROR" "Restored original file due to syntax errors in modification"
        fi
        return 1
    else
        echo -e "${GREEN}✓ Modified file passed syntax validation${NC}"
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
            # Ensure correct permissions after restoration
            chmod 644 "$js_file"
            chown root:root "$js_file"
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

# Function to check repository status
check_repository_status() {
    echo -e "${BLUE}=== Checking Repository Configuration ===${NC}"
    
    local enterprise_repo="/etc/apt/sources.list.d/pve-enterprise.list"
    local no_sub_repo="/etc/apt/sources.list.d/pve-no-subscription.list"
    
    # Check enterprise repository
    if [[ -f "$enterprise_repo" ]]; then
        if grep -q "^deb" "$enterprise_repo" 2>/dev/null; then
            echo -e "${YELLOW}⚠ Enterprise repository is ENABLED${NC}"
            echo "  File: $enterprise_repo"
            log_message "INFO" "Enterprise repository is enabled"
        else
            echo -e "${GREEN}✓ Enterprise repository is DISABLED${NC}"
            echo "  File: $enterprise_repo"
        fi
    else
        echo -e "${CYAN}  Enterprise repository file not found${NC}"
    fi
    
    # Check no-subscription repository
    if [[ -f "$no_sub_repo" ]]; then
        if grep -q "^deb" "$no_sub_repo" 2>/dev/null; then
            echo -e "${GREEN}✓ No-subscription repository is ENABLED${NC}"
            echo "  File: $no_sub_repo"
            log_message "INFO" "No-subscription repository is enabled"
            return 0
        else
            echo -e "${YELLOW}⚠ No-subscription repository is DISABLED${NC}"
            echo "  File: $no_sub_repo"
        fi
    else
        echo -e "${YELLOW}⚠ No-subscription repository is NOT CONFIGURED${NC}"
    fi
    
    return 1
}

# Function to backup repository files
backup_repository_files() {
    echo -e "${CYAN}Creating repository backups...${NC}"
    
    mkdir -p "$BACKUP_DIR"
    
    local enterprise_repo="/etc/apt/sources.list.d/pve-enterprise.list"
    local no_sub_repo="/etc/apt/sources.list.d/pve-no-subscription.list"
    
    if [[ -f "$enterprise_repo" ]]; then
        local backup_file="$BACKUP_DIR/pve-enterprise.list.backup"
        if [[ ! -f "$backup_file" ]]; then
            if cp "$enterprise_repo" "$backup_file"; then
                echo -e "${GREEN}✓ Backed up enterprise repository${NC}"
                log_message "INFO" "Backed up enterprise repository to $backup_file"
            fi
        fi
    fi
    
    if [[ -f "$no_sub_repo" ]]; then
        local backup_file="$BACKUP_DIR/pve-no-subscription.list.backup"
        if [[ ! -f "$backup_file" ]]; then
            if cp "$no_sub_repo" "$backup_file"; then
                echo -e "${GREEN}✓ Backed up no-subscription repository${NC}"
                log_message "INFO" "Backed up no-subscription repository to $backup_file"
            fi
        fi
    fi
}

# Function to configure repositories for no-subscription use
configure_repositories() {
    echo -e "${BLUE}=== Configuring Repositories ===${NC}"
    
    # Backup existing repository files
    backup_repository_files
    
    local enterprise_repo="/etc/apt/sources.list.d/pve-enterprise.list"
    local no_sub_repo="/etc/apt/sources.list.d/pve-no-subscription.list"
    
    # Get Proxmox version to determine correct repository
    local pve_version=$(pveversion | grep "pve-manager" | cut -d'/' -f2 | cut -d'-' -f1 | cut -d'.' -f1)
    local debian_codename
    
    # Determine Debian codename based on Proxmox version
    case "$pve_version" in
        8|"")
            debian_codename="bookworm"
            ;;
        7)
            debian_codename="bullseye"
            ;;
        6)
            debian_codename="buster"
            ;;
        *)
            echo -e "${YELLOW}⚠ Unknown Proxmox version, defaulting to bookworm${NC}"
            debian_codename="bookworm"
            ;;
    esac
    
    echo "Detected Proxmox version: $pve_version (Debian: $debian_codename)"
    
    # Disable enterprise repository
    if [[ -f "$enterprise_repo" ]]; then
        echo "Disabling enterprise repository..."
        if sed -i 's/^deb/#deb/g' "$enterprise_repo"; then
            echo -e "${GREEN}✓ Enterprise repository disabled${NC}"
            log_message "INFO" "Enterprise repository disabled"
        else
            echo -e "${YELLOW}⚠ Failed to disable enterprise repository${NC}"
            log_message "WARN" "Failed to disable enterprise repository"
        fi
    else
        echo -e "${CYAN}  Enterprise repository not found, creating disabled version${NC}"
        cat > "$enterprise_repo" << EOF
# deb https://enterprise.proxmox.com/debian/pve $debian_codename pve-enterprise
# This repository is disabled by subscription-popup-fix script
# To enable, remove the # at the beginning of the line above
EOF
        echo -e "${GREEN}✓ Created disabled enterprise repository${NC}"
    fi
    
    # Enable/create no-subscription repository
    echo "Configuring no-subscription repository..."
    cat > "$no_sub_repo" << EOF
# No-subscription repository for Proxmox VE
deb http://download.proxmox.com/debian/pve $debian_codename pve-no-subscription
EOF
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ No-subscription repository enabled${NC}"
        log_message "INFO" "No-subscription repository enabled for $debian_codename"
    else
        echo -e "${RED}✗ Failed to configure no-subscription repository${NC}"
        log_message "ERROR" "Failed to configure no-subscription repository"
        return 1
    fi
    
    # Update package lists
    echo "Updating package lists..."
    if apt update -qq 2>/dev/null; then
        echo -e "${GREEN}✓ Package lists updated successfully${NC}"
        log_message "INFO" "Package lists updated after repository configuration"
    else
        echo -e "${YELLOW}⚠ Package list update had warnings (this is normal)${NC}"
        log_message "WARN" "Package list update completed with warnings"
    fi
    
    return 0
}

# Function to restore original repositories
restore_repositories() {
    echo -e "${BLUE}=== Restoring Original Repositories ===${NC}"
    
    local enterprise_backup="$BACKUP_DIR/pve-enterprise.list.backup"
    local no_sub_backup="$BACKUP_DIR/pve-no-subscription.list.backup"
    local enterprise_repo="/etc/apt/sources.list.d/pve-enterprise.list"
    local no_sub_repo="/etc/apt/sources.list.d/pve-no-subscription.list"
    
    local restored=false
    
    # Restore enterprise repository
    if [[ -f "$enterprise_backup" ]]; then
        if cp "$enterprise_backup" "$enterprise_repo"; then
            echo -e "${GREEN}✓ Restored enterprise repository${NC}"
            log_message "INFO" "Restored enterprise repository from backup"
            restored=true
        fi
    else
        echo -e "${YELLOW}⚠ No enterprise repository backup found${NC}"
    fi
    
    # Restore no-subscription repository
    if [[ -f "$no_sub_backup" ]]; then
        if cp "$no_sub_backup" "$no_sub_repo"; then
            echo -e "${GREEN}✓ Restored no-subscription repository${NC}"
            log_message "INFO" "Restored no-subscription repository from backup"
            restored=true
        fi
    else
        # If no backup exists, remove the file we created
        if [[ -f "$no_sub_repo" ]] && grep -q "subscription-popup-fix script" "$no_sub_repo" 2>/dev/null; then
            rm -f "$no_sub_repo"
            echo -e "${GREEN}✓ Removed configured no-subscription repository${NC}"
            log_message "INFO" "Removed no-subscription repository (no backup existed)"
            restored=true
        fi
    fi
    
    if [[ "$restored" == true ]]; then
        echo "Updating package lists..."
        apt update -qq 2>/dev/null
        echo -e "${GREEN}✓ Package lists updated${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ No repository changes to restore${NC}"
        return 1
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
            echo ""
            check_popup_status
            local popup_result=$?
            echo ""
            check_repository_status
            local repo_result=$?
            if [[ $popup_result -eq 0 && $repo_result -eq 0 ]]; then
                exit 0
            else
                exit 1
            fi
            ;;
        --restore)
            check_root
            check_proxmox
            echo "This will restore both popup and repository settings from backups."
            echo ""
            if confirm_action "Restore original subscription popup and repositories"; then
                local popup_restored=false
                local repo_restored=false
                
                # Restore popup
                if restore_subscription_popup; then
                    popup_restored=true
                fi
                
                echo ""
                # Restore repositories  
                if restore_repositories; then
                    repo_restored=true
                fi
                
                echo ""
                if [[ "$popup_restored" == true && "$repo_restored" == true ]]; then
                    echo -e "${GREEN}=== Complete Restore Successful! ===${NC}"
                    echo "Both popup and repositories have been restored to original state."
                elif [[ "$popup_restored" == true ]]; then
                    echo -e "${GREEN}=== Popup Restored ===${NC}"
                    echo -e "${YELLOW}Repository restoration had issues (see above)${NC}"
                elif [[ "$repo_restored" == true ]]; then
                    echo -e "${GREEN}=== Repositories Restored ===${NC}"
                    echo -e "${YELLOW}Popup restoration had issues (see above)${NC}"
                else
                    echo -e "${YELLOW}=== Restore Had Issues ===${NC}"
                    echo "Check the messages above for details."
                fi
            fi
            exit 0
            ;;
        --backup)
            check_root
            check_proxmox
            echo "Creating backups of JavaScript files and repositories..."
            echo ""
            
            local js_file
            js_file=$(find_proxmox_js_path)
            if [[ -n "$js_file" ]]; then
                create_backup "$js_file"
            else
                echo -e "${RED}✗ Could not find Proxmox JavaScript files${NC}"
                exit 1
            fi
            
            backup_repository_files
            echo -e "${GREEN}✓ Backup completed${NC}"
            exit 0
            ;;
        --repo-only)
            check_root
            check_proxmox
            display_system_info
            echo ""
            check_repository_status
            echo ""
            if confirm_action "Configure repositories for no-subscription use (disable enterprise, enable no-subscription)"; then
                if configure_repositories; then
                    echo ""
                    echo -e "${GREEN}=== Repository Configuration Complete! ===${NC}"
                    echo "Enterprise repository disabled, no-subscription repository enabled."
                    echo "You can now update packages without subscription warnings."
                    echo ""
                    echo "To check status: sudo ./subscription-popup-fix.sh --status"
                    echo "To restore: sudo ./subscription-popup-fix.sh --restore"
                else
                    echo ""
                    echo -e "${RED}=== Repository Configuration Failed! ===${NC}"
                    echo "Check the messages above for details."
                    exit 1
                fi
            fi
            exit 0
            ;;
        "")
            # Default action - disable popup and configure repos
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
    
    # Check current popup status
    echo ""
    local popup_status_result
    check_popup_status
    popup_status_result=$?
    
    # Check repository status
    echo ""
    local repo_status_result
    check_repository_status
    repo_status_result=$?
    
    # Determine what needs to be done
    local popup_needs_fix=$([[ $popup_status_result -ne 0 ]] && echo true || echo false)
    local repo_needs_fix=$([[ $repo_status_result -ne 0 ]] && echo true || echo false)
    
    echo ""
    if [[ "$popup_needs_fix" == false && "$repo_needs_fix" == false ]]; then
        echo -e "${GREEN}=== Everything Already Configured! ===${NC}"
        echo "✓ Subscription popup is already disabled"
        echo "✓ Repositories are already configured for no-subscription use"
        echo ""
        echo "Use --status to check current status"
        echo "Use --restore to restore original settings"
        exit 0
    fi
    
    # Show what will be done
    echo -e "${BLUE}=== Configuration Summary ===${NC}"
    if [[ "$popup_needs_fix" == true ]]; then
        echo "Will disable subscription popup warning"
    else
        echo "✓ Subscription popup already disabled"
    fi
    
    if [[ "$repo_needs_fix" == true ]]; then
        echo "Will disable enterprise repository and enable no-subscription repository"
    else
        echo "✓ Repositories already configured correctly"
    fi
    
    echo ""
    if confirm_action "Apply these changes"; then
        local popup_success=true
        local repo_success=true
        
        # Disable popup if needed
        if [[ "$popup_needs_fix" == true ]]; then
            echo ""
            if ! disable_subscription_popup; then
                popup_success=false
            fi
        fi
        
        # Configure repositories if needed
        if [[ "$repo_needs_fix" == true ]]; then
            echo ""
            if ! configure_repositories; then
                repo_success=false
            fi
        fi
        
        # Show final results
        echo ""
        if [[ "$popup_success" == true && "$repo_success" == true ]]; then
            echo -e "${GREEN}=== Complete Success! ===${NC}"
            echo "✓ Subscription popup disabled"
            echo "✓ Repositories configured for no-subscription use"
            echo ""
            echo "You should no longer see subscription warnings when:"
            echo "  - Logging into the web interface"
            echo "  - Running apt update/upgrade commands"
            echo ""
            echo "To restore original settings:"
            echo "  sudo ./subscription-popup-fix.sh --restore"
            echo ""
            echo "To check status:"
            echo "  sudo ./subscription-popup-fix.sh --status"
        elif [[ "$popup_success" == true ]]; then
            echo -e "${GREEN}=== Partial Success ===${NC}"
            echo "✓ Subscription popup disabled"
            echo -e "${YELLOW}⚠ Repository configuration had issues${NC}"
            echo "Check the messages above for details."
        elif [[ "$repo_success" == true ]]; then
            echo -e "${GREEN}=== Partial Success ===${NC}"
            echo "✓ Repositories configured for no-subscription use"
            echo -e "${YELLOW}⚠ Popup configuration had issues${NC}"
            echo "Check the messages above for details."
        else
            echo -e "${RED}=== Configuration Failed! ===${NC}"
            echo "Both popup and repository configuration had issues."
            echo "Check the messages above and log file for details: $LOG_FILE"
            exit 1
        fi
    else
        echo "Operation cancelled."
        exit 0
    fi
}

# Run main function
main "$@"
