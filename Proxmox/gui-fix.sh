#!/bin/bash

# Proxmox GUI Fix Script
# Diagnoses and fixes Proxmox web interface loading issues including JavaScript errors
# Usage: ./gui-fix.sh

# Configuration
LOG_FILE="/var/log/gui-fix.log"
BACKUP_DIR="/var/backups/gui-fix"

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

# Function to display system overview
display_system_overview() {
    echo -e "${BLUE}=== Proxmox System Overview ===${NC}"
    
    echo "Proxmox Version:"
    pveversion
    echo ""
    
    echo "System uptime:"
    uptime
    echo ""
    
    echo "Web interface status:"
    systemctl status pveproxy --no-pager -l | head -5
    echo ""
}

# Function to check for subscription popup modifications
check_subscription_popup_modifications() {
    echo -e "${BLUE}=== Checking for Subscription Popup Modifications ===${NC}"
    
    local popup_modified=false
    local critical_files=(
        "/usr/share/pve-manager/js/pvemanagerlib.js"
        "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    )
    
    for file in "${critical_files[@]}"; do
        if [[ -f "$file" ]]; then
            if grep -q "// POPUP DISABLED" "$file" 2>/dev/null; then
                echo -e "${YELLOW}⚠ Found subscription popup modifications in: $file${NC}"
                log_message "WARN" "Subscription popup modifications detected in: $file"
                popup_modified=true
                
                # Check if there's a backup from the subscription script
                local backup_file="/var/backups/subscription-popup-fix/$(basename "$file").backup"
                if [[ -f "$backup_file" ]]; then
                    echo -e "${CYAN}  └─ Backup available: $backup_file${NC}"
                else
                    echo -e "${RED}  └─ No backup found, will need package reinstallation${NC}"
                fi
            fi
        fi
    done
    
    if [[ "$popup_modified" == true ]]; then
        echo ""
        echo -e "${YELLOW}IMPORTANT: Subscription popup modifications detected!${NC}"
        echo "These modifications can sometimes cause JavaScript syntax errors that prevent"
        echo "the web interface from loading properly. The GUI repair process will:"
        echo "  1. Restore original files from backups (if available)"
        echo "  2. Or reinstall packages to get clean versions"
        echo "  3. Reapply popup modifications safely (if requested)"
        echo ""
        return 1
    else
        echo -e "${GREEN}✓ No subscription popup modifications detected${NC}"
        return 0
    fi
}

# Function to check web interface files
check_web_files() {
    echo -e "${BLUE}=== Checking Web Interface Files ===${NC}"
    
    local file_issues=false
    
    # Check critical web interface directories and files
    local web_dirs=(
        "/usr/share/pve-manager"
        "/usr/share/pve-manager/js"
        "/usr/share/javascript/proxmox-widget-toolkit"
        "/usr/share/javascript/extjs"
    )
    
    local critical_files=(
        "/usr/share/pve-manager/js/pvemanagerlib.js"
        "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
        "/usr/share/javascript/extjs/ext-all.js"
    )
    
    echo "Checking web interface directories..."
    for dir in "${web_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
            echo -e "${GREEN}✓ $dir exists (${file_count} files)${NC}"
        else
            echo -e "${RED}✗ $dir is missing${NC}"
            log_message "ERROR" "Web directory missing: $dir"
            file_issues=true
        fi
    done
    
    echo ""
    echo "Checking critical JavaScript files..."
    for file in "${critical_files[@]}"; do
        if [[ -f "$file" ]]; then
            local size=$(stat -c%s "$file" 2>/dev/null)
            if [[ $size -gt 0 ]]; then
                echo -e "${GREEN}✓ $file exists (${size} bytes)${NC}"
                
                # Basic syntax check for JavaScript files
                if [[ "$file" == *.js ]]; then
                    if command -v node &> /dev/null; then
                        if node -c "$file" 2>/dev/null; then
                            echo -e "${GREEN}  └─ JavaScript syntax is valid${NC}"
                        else
                            echo -e "${RED}  └─ JavaScript syntax error detected${NC}"
                            log_message "ERROR" "JavaScript syntax error in: $file"
                            file_issues=true
                        fi
                    else
                        echo -e "${YELLOW}  └─ Node.js not available, skipping syntax check${NC}"
                    fi
                fi
            else
                echo -e "${RED}✗ $file exists but is empty${NC}"
                log_message "ERROR" "Empty file: $file"
                file_issues=true
            fi
        else
            echo -e "${RED}✗ $file is missing${NC}"
            log_message "ERROR" "Missing critical file: $file"
            file_issues=true
        fi
    done
    
    # Check for common problematic files
    echo ""
    echo "Checking for problematic patterns..."
    
    # Look for StdWorkspace.js specifically mentioned in the error
    local stdworkspace_files=$(find /usr/share -name "*StdWorkspace*" 2>/dev/null)
    if [[ -n "$stdworkspace_files" ]]; then
        echo "Found StdWorkspace related files:"
        echo "$stdworkspace_files"
    else
        echo -e "${YELLOW}⚠ No StdWorkspace files found (this may be normal)${NC}"
    fi
    
    # Check file permissions on web directories
    echo ""
    echo "Checking file permissions..."
    for dir in "${web_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local perms=$(stat -c "%a" "$dir" 2>/dev/null)
            local owner=$(stat -c "%U:%G" "$dir" 2>/dev/null)
            echo "Directory $dir: permissions=$perms, owner=$owner"
            
            if [[ ! -r "$dir" ]]; then
                echo -e "${RED}✗ Directory $dir is not readable${NC}"
                file_issues=true
            fi
        fi
    done
    
    echo ""
    if [[ "$file_issues" == true ]]; then
        return 1
    else
        echo -e "${GREEN}✓ Web interface files appear intact${NC}"
        return 0
    fi
}

# Function to check web service configuration
check_web_service() {
    echo -e "${BLUE}=== Checking Web Service Configuration ===${NC}"
    
    local service_issues=false
    
    # Check pveproxy service
    echo "Checking pveproxy service..."
    if systemctl is-active --quiet pveproxy; then
        echo -e "${GREEN}✓ pveproxy service is running${NC}"
    else
        echo -e "${RED}✗ pveproxy service is not running${NC}"
        log_message "ERROR" "pveproxy service is not running"
        service_issues=true
    fi
    
    # Check if web interface is listening on port 8006
    echo "Checking web interface port..."
    if ss -tlnp | grep -q ":8006 "; then
        echo -e "${GREEN}✓ Web interface is listening on port 8006${NC}"
    else
        echo -e "${RED}✗ Web interface is not listening on port 8006${NC}"
        log_message "ERROR" "Web interface not listening on port 8006"
        service_issues=true
    fi
    
    # Check for recent pveproxy errors
    echo ""
    echo "Checking recent pveproxy errors..."
    local recent_errors=$(journalctl -u pveproxy --since="1 hour ago" --no-pager -q | grep -i "error\|fail\|exception" | tail -3)
    if [[ -n "$recent_errors" ]]; then
        echo -e "${YELLOW}Recent pveproxy errors found:${NC}"
        echo "$recent_errors"
        log_message "WARN" "Recent pveproxy errors detected"
    else
        echo -e "${GREEN}✓ No recent pveproxy errors${NC}"
    fi
    
    # Check web interface configuration files
    echo ""
    echo "Checking configuration files..."
    local config_files=(
        "/etc/default/pveproxy"
        "/etc/pve/local/pveproxy-ssl.pem"
        "/etc/pve/local/pveproxy-ssl.key"
    )
    
    for config in "${config_files[@]}"; do
        if [[ -f "$config" ]]; then
            echo -e "${GREEN}✓ $config exists${NC}"
        else
            if [[ "$config" == *"ssl"* ]]; then
                echo -e "${YELLOW}⚠ $config missing (may use default SSL)${NC}"
            else
                echo -e "${RED}✗ $config is missing${NC}"
                service_issues=true
            fi
        fi
    done
    
    echo ""
    if [[ "$service_issues" == true ]]; then
        return 1
    else
        return 0
    fi
}

# Function to check browser cache and temporary files
check_cache_files() {
    echo -e "${BLUE}=== Checking Cache and Temporary Files ===${NC}"
    
    local cache_issues=false
    
    # Check for web interface cache directories
    local cache_dirs=(
        "/var/cache/pve"
        "/var/tmp"
        "/tmp"
    )
    
    echo "Checking cache directories..."
    for dir in "${cache_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            local file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
            echo "Directory $dir: size=$size, files=$file_count"
            
            # Check if cache is excessively large
            local size_mb=$(du -sm "$dir" 2>/dev/null | cut -f1)
            if [[ $size_mb -gt 1000 ]]; then
                echo -e "${YELLOW}⚠ Cache directory $dir is large (${size}MB)${NC}"
                cache_issues=true
            fi
        else
            if [[ "$dir" == "/var/tmp" ]]; then
                echo -e "${RED}✗ Critical directory $dir is missing${NC}"
                cache_issues=true
            else
                echo -e "${YELLOW}⚠ $dir does not exist${NC}"
            fi
        fi
    done
    
    # Check for corrupted session files
    echo ""
    echo "Checking for corrupted temporary files..."
    local corrupted_files=$(find /var/tmp /tmp -name "*pve*" -type f -size 0 2>/dev/null)
    if [[ -n "$corrupted_files" ]]; then
        echo -e "${YELLOW}⚠ Found empty PVE temporary files (may indicate corruption):${NC}"
        echo "$corrupted_files" | head -5
        cache_issues=true
    else
        echo -e "${GREEN}✓ No corrupted temporary files found${NC}"
    fi
    
    echo ""
    if [[ "$cache_issues" == true ]]; then
        return 1
    else
        return 0
    fi
}

# Function to restore files from subscription popup backups
restore_from_popup_backups() {
    echo -e "${BLUE}=== Restoring from Subscription Popup Backups ===${NC}"
    
    local backup_dir="/var/backups/subscription-popup-fix"
    local restored_files=0
    
    if [[ ! -d "$backup_dir" ]]; then
        echo -e "${YELLOW}⚠ No subscription popup backup directory found${NC}"
        return 1
    fi
    
    local critical_files=(
        "/usr/share/pve-manager/js/pvemanagerlib.js"
        "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    )
    
    for file in "${critical_files[@]}"; do
        local backup_file="$backup_dir/$(basename "$file").backup"
        
        if [[ -f "$backup_file" && -f "$file" ]]; then
            if grep -q "// POPUP DISABLED" "$file" 2>/dev/null; then
                echo "Restoring $file from subscription popup backup..."
                if cp "$backup_file" "$file"; then
                    chmod 644 "$file"
                    chown root:root "$file"
                    echo -e "${GREEN}✓ Restored $file${NC}"
                    log_message "INFO" "Restored $file from subscription popup backup"
                    ((restored_files++))
                else
                    echo -e "${RED}✗ Failed to restore $file${NC}"
                    log_message "ERROR" "Failed to restore $file from backup"
                fi
            fi
        fi
    done
    
    if [[ $restored_files -gt 0 ]]; then
        echo -e "${GREEN}✓ Restored $restored_files files from subscription popup backups${NC}"
        
        # Ask if user wants to reapply popup fix safely
        echo ""
        if confirm_action "Would you like to reapply the subscription popup fix safely after verification"; then
            echo -e "${CYAN}Note: After the web interface is working, you can run:${NC}"
            echo "  sudo ./subscription-popup-fix.sh"
            echo "  (The improved version will be safer against JavaScript errors)"
        fi
        
        return 0
    else
        echo -e "${YELLOW}⚠ No files restored from subscription popup backups${NC}"
        return 1
    fi
}

# Function to repair web interface files
repair_web_files() {
    echo -e "${BLUE}=== Repairing Web Interface Files ===${NC}"
    
    # First try to restore from subscription popup backups
    local popup_backup_restored=false
    if ! check_subscription_popup_modifications >/dev/null 2>&1; then
        echo "Attempting to restore from subscription popup backups first..."
        if restore_from_popup_backups; then
            popup_backup_restored=true
            echo ""
        fi
    fi
    
    if [[ "$popup_backup_restored" == false ]] && confirm_action "Reinstall/repair Proxmox web interface packages"; then
        log_message "INFO" "Starting web interface repair"
        
        # Create backup directory
        mkdir -p "$BACKUP_DIR"
        
        echo "Backing up current configuration..."
        if [[ -d "/etc/pve" ]]; then
            tar -czf "$BACKUP_DIR/pve-config-backup-$(date +%s).tar.gz" /etc/pve/ 2>/dev/null
        fi
        
        # Update package lists
        echo "Updating package lists..."
        apt update
        
        # Reinstall web interface packages
        echo "Reinstalling Proxmox web interface packages..."
        local web_packages=(
            "pve-manager"
            "proxmox-widget-toolkit"
            "libjs-extjs"
            "pveproxy"
        )
        
        for package in "${web_packages[@]}"; do
            echo "Reinstalling $package..."
            if apt install --reinstall -y "$package"; then
                echo -e "${GREEN}✓ $package reinstalled successfully${NC}"
                log_message "INFO" "Successfully reinstalled $package"
            else
                echo -e "${RED}✗ Failed to reinstall $package${NC}"
                log_message "ERROR" "Failed to reinstall $package"
            fi
        done
        
        echo -e "${GREEN}✓ Web interface packages reinstalled${NC}"
        return 0
    else
        return 1
    fi
}

# Function to clear cache and temporary files
clear_cache_files() {
    echo -e "${BLUE}=== Clearing Cache and Temporary Files ===${NC}"
    
    if confirm_action "Clear web interface cache and temporary files"; then
        log_message "INFO" "Clearing cache and temporary files"
        
        # Stop pveproxy temporarily
        echo "Temporarily stopping pveproxy..."
        systemctl stop pveproxy
        
        # Clear cache directories
        echo "Clearing cache files..."
        rm -rf /var/cache/pve/* 2>/dev/null
        rm -rf /var/tmp/pve* 2>/dev/null
        rm -rf /tmp/pve* 2>/dev/null
        
        # Clear browser cache hints (remove etag files if they exist)
        find /usr/share/pve-manager -name "*.etag" -delete 2>/dev/null
        find /usr/share/javascript -name "*.etag" -delete 2>/dev/null
        
        # Recreate necessary directories with correct permissions
        mkdir -p /var/cache/pve
        chmod 755 /var/cache/pve
        
        # Ensure /var/tmp has correct permissions
        chmod 1777 /var/tmp
        
        # Restart pveproxy
        echo "Restarting pveproxy..."
        systemctl start pveproxy
        
        echo -e "${GREEN}✓ Cache and temporary files cleared${NC}"
        log_message "INFO" "Cache and temporary files cleared"
        return 0
    else
        return 1
    fi
}

# Function to restart web services
restart_web_services() {
    echo -e "${BLUE}=== Restarting Web Services ===${NC}"
    
    local services=(
        "pveproxy"
        "pvedaemon"
        "pvestatd"
    )
    
    local restart_success=true
    
    for service in "${services[@]}"; do
        if confirm_action "Restart $service"; then
            echo "Restarting $service..."
            log_message "INFO" "Restarting service: $service"
            
            if systemctl restart "$service"; then
                echo -e "${GREEN}✓ $service restarted successfully${NC}"
                log_message "INFO" "Successfully restarted $service"
                sleep 2
                
                # Verify service is running
                if systemctl is-active --quiet "$service"; then
                    echo -e "${GREEN}  └─ $service is now running${NC}"
                else
                    echo -e "${RED}  └─ $service failed to start properly${NC}"
                    restart_success=false
                fi
            else
                echo -e "${RED}✗ Failed to restart $service${NC}"
                log_message "ERROR" "Failed to restart $service"
                restart_success=false
            fi
        fi
    done
    
    echo ""
    if [[ "$restart_success" == true ]]; then
        echo -e "${GREEN}Service restart completed${NC}"
        return 0
    else
        return 1
    fi
}

# Function to test web interface
test_web_interface() {
    echo -e "${BLUE}=== Testing Web Interface ===${NC}"
    
    echo "Testing web interface connectivity..."
    
    # Get the server's IP address
    local server_ip=$(hostname -I | awk '{print $1}')
    local test_url="https://${server_ip}:8006"
    
    echo "Testing URL: $test_url"
    
    # Test basic connectivity
    if curl -k -s --connect-timeout 10 "$test_url" > /dev/null; then
        echo -e "${GREEN}✓ Web interface is responding${NC}"
        
        # Test for specific JavaScript files mentioned in the error
        echo "Testing critical JavaScript files..."
        local js_files=(
            "/pve2/js/pvemanagerlib.js"
            "/pve2/js/proxmoxlib.js"
        )
        
        for js_file in "${js_files[@]}"; do
            local js_url="https://${server_ip}:8006${js_file}"
            local http_status=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$js_url")
            
            if [[ "$http_status" == "200" ]]; then
                echo -e "${GREEN}✓ $js_file is accessible (HTTP $http_status)${NC}"
            else
                echo -e "${RED}✗ $js_file returned HTTP $http_status${NC}"
            fi
        done
        
        return 0
    else
        echo -e "${RED}✗ Web interface is not responding${NC}"
        return 1
    fi
}

# Function to display diagnostic information
display_diagnostics() {
    echo -e "${BLUE}=== Diagnostic Information ===${NC}"
    
    echo "Web interface process information:"
    ps aux | grep -E "pveproxy|pvedaemon" | grep -v grep
    echo ""
    
    echo "Network connections on port 8006:"
    ss -tulpn | grep :8006
    echo ""
    
    echo "Recent web interface log entries:"
    journalctl -u pveproxy --since="10 minutes ago" --no-pager -q | tail -5
    echo ""
    
    echo "Disk usage of web directories:"
    du -sh /usr/share/pve-manager /usr/share/javascript/proxmox-widget-toolkit 2>/dev/null
    echo ""
}

# Function to show usage help
show_help() {
    echo -e "${CYAN}Proxmox GUI Fix Script${NC}"
    echo "Diagnoses and fixes Proxmox web interface loading issues"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  check      - Run all diagnostic checks"
    echo "  repair     - Repair web interface files"
    echo "  cache      - Clear cache and temporary files"  
    echo "  restart    - Restart web services"
    echo "  test       - Test web interface functionality"
    echo "  diag       - Show diagnostic information"
    echo "  help       - Show this help message"
    echo ""
    echo "Interactive mode (default): Run without arguments for guided repair"
    echo ""
}

# Main function for interactive mode
main_interactive() {
    echo -e "${CYAN}Proxmox GUI Fix Script${NC}"
    echo "Automated diagnosis and repair of web interface loading issues"
    echo ""
    
    display_system_overview
    
    echo -e "${BLUE}=== Diagnostic Phase ===${NC}"
    
    local issues_found=0
    
    # Check for subscription popup modifications first
    if ! check_subscription_popup_modifications; then
        ((issues_found++))
    fi
    
    # Run all checks
    if ! check_web_files; then
        ((issues_found++))
    fi
    
    if ! check_web_service; then
        ((issues_found++))
    fi
    
    if ! check_cache_files; then
        ((issues_found++))
    fi
    
    echo ""
    if [[ $issues_found -gt 0 ]]; then
        echo -e "${YELLOW}Found $issues_found potential issues.${NC}"
        echo ""
        
        echo -e "${BLUE}=== Repair Phase ===${NC}"
        
        # Offer repairs based on issues found
        repair_web_files
        clear_cache_files
        restart_web_services
        
        echo ""
        echo -e "${BLUE}=== Verification Phase ===${NC}"
        test_web_interface
        
    else
        echo -e "${GREEN}No issues detected. Testing web interface...${NC}"
        test_web_interface
    fi
    
    echo ""
    echo -e "${CYAN}GUI fix process completed. Check the web interface in your browser.${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
}

# Main execution
main() {
    # Create log file directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Log script start
    log_message "INFO" "GUI fix script started"
    
    case "${1:-interactive}" in
        "check")
            check_root
            check_proxmox
            display_system_overview
            check_web_files
            check_web_service  
            check_cache_files
            ;;
        "repair")
            check_root
            check_proxmox
            repair_web_files
            ;;
        "cache")
            check_root
            check_proxmox
            clear_cache_files
            ;;
        "restart")
            check_root
            check_proxmox
            restart_web_services
            ;;
        "test")
            check_root
            check_proxmox
            test_web_interface
            ;;
        "diag")
            check_root
            check_proxmox
            display_diagnostics
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        "interactive"|"")
            check_root
            check_proxmox
            main_interactive
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
    
    log_message "INFO" "GUI fix script completed"
}

# Run main function
main "$@"
