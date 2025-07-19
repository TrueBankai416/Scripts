#!/bin/bash

# Proxmox Console Fix Script
# Diagnoses and fixes common Proxmox console 500 errors
# Usage: ./console-fix.sh

# Configuration
LOG_FILE="/var/log/console-fix.log"
BACKUP_DIR="/var/backups/console-fix"

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
    
    echo "Current disk usage:"
    df -h | grep -E '^/dev|^tmpfs' | head -5
    echo ""
    
    echo "Memory usage:"
    free -h
    echo ""
    
    echo "Load average:"
    cat /proc/loadavg
    echo ""
}

# Function to check Proxmox services
check_proxmox_services() {
    echo -e "${BLUE}=== Checking Proxmox Services ===${NC}"
    
    local services=(
        "pveproxy"
        "pvedaemon" 
        "pvestatd"
        "pve-cluster"
        "pve-firewall"
        "spiceproxy"
    )
    
    local failed_services=()
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}✓ $service is running${NC}"
            log_message "INFO" "Service $service is running"
        else
            echo -e "${RED}✗ $service is not running${NC}"
            log_message "ERROR" "Service $service is not running"
            failed_services+=("$service")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Failed services: ${failed_services[*]}${NC}"
        return 1
    else
        echo -e "${GREEN}All Proxmox services are running${NC}"
        return 0
    fi
    echo ""
}

# Function to check disk space
check_disk_space() {
    echo -e "${BLUE}=== Checking Disk Space ===${NC}"
    
    local space_issues=false
    
    # Check root filesystem
    local root_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    echo "Root filesystem usage: ${root_usage}%"
    
    if [[ $root_usage -gt 90 ]]; then
        echo -e "${RED}✗ Root filesystem is critically full (${root_usage}%)${NC}"
        log_message "ERROR" "Root filesystem critically full: ${root_usage}%"
        space_issues=true
    elif [[ $root_usage -gt 80 ]]; then
        echo -e "${YELLOW}⚠ Root filesystem is getting full (${root_usage}%)${NC}"
        log_message "WARN" "Root filesystem getting full: ${root_usage}%"
    else
        echo -e "${GREEN}✓ Root filesystem usage is normal${NC}"
    fi
    
    # Check /var specifically (where logs are stored)
    if [[ -d "/var" ]]; then
        local var_usage=$(df /var | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null)
        if [[ -n "$var_usage" ]]; then
            echo "/var filesystem usage: ${var_usage}%"
            if [[ $var_usage -gt 90 ]]; then
                echo -e "${RED}✗ /var filesystem is critically full (${var_usage}%)${NC}"
                log_message "ERROR" "/var filesystem critically full: ${var_usage}%"
                space_issues=true
            fi
        fi
    fi
    
    # Check for large log files
    echo ""
    echo "Checking for large log files..."
    local large_logs=$(find /var/log -type f -size +100M 2>/dev/null)
    if [[ -n "$large_logs" ]]; then
        echo -e "${YELLOW}Large log files found:${NC}"
        echo "$large_logs" | xargs -I {} ls -lh {} 2>/dev/null | head -5
        space_issues=true
    else
        echo -e "${GREEN}✓ No excessively large log files found${NC}"
    fi
    
    echo ""
    if [[ "$space_issues" == true ]]; then
        return 1
    else
        return 0
    fi
}

# Function to check SSL certificates
check_ssl_certificates() {
    echo -e "${BLUE}=== Checking SSL Certificates ===${NC}"
    
    local cert_issues=false
    
    # Check main Proxmox certificate
    local cert_file="/etc/pve/local/pve-ssl.pem"
    local key_file="/etc/pve/local/pve-ssl.key"
    
    if [[ -f "$cert_file" ]]; then
        echo "Checking main SSL certificate..."
        
        # Check certificate validity
        local cert_info=$(openssl x509 -in "$cert_file" -noout -dates 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            echo "Certificate dates:"
            echo "$cert_info"
            
            # Check if certificate is expired
            if ! openssl x509 -in "$cert_file" -noout -checkend 0 2>/dev/null; then
                echo -e "${RED}✗ SSL certificate is expired${NC}"
                log_message "ERROR" "SSL certificate is expired"
                cert_issues=true
            else
                echo -e "${GREEN}✓ SSL certificate is valid${NC}"
            fi
        else
            echo -e "${RED}✗ SSL certificate is corrupted or unreadable${NC}"
            log_message "ERROR" "SSL certificate is corrupted"
            cert_issues=true
        fi
    else
        echo -e "${RED}✗ SSL certificate file not found: $cert_file${NC}"
        log_message "ERROR" "SSL certificate file not found"
        cert_issues=true
    fi
    
    # Check certificate key
    if [[ -f "$key_file" ]]; then
        if openssl rsa -in "$key_file" -check -noout 2>/dev/null; then
            echo -e "${GREEN}✓ SSL private key is valid${NC}"
        else
            echo -e "${RED}✗ SSL private key is corrupted${NC}"
            log_message "ERROR" "SSL private key is corrupted"
            cert_issues=true
        fi
    else
        echo -e "${RED}✗ SSL private key file not found: $key_file${NC}"
        log_message "ERROR" "SSL private key file not found"
        cert_issues=true
    fi
    
    echo ""
    if [[ "$cert_issues" == true ]]; then
        return 1
    else
        return 0
    fi
}

# Function to check file permissions
check_file_permissions() {
    echo -e "${BLUE}=== Checking File Permissions ===${NC}"
    
    local permission_issues=false
    
    # Check critical Proxmox directories
    local directories=(
        "/etc/pve"
        "/var/lib/pve-cluster"
        "/var/log/pve"
        "/var/lib/vz"
        "/var/tmp"
    )
    
    for dir in "${directories[@]}"; do
        if [[ -d "$dir" ]]; then
            local owner=$(stat -c "%U:%G" "$dir" 2>/dev/null)
            local perms=$(stat -c "%a" "$dir" 2>/dev/null)
            echo "Directory $dir: owner=$owner, permissions=$perms"
            
            # Check if directory is accessible
            if [[ ! -r "$dir" || ! -x "$dir" ]]; then
                echo -e "${RED}✗ Directory $dir is not accessible${NC}"
                log_message "ERROR" "Directory $dir is not accessible"
                permission_issues=true
            fi
            
            # Special check for /var/tmp - needs sticky bit (1777)
            if [[ "$dir" == "/var/tmp" && "$perms" != "1777" ]]; then
                echo -e "${YELLOW}⚠ /var/tmp permissions should be 1777 (sticky bit)${NC}"
                log_message "WARN" "/var/tmp has incorrect permissions: $perms (should be 1777)"
                permission_issues=true
            fi
        else
            if [[ "$dir" == "/var/tmp" ]]; then
                echo -e "${RED}✗ CRITICAL: Directory $dir does not exist (required for console temp files)${NC}"
                log_message "ERROR" "Critical directory $dir does not exist"
                permission_issues=true
            else
                echo -e "${YELLOW}⚠ Directory $dir does not exist${NC}"
            fi
        fi
    done
    
    # Check critical files
    local files=(
        "/etc/pve/local/pve-ssl.pem"
        "/etc/pve/local/pve-ssl.key"
        "/etc/pve/storage.cfg"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            local owner=$(stat -c "%U:%G" "$file" 2>/dev/null)
            local perms=$(stat -c "%a" "$file" 2>/dev/null)
            echo "File $file: owner=$owner, permissions=$perms"
            
            if [[ ! -r "$file" ]]; then
                echo -e "${RED}✗ File $file is not readable${NC}"
                log_message "ERROR" "File $file is not readable"
                permission_issues=true
            fi
        fi
    done
    
    echo ""
    if [[ "$permission_issues" == true ]]; then
        return 1
    else
        echo -e "${GREEN}✓ File permissions appear correct${NC}"
        return 0
    fi
}

# Function to check console-specific components
check_console_components() {
    echo -e "${BLUE}=== Checking Console Components ===${NC}"
    
    local console_issues=false
    
    # Check if novnc is installed and working
    echo "Checking noVNC components..."
    if [[ -d "/usr/share/novnc" ]]; then
        echo -e "${GREEN}✓ noVNC directory found${NC}"
    else
        echo -e "${RED}✗ noVNC directory not found${NC}"
        console_issues=true
    fi
    
    # Check pveproxy configuration
    local pveproxy_conf="/etc/default/pveproxy"
    if [[ -f "$pveproxy_conf" ]]; then
        echo -e "${GREEN}✓ pveproxy configuration found${NC}"
    else
        echo -e "${YELLOW}⚠ pveproxy configuration not found${NC}"
    fi
    
    # Check if console ports are listening
    echo "Checking console port listeners..."
    local console_ports=("8006" "5900-5999")
    
    for port_range in "${console_ports[@]}"; do
        if [[ "$port_range" == "8006" ]]; then
            if ss -tlnp | grep -q ":$port_range "; then
                echo -e "${GREEN}✓ Port $port_range is listening${NC}"
            else
                echo -e "${RED}✗ Port $port_range is not listening${NC}"
                console_issues=true
            fi
        else
            # Check VNC port range
            local vnc_listening=$(ss -tlnp | grep -c ":59[0-9][0-9] ")
            if [[ $vnc_listening -gt 0 ]]; then
                echo -e "${GREEN}✓ VNC ports are listening ($vnc_listening active)${NC}"
            else
                echo -e "${YELLOW}⚠ No VNC ports currently listening${NC}"
            fi
        fi
    done
    
    echo ""
    if [[ "$console_issues" == true ]]; then
        return 1
    else
        return 0
    fi
}

# Function to check recent logs for errors
check_recent_logs() {
    echo -e "${BLUE}=== Checking Recent Log Errors ===${NC}"
    
    echo "Recent Proxmox daemon errors:"
    journalctl -u pvedaemon --since="10 minutes ago" --no-pager -q | grep -i error | tail -5
    echo ""
    
    echo "Recent Proxmox proxy errors:"
    journalctl -u pveproxy --since="10 minutes ago" --no-pager -q | grep -i error | tail -5
    echo ""
    
    echo "Recent system errors related to console:"
    journalctl --since="10 minutes ago" --no-pager -q | grep -i "console\|vnc\|websocket" | tail -5
    echo ""
}

# Function to restart Proxmox services
restart_proxmox_services() {
    echo -e "${BLUE}=== Restarting Proxmox Services ===${NC}"
    
    local services=(
        "pvestatd"
        "pvedaemon"
        "pveproxy"
    )
    
    local restart_success=true
    
    for service in "${services[@]}"; do
        if confirm_action "Restart $service service"; then
            echo "Restarting $service..."
            log_message "INFO" "Restarting service: $service"
            
            if systemctl restart "$service"; then
                echo -e "${GREEN}✓ $service restarted successfully${NC}"
                log_message "INFO" "Successfully restarted $service"
                sleep 2
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

# Function to regenerate SSL certificates
regenerate_ssl_certificates() {
    echo -e "${BLUE}=== Regenerating SSL Certificates ===${NC}"
    
    if confirm_action "Regenerate Proxmox SSL certificates (this will create new self-signed certificates)"; then
        log_message "INFO" "Regenerating SSL certificates"
        
        # Backup existing certificates
        mkdir -p "$BACKUP_DIR"
        if [[ -f "/etc/pve/local/pve-ssl.pem" ]]; then
            cp "/etc/pve/local/pve-ssl.pem" "$BACKUP_DIR/pve-ssl.pem.backup.$(date +%s)"
        fi
        if [[ -f "/etc/pve/local/pve-ssl.key" ]]; then
            cp "/etc/pve/local/pve-ssl.key" "$BACKUP_DIR/pve-ssl.key.backup.$(date +%s)"
        fi
        
        # Generate new certificates
        if pvecm updatecerts --force 2>/dev/null; then
            echo -e "${GREEN}✓ SSL certificates regenerated successfully${NC}"
            log_message "INFO" "SSL certificates regenerated successfully"
            
            # Restart pveproxy to use new certificates
            systemctl restart pveproxy
            echo -e "${GREEN}✓ pveproxy restarted with new certificates${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed to regenerate SSL certificates${NC}"
            log_message "ERROR" "Failed to regenerate SSL certificates"
            return 1
        fi
    fi
}

# Function to clean up disk space
cleanup_disk_space() {
    echo -e "${BLUE}=== Cleaning Up Disk Space ===${NC}"
    
    if confirm_action "Clean up log files and temporary data to free disk space"; then
        log_message "INFO" "Cleaning up disk space"
        
        # Clean old compressed logs
        find /var/log -name "*.gz" -mtime +7 -delete 2>/dev/null
        
        # Clean systemd journal
        journalctl --vacuum-time=3d 2>/dev/null
        
        # Clean APT cache
        apt clean 2>/dev/null
        
        # Clean temporary files
        find /tmp -type f -mtime +1 -delete 2>/dev/null
        find /var/tmp -type f -mtime +1 -delete 2>/dev/null
        
        echo -e "${GREEN}✓ Disk cleanup completed${NC}"
        log_message "INFO" "Disk cleanup completed"
        
        # Show new disk usage
        echo "Updated disk usage:"
        df -h / | tail -1
    fi
}

# Function to test console access
test_console_access() {
    echo -e "${BLUE}=== Testing Console Access ===${NC}"
    
    echo "Testing Proxmox web interface connectivity..."
    
    # Test if pveproxy is responding
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8006 | grep -q "200\|302\|401"; then
        echo -e "${GREEN}✓ Proxmox web interface is responding${NC}"
    else
        echo -e "${RED}✗ Proxmox web interface is not responding${NC}"
        return 1
    fi
    
    # Check if we can list VMs (basic API test)
    if qm list >/dev/null 2>&1; then
        echo -e "${GREEN}✓ VM management API is working${NC}"
        
        # Show available VMs
        local vm_count=$(qm list | wc -l)
        if [[ $vm_count -gt 1 ]]; then
            echo "Available VMs for console testing:"
            qm list | head -5
        fi
    else
        echo -e "${YELLOW}⚠ VM management API test failed${NC}"
    fi
    
    echo ""
}

# Function to show fix recommendations
show_fix_recommendations() {
    echo -e "${YELLOW}=== Fix Recommendations ===${NC}"
    
    echo "Based on the diagnosis, try these solutions in order:"
    echo ""
    
    echo "1. Critical Directory Issues:"
    echo "   - Check if /var/tmp exists: ls -la /var/tmp"
    echo "   - Recreate if missing: mkdir -p /var/tmp && chmod 1777 /var/tmp"
    echo "   - Restart services after fixing: systemctl restart pveproxy"
    echo ""
    
    echo "2. Service Issues:"
    echo "   - Restart Proxmox services (pveproxy, pvedaemon, pvestatd)"
    echo "   - Check service logs: journalctl -u pveproxy -f"
    echo ""
    
    echo "3. Disk Space Issues:"
    echo "   - Free up disk space on root filesystem"
    echo "   - Clean old log files and temporary data"
    echo "   - Use storage-cleanup.sh from this repository"
    echo ""
    
    echo "4. SSL Certificate Issues:"
    echo "   - Regenerate SSL certificates"
    echo "   - Check certificate expiration dates"
    echo ""
    
    echo "5. Permission Issues:"
    echo "   - Check /etc/pve directory permissions"
    echo "   - Verify SSL file ownership and permissions"
    echo "   - Ensure /var/tmp has 1777 permissions (sticky bit)"
    echo ""
    
    echo "6. Console-Specific Issues:"
    echo "   - Verify noVNC installation: apt install novnc"
    echo "   - Check firewall rules for port 8006"
    echo "   - Test with different browsers"
    echo ""
    
    echo "If console 500 errors persist after trying these fixes:"
    echo "- Check browser developer console for JavaScript errors"
    echo "- Try accessing console from different network/browser"
    echo "- Check Proxmox community forums for specific error messages"
    echo ""
}

# Function to run comprehensive diagnosis
run_comprehensive_diagnosis() {
    echo -e "${CYAN}=== Comprehensive Console Diagnosis ===${NC}"
    echo ""
    
    local issues_found=0
    
    display_system_overview
    
    if ! check_proxmox_services; then
        ((issues_found++))
    fi
    
    if ! check_disk_space; then
        ((issues_found++))
    fi
    
    if ! check_ssl_certificates; then
        ((issues_found++))
    fi
    
    if ! check_file_permissions; then
        ((issues_found++))
    fi
    
    if ! check_console_components; then
        ((issues_found++))
    fi
    
    check_recent_logs
    test_console_access
    
    echo ""
    if [[ $issues_found -eq 0 ]]; then
        echo -e "${GREEN}✓ No obvious issues found with Proxmox console components${NC}"
        echo "If you're still experiencing 500 errors, check the browser console"
        echo "and try accessing from a different browser or network."
    else
        echo -e "${YELLOW}⚠ Found $issues_found potential issues${NC}"
        echo "Use the automated fix options or follow the recommendations below."
    fi
    
    show_fix_recommendations
}

# Function to run automated fixes
run_automated_fixes() {
    echo -e "${CYAN}=== Automated Console Fixes ===${NC}"
    echo ""
    
    echo "This will attempt to fix common console issues automatically."
    echo "The following actions will be performed:"
    echo "1. Check and fix /var/tmp directory"
    echo "2. Restart Proxmox services"
    echo "3. Clean up disk space if needed"
    echo "4. Regenerate SSL certificates if corrupted"
    echo ""
    
    if confirm_action "Proceed with automated fixes"; then
        log_message "INFO" "Starting automated console fixes"
        
        # Fix 1: Check and fix /var/tmp directory
        echo -e "${YELLOW}Fix 1: Checking /var/tmp directory...${NC}"
        if [[ ! -d "/var/tmp" ]]; then
            echo "Creating missing /var/tmp directory..."
            mkdir -p /var/tmp
            chmod 1777 /var/tmp
            chown root:root /var/tmp
            echo -e "${GREEN}✓ Created /var/tmp with proper permissions${NC}"
            log_message "INFO" "Created missing /var/tmp directory"
        else
            local perms=$(stat -c "%a" /var/tmp 2>/dev/null)
            if [[ "$perms" != "1777" ]]; then
                echo "Fixing /var/tmp permissions..."
                chmod 1777 /var/tmp
                chown root:root /var/tmp
                echo -e "${GREEN}✓ Fixed /var/tmp permissions${NC}"
                log_message "INFO" "Fixed /var/tmp permissions from $perms to 1777"
            else
                echo -e "${GREEN}✓ /var/tmp directory exists with correct permissions${NC}"
            fi
        fi
        
        # Fix 2: Restart services
        echo -e "${YELLOW}Fix 2: Restarting Proxmox services...${NC}"
        systemctl restart pvestatd pvedaemon pveproxy
        sleep 5
        
        # Fix 3: Check and clean disk space if needed
        local root_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
        if [[ $root_usage -gt 85 ]]; then
            echo -e "${YELLOW}Fix 3: Cleaning disk space...${NC}"
            find /var/log -name "*.gz" -mtime +3 -delete 2>/dev/null
            journalctl --vacuum-time=2d 2>/dev/null
            apt clean 2>/dev/null
        fi
        
        # Fix 4: Test and regenerate certificates if needed
        if ! openssl x509 -in "/etc/pve/local/pve-ssl.pem" -noout -checkend 0 2>/dev/null; then
            echo -e "${YELLOW}Fix 4: Regenerating SSL certificates...${NC}"
            pvecm updatecerts --force 2>/dev/null
            systemctl restart pveproxy
        fi
        
        echo ""
        echo -e "${GREEN}Automated fixes completed${NC}"
        echo "Wait 30 seconds, then test console access again."
        
        log_message "INFO" "Automated console fixes completed"
    fi
}

# Interactive mode function
interactive_mode() {
    echo -e "${CYAN}=== Interactive Console Fix Mode ===${NC}"
    echo ""
    
    echo "What would you like to do?"
    echo "1. Run comprehensive diagnosis"
    echo "2. Check Proxmox services only"
    echo "3. Check disk space and cleanup"
    echo "4. Check and regenerate SSL certificates"
    echo "5. Restart Proxmox services"
    echo "6. Run automated fixes"
    echo "7. Test console access"
    echo "8. Show fix recommendations"
    echo "9. Exit"
    echo ""
    
    echo -n "Enter your choice (1-9): "
    read -r choice
    
    case "$choice" in
        1) run_comprehensive_diagnosis ;;
        2) check_proxmox_services ;;
        3) 
            check_disk_space
            echo ""
            cleanup_disk_space
            ;;
        4) 
            check_ssl_certificates
            echo ""
            regenerate_ssl_certificates
            ;;
        5) restart_proxmox_services ;;
        6) run_automated_fixes ;;
        7) test_console_access ;;
        8) show_fix_recommendations ;;
        9) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
    esac
}

# Main function
main() {
    echo -e "${CYAN}=== Proxmox Console Fix Script ===${NC}"
    echo ""
    
    # Check if running as root
    check_root
    
    # Check if this is a Proxmox system
    check_proxmox
    
    # Create log file and backup directory
    touch "$LOG_FILE"
    mkdir -p "$BACKUP_DIR"
    
    log_message "INFO" "Console fix script started"
    
    # Run based on command line argument
    case "${1:-interactive}" in
        "diagnose")
            run_comprehensive_diagnosis
            ;;
        "fix")
            run_automated_fixes
            ;;
        "services")
            check_proxmox_services
            if [[ $? -ne 0 ]]; then
                restart_proxmox_services
            fi
            ;;
        "interactive"|"")
            interactive_mode
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [diagnose|fix|services|interactive]"
            exit 1
            ;;
    esac
    
    log_message "INFO" "Console fix script completed"
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [mode]"
    echo ""
    echo "Proxmox Console Fix Script"
    echo "Diagnoses and fixes common Proxmox console 500 errors"
    echo ""
    echo "Modes:"
    echo "  (no args)     - Interactive mode with menu"
    echo "  diagnose      - Run comprehensive diagnosis only"
    echo "  fix           - Run automated fixes"
    echo "  services      - Check and restart Proxmox services"
    echo "  interactive   - Interactive mode with menu"
    echo ""
    echo "Common Console 500 Error Causes:"
    echo "  - Proxmox services not running (pveproxy, pvedaemon)"
    echo "  - Disk space issues (full root filesystem)"
    echo "  - SSL certificate problems (expired/corrupted)"
    echo "  - File permission issues"
    echo "  - noVNC component problems"
    echo ""
    echo "Examples:"
    echo "  $0                # Interactive mode"
    echo "  $0 diagnose       # Run diagnosis only"
    echo "  $0 fix            # Attempt automated fixes"
    echo "  $0 services       # Check/restart services"
    exit 0
fi

# Run main function
main "$@"
