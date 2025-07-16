#!/bin/bash

# Installation script for Proxmox Automation Tools
# This script downloads and sets up network fix, monitoring, and storage management tools

# Configuration
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log"
REPO_URL="https://raw.githubusercontent.com/TrueBankai416/Scripts/refs/heads/main/Proxmox"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_status "$RED" "Error: This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

# Function to check for script updates
check_for_updates() {
    local script_type="${1:-all}"
    local force_check="${2:-false}"
    
    print_status "$BLUE" "Checking for script updates..."
    
    local network_files=(
        "fix-network.sh"
        "network-monitor.sh"
        "network-fix.service"
    )
    
    local storage_files=(
        "storage-analyzer.sh"
        "storage-cleanup.sh"
        "storage-config-fix.sh"
    )
    
    local installer_files=(
        "install.sh"
    )
    
    local files=()
    case "$script_type" in
        "network")
            files=("${network_files[@]}" "${installer_files[@]}")
            ;;
        "storage")
            files=("${storage_files[@]}" "${installer_files[@]}")
            ;;
        "all"|*)
            files=("${network_files[@]}" "${storage_files[@]}" "${installer_files[@]}")
            ;;
    esac
    
    local existing_files=()
    local missing_files=()
    
    # Check which files exist locally
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            existing_files+=("$file")
        else
            missing_files+=("$file")
        fi
    done
    
    # If no files exist locally, proceed with normal download
    if [[ ${#existing_files[@]} -eq 0 ]]; then
        print_status "$YELLOW" "No existing files found, proceeding with download..."
        return 1  # Signal to proceed with download
    fi
    
    # If some files exist, check for updates
    if [[ ${#existing_files[@]} -gt 0 ]]; then
        print_status "$YELLOW" "Found existing files:"
        for file in "${existing_files[@]}"; do
            local size=$(stat -c%s "$file" 2>/dev/null || echo "unknown")
            local date=$(stat -c%y "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
            echo "  ✓ $file ($size bytes, $date)"
        done
        echo ""
        
        if [[ "$force_check" == "true" ]]; then
            print_status "$YELLOW" "Would you like to check for updates?"
            echo "1. Use existing files (faster)"
            echo "2. Check for updates from repository"
            echo "3. Cancel installation"
            echo ""
            echo -n "Enter your choice (1-3): "
            read -r choice
            
            case "$choice" in
                1)
                    print_status "$GREEN" "Using existing files"
                    return 0  # Signal to use existing files
                    ;;
                2)
                    print_status "$YELLOW" "Checking for updates..."
                    # Fall through to download check
                    ;;
                3)
                    print_status "$YELLOW" "Installation cancelled"
                    exit 0
                    ;;
                *)
                    print_status "$YELLOW" "Invalid choice, using existing files"
                    return 0
                    ;;
            esac
        fi
    fi
    
    # Check if remote files are different
    local updated_files=()
    local check_failed=()
    
    for file in "${existing_files[@]}"; do
        local base_file=$(basename "$file")
        local url="$REPO_URL/$base_file"
        local temp_file="${base_file}.tmp"
        
        print_status "$YELLOW" "Checking $base_file for updates..."
        
        # Download to temp file
        local http_code=$(curl -L -w "%{http_code}" -o "$temp_file" "$url" 2>/dev/null)
        
        if [[ "$http_code" == "200" && -f "$temp_file" && -s "$temp_file" ]]; then
            # Check if file contains actual content (not 404 page)
            # Look for GitHub's specific 404 error page structure
            if grep -q "<!DOCTYPE html>" "$temp_file" 2>/dev/null && grep -q "404.*Not Found" "$temp_file" 2>/dev/null; then
                print_status "$YELLOW" "  ⚠ $base_file not available in repository"
                rm -f "$temp_file"
                check_failed+=("$base_file")
            else
                # Compare files
                if ! diff -q "$file" "$temp_file" >/dev/null 2>&1; then
                    print_status "$GREEN" "  ✓ Update available for $base_file"
                    updated_files+=("$base_file")
                else
                    print_status "$GREEN" "  ✓ $base_file is up to date"
                fi
                rm -f "$temp_file"
            fi
        else
            print_status "$YELLOW" "  ⚠ Failed to check $base_file (HTTP: $http_code)"
            rm -f "$temp_file"
            check_failed+=("$base_file")
        fi
    done
    
    # Handle missing files
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_status "$YELLOW" "Missing files that will be downloaded:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
    fi
    
    # If updates or missing files found, ask user
    if [[ ${#updated_files[@]} -gt 0 || ${#missing_files[@]} -gt 0 ]]; then
        echo ""
        if [[ ${#updated_files[@]} -gt 0 ]]; then
            print_status "$YELLOW" "Updates available for: ${updated_files[*]}"
        fi
        if [[ ${#missing_files[@]} -gt 0 ]]; then
            print_status "$YELLOW" "Missing files: ${missing_files[*]}"
        fi
        echo ""
        echo "Would you like to:"
        echo "1. Download updates and missing files"
        echo "2. Use existing files (skip updates)"
        echo "3. Cancel installation"
        echo ""
        echo -n "Enter your choice (1-3): "
        read -r choice
        
        case "$choice" in
            1)
                print_status "$GREEN" "Downloading updates and missing files..."
                return 1  # Signal to proceed with download
                ;;
            2)
                print_status "$YELLOW" "Using existing files, skipping updates"
                return 0  # Signal to use existing files
                ;;
            3)
                print_status "$YELLOW" "Installation cancelled"
                exit 0
                ;;
            *)
                print_status "$YELLOW" "Invalid choice, using existing files"
                return 0
                ;;
        esac
    fi
    
    # All files are up to date
    print_status "$GREEN" "All files are up to date!"
    if [[ "$force_check" == "true" ]]; then
        echo ""
        print_status "$BLUE" "Update check summary:"
        echo "  ✓ Total files checked: ${#existing_files[@]}"
        echo "  ✓ Files up to date: ${#existing_files[@]}"
        echo "  ✓ Updates available: 0"
        echo "  ✓ Check failed: ${#check_failed[@]}"
        [[ ${#check_failed[@]} -gt 0 ]] && echo "  ⚠ Failed to check: ${check_failed[*]}"
    fi
    return 0  # Signal to use existing files
}

# Function to download required files from the repository
download_scripts() {
    local script_type="${1:-all}"  # all, network, storage
    
    print_status "$BLUE" "Downloading scripts from repository..."
    
    local network_files=(
        "fix-network.sh"
        "network-monitor.sh"
        "network-fix.service"
    )
    
    local storage_files=(
        "storage-analyzer.sh"
        "storage-cleanup.sh"
        "storage-config-fix.sh"
    )
    
    local files=()
    case "$script_type" in
        "network")
            files=("${network_files[@]}")
            print_status "$YELLOW" "Downloading network scripts only..."
            ;;
        "storage")
            files=("${storage_files[@]}")
            print_status "$YELLOW" "Downloading storage scripts only..."
            ;;
        "all"|*)
            files=("${network_files[@]}" "${storage_files[@]}")
            print_status "$YELLOW" "Downloading all scripts..."
            ;;
    esac
    
    local download_success=true
    local downloaded_files=()
    local failed_files=()
    local total_files=${#files[@]}
    local current_file=0
    
    for file in "${files[@]}"; do
        ((current_file++))
        local url="$REPO_URL/$file"
        print_status "$YELLOW" "[$current_file/$total_files] Downloading $file..."
        
        # Get file size for progress if possible
        local file_size=$(curl -sI "$url" 2>/dev/null | grep -i content-length | cut -d' ' -f2 | tr -d '\r')
        
        # Try to download with progress bar
        local http_code
        if [[ -n "$file_size" && "$file_size" -gt 0 ]]; then
            # Show progress bar for larger files
            http_code=$(curl -L -w "%{http_code}" -o "$file" "$url" --progress-bar 2>&1 | grep -o '[0-9]*$' | tail -1)
            # If grep didn't capture the http code, try again without progress bar
            if [[ -z "$http_code" ]]; then
                http_code=$(curl -L -w "%{http_code}" -o "$file" "$url" --progress-bar 2>/dev/null)
            fi
        else
            # Standard download for smaller files or when size unknown
            http_code=$(curl -L -w "%{http_code}" -o "$file" "$url" 2>/dev/null)
        fi
        
        if [[ "$http_code" == "200" && -f "$file" && -s "$file" ]]; then
            # Check if file contains actual content (not 404 page)
            # Look for GitHub's specific 404 error page structure
            if grep -q "<!DOCTYPE html>" "$file" 2>/dev/null && grep -q "404.*Not Found" "$file" 2>/dev/null; then
                print_status "$RED" "✗ $file not found (404 error)"
                rm -f "$file"
                failed_files+=("$file")
                download_success=false
            else
                local final_size=$(stat -c%s "$file" 2>/dev/null || echo "unknown")
                print_status "$GREEN" "✓ Downloaded $file successfully ($final_size bytes)"
                downloaded_files+=("$file")
            fi
        else
            print_status "$RED" "✗ Failed to download $file (HTTP: $http_code)"
            rm -f "$file"  # Remove empty or failed file
            failed_files+=("$file")
            download_success=false
        fi
    done
    
    echo ""
    if [[ "$download_success" == true ]]; then
        print_status "$GREEN" "All files downloaded successfully!"
        echo ""
        print_status "$BLUE" "Download Summary:"
        echo "  ✓ Total files: $total_files"
        echo "  ✓ Successfully downloaded: ${#downloaded_files[@]}"
        echo "  ✓ Files: ${downloaded_files[*]}"
        return 0
    else
        print_status "$RED" "Failed to download some files:"
        for file in "${failed_files[@]}"; do
            echo "  ✗ $file"
        done
        echo ""
        print_status "$BLUE" "Download Summary:"
        echo "  ✓ Total files: $total_files"
        echo "  ✓ Successfully downloaded: ${#downloaded_files[@]}"
        echo "  ✗ Failed downloads: ${#failed_files[@]}"
        echo ""
        print_status "$YELLOW" "Possible causes:"
        echo "  - Files not yet merged to main branch"
        echo "  - Network connectivity issues"
        echo "  - Repository structure changes"
        echo ""
        print_status "$YELLOW" "Solutions:"
        echo "  - Wait for PR to be merged to main branch"
        echo "  - Download files manually from the PR branch"
        echo "  - Check repository URL: $REPO_URL"
        echo "  - Use local files if you have them"
        return 1
    fi
}

# Function to install scripts
install_scripts() {
    local script_type="${1:-all}"  # all, network, storage
    
    print_status "$BLUE" "Installing Proxmox automation scripts..."
    
    local installed_count=0
    
    # Install network scripts
    if [[ "$script_type" == "all" || "$script_type" == "network" ]]; then
        if [[ -f "fix-network.sh" ]]; then
            cp fix-network.sh "$INSTALL_DIR/fix-network.sh"
            chmod +x "$INSTALL_DIR/fix-network.sh"
            ln -sf "$INSTALL_DIR/fix-network.sh" "$INSTALL_DIR/fix-network"
            ((installed_count++))
        fi
        
        if [[ -f "network-monitor.sh" ]]; then
            cp network-monitor.sh "$INSTALL_DIR/network-monitor.sh"
            chmod +x "$INSTALL_DIR/network-monitor.sh"
            ln -sf "$INSTALL_DIR/network-monitor.sh" "$INSTALL_DIR/network-monitor"
            ((installed_count++))
        fi
    fi
    
    # Install storage scripts
    if [[ "$script_type" == "all" || "$script_type" == "storage" ]]; then
        if [[ -f "storage-analyzer.sh" ]]; then
            cp storage-analyzer.sh "$INSTALL_DIR/storage-analyzer.sh"
            chmod +x "$INSTALL_DIR/storage-analyzer.sh"
            ln -sf "$INSTALL_DIR/storage-analyzer.sh" "$INSTALL_DIR/storage-analyzer"
            ((installed_count++))
        fi
        
        if [[ -f "storage-cleanup.sh" ]]; then
            cp storage-cleanup.sh "$INSTALL_DIR/storage-cleanup.sh"
            chmod +x "$INSTALL_DIR/storage-cleanup.sh"
            ln -sf "$INSTALL_DIR/storage-cleanup.sh" "$INSTALL_DIR/storage-cleanup"
            ((installed_count++))
        fi
        
        if [[ -f "storage-config-fix.sh" ]]; then
            cp storage-config-fix.sh "$INSTALL_DIR/storage-config-fix.sh"
            chmod +x "$INSTALL_DIR/storage-config-fix.sh"
            ln -sf "$INSTALL_DIR/storage-config-fix.sh" "$INSTALL_DIR/storage-config-fix"
            ((installed_count++))
        fi
    fi
    
    if [[ $installed_count -eq 0 ]]; then
        print_status "$RED" "No scripts were installed - no valid files found!"
        return 1
    fi
    
    print_status "$GREEN" "Scripts installed successfully! ($installed_count files)"
    
    # Show what was installed
    echo "  Installed scripts:"
    [[ -f "$INSTALL_DIR/fix-network.sh" ]] && echo "    ✓ fix-network.sh -> $INSTALL_DIR/fix-network.sh"
    [[ -f "$INSTALL_DIR/network-monitor.sh" ]] && echo "    ✓ network-monitor.sh -> $INSTALL_DIR/network-monitor.sh"
    [[ -f "$INSTALL_DIR/storage-analyzer.sh" ]] && echo "    ✓ storage-analyzer.sh -> $INSTALL_DIR/storage-analyzer.sh"
    [[ -f "$INSTALL_DIR/storage-cleanup.sh" ]] && echo "    ✓ storage-cleanup.sh -> $INSTALL_DIR/storage-cleanup.sh"
    [[ -f "$INSTALL_DIR/storage-config-fix.sh" ]] && echo "    ✓ storage-config-fix.sh -> $INSTALL_DIR/storage-config-fix.sh"
    echo "  Symlinks created for all installed scripts"
}

# Function to install systemd service
install_service() {
    print_status "$BLUE" "Installing systemd service..."
    
    # Only install service if network monitoring is being installed
    if [[ -f "network-fix.service" ]]; then
        cp network-fix.service "$SERVICE_DIR/network-fix.service"
        
        # Reload systemd
        systemctl daemon-reload
        
        print_status "$GREEN" "Systemd service installed successfully!"
        echo "  - Service file: $SERVICE_DIR/network-fix.service"
    else
        print_status "$YELLOW" "Skipping systemd service installation (network-fix.service not found)"
    fi
}

# Function to setup logging
setup_logging() {
    local script_type="${1:-all}"
    
    print_status "$BLUE" "Setting up logging..."
    
    local log_files_created=()
    
    # Create network log files
    if [[ "$script_type" == "all" || "$script_type" == "network" ]]; then
        if [[ -f "$INSTALL_DIR/fix-network.sh" ]]; then
            touch "$LOG_DIR/network-fix.log"
            chmod 644 "$LOG_DIR/network-fix.log"
            log_files_created+=("$LOG_DIR/network-fix.log")
        fi
        
        if [[ -f "$INSTALL_DIR/network-monitor.sh" ]]; then
            touch "$LOG_DIR/network-monitor.log"
            chmod 644 "$LOG_DIR/network-monitor.log"
            log_files_created+=("$LOG_DIR/network-monitor.log")
        fi
    fi
    
    # Create storage log files
    if [[ "$script_type" == "all" || "$script_type" == "storage" ]]; then
        if [[ -f "$INSTALL_DIR/storage-analyzer.sh" ]]; then
            touch "$LOG_DIR/storage-analyzer.log"
            chmod 644 "$LOG_DIR/storage-analyzer.log"
            log_files_created+=("$LOG_DIR/storage-analyzer.log")
        fi
        
        if [[ -f "$INSTALL_DIR/storage-cleanup.sh" ]]; then
            touch "$LOG_DIR/storage-cleanup.log"
            chmod 644 "$LOG_DIR/storage-cleanup.log"
            log_files_created+=("$LOG_DIR/storage-cleanup.log")
        fi
        
        if [[ -f "$INSTALL_DIR/storage-config-fix.sh" ]]; then
            touch "$LOG_DIR/storage-config-fix.log"
            chmod 644 "$LOG_DIR/storage-config-fix.log"
            log_files_created+=("$LOG_DIR/storage-config-fix.log")
        fi
    fi
    
    print_status "$GREEN" "Logging setup complete!"
    echo "  Created log files:"
    for log in "${log_files_created[@]}"; do
        echo "    ✓ $log"
    done
}

# Function to setup automation
setup_automation() {
    print_status "$BLUE" "=== Setup Network Monitoring Automation ==="
    echo ""
    echo "Would you like to setup automatic network monitoring? (y/N)"
    read -r setup_auto
    
    if [[ "$setup_auto" =~ ^[Yy]$ ]]; then
        echo ""
        print_status "$YELLOW" "Choose monitoring method:"
        echo "1. Systemd Service (recommended - continuous monitoring)"
        echo "2. Cron Job (periodic checks every 5 minutes)"
        echo "3. Skip automation setup"
        echo ""
        echo -n "Enter your choice (1-3): "
        read -r choice
        
        case "$choice" in
            1)
                setup_systemd_monitoring
                ;;
            2)
                setup_cron_monitoring
                ;;
            3)
                print_status "$YELLOW" "Automation setup skipped. You can set it up later."
                ;;
            *)
                print_status "$YELLOW" "Invalid choice. Automation setup skipped."
                ;;
        esac
    else
        print_status "$YELLOW" "Automation setup skipped."
    fi
}

# Function to setup systemd monitoring
setup_systemd_monitoring() {
    print_status "$BLUE" "Setting up systemd service monitoring..."
    
    if systemctl enable network-fix.service 2>/dev/null; then
        print_status "$GREEN" "✓ Service enabled successfully"
        
        if systemctl start network-fix.service 2>/dev/null; then
            print_status "$GREEN" "✓ Service started successfully"
            
            # Give service a moment to start
            sleep 2
            
            if systemctl is-active network-fix.service >/dev/null 2>&1; then
                print_status "$GREEN" "✓ Service is running"
                echo ""
                print_status "$BLUE" "Monitoring service commands:"
                echo "  View status: sudo systemctl status network-fix.service"
                echo "  View logs:   sudo journalctl -u network-fix.service -f"
                echo "  Stop:        sudo systemctl stop network-fix.service"
                echo "  Disable:     sudo systemctl disable network-fix.service"
            else
                print_status "$YELLOW" "⚠ Service started but may not be running properly"
                echo "  Check status: sudo systemctl status network-fix.service"
            fi
        else
            print_status "$RED" "✗ Failed to start service"
            echo "  Check logs: sudo journalctl -u network-fix.service"
        fi
    else
        print_status "$RED" "✗ Failed to enable service"
    fi
}

# Function to setup cron monitoring
setup_cron_monitoring() {
    print_status "$BLUE" "Setting up cron job monitoring..."
    
    local cron_line="*/5 * * * * /usr/local/bin/network-monitor check >/dev/null 2>&1"
    local temp_cron="/tmp/crontab.tmp"
    
    # Get current crontab
    if crontab -l >/dev/null 2>&1; then
        crontab -l > "$temp_cron"
        
        # Check if our cron job already exists
        if grep -q "network-monitor check" "$temp_cron"; then
            print_status "$YELLOW" "⚠ Cron job already exists. Not adding duplicate."
            rm -f "$temp_cron"
            return
        fi
    else
        # No existing crontab, create empty one
        touch "$temp_cron"
    fi
    
    # Add our cron job
    echo "$cron_line" >> "$temp_cron"
    
    # Install the new crontab
    if crontab "$temp_cron" 2>/dev/null; then
        print_status "$GREEN" "✓ Cron job added successfully"
        echo ""
        print_status "$BLUE" "Cron job details:"
        echo "  Schedule: Every 5 minutes"
        echo "  Command:  $cron_line"
        echo ""
        print_status "$BLUE" "Cron management commands:"
        echo "  View cron jobs: sudo crontab -l"
        echo "  Edit cron jobs: sudo crontab -e"
        echo "  View logs:      sudo tail -f /var/log/network-monitor.log"
    else
        print_status "$RED" "✗ Failed to add cron job"
        echo "  You can manually add this line to crontab:"
        echo "  $cron_line"
    fi
    
    # Clean up
    rm -f "$temp_cron"
}

# Function to show usage options
show_usage_options() {
    local script_type="${1:-all}"
    
    print_status "$BLUE" "=== Installation Complete! ==="
    echo ""
    
    if [[ "$script_type" == "all" || "$script_type" == "network" ]]; then
        if [[ -x "$INSTALL_DIR/fix-network.sh" ]]; then
            print_status "$YELLOW" "Network Tools Usage:"
            echo "  sudo fix-network            # Auto-detect interface"
            echo "  sudo fix-network eth0       # Specific interface"
            echo "  sudo network-monitor check  # Single connectivity check"
            echo "  network-monitor status      # View recent logs"
            echo ""
        fi
    fi
    
    if [[ "$script_type" == "all" || "$script_type" == "storage" ]]; then
        if [[ -x "$INSTALL_DIR/storage-analyzer.sh" ]]; then
            print_status "$YELLOW" "Storage Tools Usage:"
            echo "  sudo storage-analyzer       # Analyze storage usage"
            echo "  sudo storage-cleanup        # Interactive cleanup"
            echo "  sudo storage-cleanup all    # Auto cleanup all categories"
            echo "  sudo storage-config-fix     # Fix storage configuration issues"
            echo ""
        fi
    fi
    
    print_status "$YELLOW" "View Logs:"
    [[ -f "$LOG_DIR/network-fix.log" ]] && echo "  sudo tail -f /var/log/network-fix.log"
    [[ -f "$LOG_DIR/network-monitor.log" ]] && echo "  sudo tail -f /var/log/network-monitor.log"
    [[ -f "$LOG_DIR/storage-analyzer.log" ]] && echo "  sudo tail -f /var/log/storage-analyzer.log"
    [[ -f "$LOG_DIR/storage-cleanup.log" ]] && echo "  sudo tail -f /var/log/storage-cleanup.log"
    [[ -f "$LOG_DIR/storage-config-fix.log" ]] && echo "  sudo tail -f /var/log/storage-config-fix.log"
    echo ""
    print_status "$GREEN" "For more information, see README.md"
}

# Function to test installation
test_installation() {
    local script_type="${1:-all}"
    
    print_status "$BLUE" "Testing installation..."
    
    local tests_passed=0
    local tests_total=0
    
    # Test network scripts
    if [[ "$script_type" == "all" || "$script_type" == "network" ]]; then
        ((tests_total++))
        if [[ -x "$INSTALL_DIR/fix-network.sh" ]]; then
            print_status "$GREEN" "✓ fix-network.sh is executable"
            ((tests_passed++))
        else
            print_status "$YELLOW" "⚠ fix-network.sh is not executable (may not be installed)"
        fi
        
        ((tests_total++))
        if [[ -x "$INSTALL_DIR/network-monitor.sh" ]]; then
            print_status "$GREEN" "✓ network-monitor.sh is executable"
            ((tests_passed++))
        else
            print_status "$YELLOW" "⚠ network-monitor.sh is not executable (may not be installed)"
        fi
        
        # Test help commands for network scripts
        if [[ -x "$INSTALL_DIR/fix-network.sh" ]]; then
            ((tests_total++))
            if "$INSTALL_DIR/fix-network.sh" --help &>/dev/null; then
                print_status "$GREEN" "✓ fix-network help works"
                ((tests_passed++))
            else
                print_status "$RED" "✗ fix-network help failed"
            fi
        fi
        
        if [[ -x "$INSTALL_DIR/network-monitor.sh" ]]; then
            ((tests_total++))
            if "$INSTALL_DIR/network-monitor.sh" help &>/dev/null; then
                print_status "$GREEN" "✓ network-monitor help works"
                ((tests_passed++))
            else
                print_status "$RED" "✗ network-monitor help failed"
            fi
        fi
        
        # Test service file
        ((tests_total++))
        if [[ -f "$SERVICE_DIR/network-fix.service" ]]; then
            print_status "$GREEN" "✓ systemd service file installed"
            ((tests_passed++))
        else
            print_status "$YELLOW" "⚠ systemd service file not found (may not be installed)"
        fi
    fi
    
    # Test storage scripts
    if [[ "$script_type" == "all" || "$script_type" == "storage" ]]; then
        ((tests_total++))
        if [[ -x "$INSTALL_DIR/storage-analyzer.sh" ]]; then
            print_status "$GREEN" "✓ storage-analyzer.sh is executable"
            ((tests_passed++))
        else
            print_status "$YELLOW" "⚠ storage-analyzer.sh is not executable (may not be installed)"
        fi
        
        ((tests_total++))
        if [[ -x "$INSTALL_DIR/storage-cleanup.sh" ]]; then
            print_status "$GREEN" "✓ storage-cleanup.sh is executable"
            ((tests_passed++))
        else
            print_status "$YELLOW" "⚠ storage-cleanup.sh is not executable (may not be installed)"
        fi
        
        ((tests_total++))
        if [[ -x "$INSTALL_DIR/storage-config-fix.sh" ]]; then
            print_status "$GREEN" "✓ storage-config-fix.sh is executable"
            ((tests_passed++))
        else
            print_status "$YELLOW" "⚠ storage-config-fix.sh is not executable (may not be installed)"
        fi
        
        # Test help commands for storage scripts
        if [[ -x "$INSTALL_DIR/storage-analyzer.sh" ]]; then
            ((tests_total++))
            if "$INSTALL_DIR/storage-analyzer.sh" --help &>/dev/null; then
                print_status "$GREEN" "✓ storage-analyzer help works"
                ((tests_passed++))
            else
                print_status "$RED" "✗ storage-analyzer help failed"
            fi
        fi
        
        if [[ -x "$INSTALL_DIR/storage-cleanup.sh" ]]; then
            ((tests_total++))
            if "$INSTALL_DIR/storage-cleanup.sh" --help &>/dev/null; then
                print_status "$GREEN" "✓ storage-cleanup help works"
                ((tests_passed++))
            else
                print_status "$RED" "✗ storage-cleanup help failed"
            fi
        fi
        
        if [[ -x "$INSTALL_DIR/storage-config-fix.sh" ]]; then
            ((tests_total++))
            if "$INSTALL_DIR/storage-config-fix.sh" --help &>/dev/null; then
                print_status "$GREEN" "✓ storage-config-fix help works"
                ((tests_passed++))
            else
                print_status "$RED" "✗ storage-config-fix help failed"
            fi
        fi
    fi
    
    echo ""
    print_status "$BLUE" "Test Summary: $tests_passed/$tests_total tests passed"
    
    if [[ $tests_passed -eq $tests_total ]]; then
        print_status "$GREEN" "✓ All tests passed!"
        return 0
    else
        print_status "$YELLOW" "⚠ Some tests failed or components not installed"
        return 1
    fi
}

# Main installation function
main() {
    local script_type="${1:-all}"  # all, network, storage
    
    print_status "$BLUE" "=== Proxmox Automation Tools Installation ==="
    echo ""
    
    # Check if running as root
    check_root
    
    # Define files needed based on script type
    local network_files=("fix-network.sh" "network-monitor.sh" "network-fix.service")
    local storage_files=("storage-analyzer.sh" "storage-cleanup.sh")
    local required_files=()
    
    case "$script_type" in
        "network")
            required_files=("${network_files[@]}")
            print_status "$YELLOW" "Installing network tools only..."
            ;;
        "storage")
            required_files=("${storage_files[@]}")
            print_status "$YELLOW" "Installing storage tools only..."
            ;;
        "all"|*)
            required_files=("${network_files[@]}" "${storage_files[@]}")
            print_status "$YELLOW" "Installing all tools..."
            ;;
    esac
    
    # Check if required files exist
    local missing_files=()
    for file in "${required_files[@]}"; do
        [[ ! -f "$file" ]] && missing_files+=("$file")
    done
    
    # Check for updates or missing files
    print_status "$BLUE" "Checking for script updates..."
    if ! check_for_updates "$script_type" "true"; then
        # check_for_updates returned 1, meaning we should download
        if [[ ${#missing_files[@]} -gt 0 ]]; then
            print_status "$YELLOW" "Missing required files, attempting to download from repository..."
            printf ' - %s\n' "${missing_files[@]}"
            echo ""
        fi
        
        # Attempt to download missing files
        if ! download_scripts "$script_type"; then
            print_status "$RED" "Failed to download required files."
            print_status "$YELLOW" "Please manually download the files or run this script from the directory containing all the files."
            exit 1
        fi
        
        # Verify files were downloaded
        local still_missing=()
        for file in "${required_files[@]}"; do
            [[ ! -f "$file" ]] && still_missing+=("$file")
        done
        
        if [[ ${#still_missing[@]} -gt 0 ]]; then
            print_status "$RED" "Error: Still missing files after download attempt:"
            printf ' - %s\n' "${still_missing[@]}"
            exit 1
        fi
    else
        print_status "$GREEN" "✓ Update check completed - using existing files"
    fi
    
    # Perform installation
    install_scripts "$script_type"
    install_service
    setup_logging "$script_type"
    
    # Test installation
    if test_installation "$script_type"; then
        show_usage_options "$script_type"
        if [[ "$script_type" == "all" || "$script_type" == "network" ]]; then
            setup_automation
        fi
        exit 0
    else
        print_status "$RED" "Installation completed but tests failed. Please check the output above."
        exit 1
    fi
}

# Function for interactive mode
interactive_mode() {
    print_status "$BLUE" "=== Proxmox Automation Tools Setup ==="
    
    # Auto-check for updates when script starts
    auto_check_updates
    
    echo ""
    print_status "$YELLOW" "What would you like to do?"
    echo "1. Download and install all Proxmox tools (network + storage)"
    echo "2. Download and install network tools only"
    echo "3. Download and install storage tools only"
    echo "4. Download scripts only (no installation)"
    echo "5. Check for script updates"
    echo "6. Uninstall Proxmox tools"
    echo "7. Test current installation"
    echo "8. Exit"
    echo ""
    echo -n "Enter your choice (1-8): "
    read -r choice
    
    case "$choice" in
        1)
            echo ""
            main "all"
            ;;
        2)
            echo ""
            main "network"
            ;;
        3)
            echo ""
            main "storage"
            ;;
        4)
            echo ""
            select_download_type
            ;;
        5)
            echo ""
            manual_update_check
            ;;
        6)
            echo ""
            uninstall_tools "interactive"
            ;;
        7)
            echo ""
            check_root
            test_installation
            ;;
        8)
            print_status "$YELLOW" "Exiting..."
            exit 0
            ;;
        *)
            print_status "$RED" "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
}

# Function to select download type
select_download_type() {
    print_status "$BLUE" "=== Download Scripts Only ==="
    echo ""
    print_status "$YELLOW" "What would you like to download?"
    echo "1. All scripts (network + storage)"
    echo "2. Network scripts only"
    echo "3. Storage scripts only"
    echo "4. Back to main menu"
    echo ""
    echo -n "Enter your choice (1-4): "
    read -r choice
    
    case "$choice" in
        1)
            echo ""
            print_status "$BLUE" "Downloading all Proxmox tools..."
            if download_scripts "all"; then
                print_status "$GREEN" "Download completed successfully!"
                print_status "$YELLOW" "Run '$0 install' to install the downloaded scripts."
            else
                print_status "$RED" "Download failed!"
                exit 1
            fi
            ;;
        2)
            echo ""
            print_status "$BLUE" "Downloading network tools..."
            if download_scripts "network"; then
                print_status "$GREEN" "Download completed successfully!"
                print_status "$YELLOW" "Run '$0 install-network' to install the downloaded scripts."
            else
                print_status "$RED" "Download failed!"
                exit 1
            fi
            ;;
        3)
            echo ""
            print_status "$BLUE" "Downloading storage tools..."
            if download_scripts "storage"; then
                print_status "$GREEN" "Download completed successfully!"
                print_status "$YELLOW" "Run '$0 install-storage' to install the downloaded scripts."
            else
                print_status "$RED" "Download failed!"
                exit 1
            fi
            ;;
        4)
            interactive_mode
            ;;
        *)
            print_status "$RED" "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
}

# Function to handle uninstall
uninstall_tools() {
    local script_type="${1:-interactive}"
    
    if [[ "$script_type" == "interactive" ]]; then
        select_uninstall_type
        return
    fi
    
    print_status "$BLUE" "Uninstalling Proxmox Automation Tools..."
    
    local removed_files=()
    
    # Stop and disable service for network tools
    if [[ "$script_type" == "all" || "$script_type" == "network" ]]; then
        systemctl stop network-fix.service 2>/dev/null
        systemctl disable network-fix.service 2>/dev/null
    fi
    
    # Remove network files
    if [[ "$script_type" == "all" || "$script_type" == "network" ]]; then
        [[ -f "$INSTALL_DIR/fix-network.sh" ]] && rm -f "$INSTALL_DIR/fix-network.sh" && removed_files+=("fix-network.sh")
        [[ -f "$INSTALL_DIR/network-monitor.sh" ]] && rm -f "$INSTALL_DIR/network-monitor.sh" && removed_files+=("network-monitor.sh")
        [[ -f "$INSTALL_DIR/fix-network" ]] && rm -f "$INSTALL_DIR/fix-network"
        [[ -f "$INSTALL_DIR/network-monitor" ]] && rm -f "$INSTALL_DIR/network-monitor"
        [[ -f "$SERVICE_DIR/network-fix.service" ]] && rm -f "$SERVICE_DIR/network-fix.service" && removed_files+=("network-fix.service")
        
        # Remove ethtool workaround services
        rm -f "$SERVICE_DIR/ethtool-workaround-"*.service 2>/dev/null
        
        # Remove cron job if it exists
        if crontab -l 2>/dev/null | grep -q "network-monitor check"; then
            print_status "$YELLOW" "Removing cron job..."
            local temp_cron="/tmp/crontab.tmp"
            crontab -l | grep -v "network-monitor check" > "$temp_cron"
            crontab "$temp_cron" 2>/dev/null
            rm -f "$temp_cron"
            print_status "$GREEN" "✓ Cron job removed"
        fi
    fi
    
    # Remove storage files
    if [[ "$script_type" == "all" || "$script_type" == "storage" ]]; then
        [[ -f "$INSTALL_DIR/storage-analyzer.sh" ]] && rm -f "$INSTALL_DIR/storage-analyzer.sh" && removed_files+=("storage-analyzer.sh")
        [[ -f "$INSTALL_DIR/storage-cleanup.sh" ]] && rm -f "$INSTALL_DIR/storage-cleanup.sh" && removed_files+=("storage-cleanup.sh")
        [[ -f "$INSTALL_DIR/storage-analyzer" ]] && rm -f "$INSTALL_DIR/storage-analyzer"
        [[ -f "$INSTALL_DIR/storage-cleanup" ]] && rm -f "$INSTALL_DIR/storage-cleanup"
        [[ -f "$INSTALL_DIR/storage-config-fix.sh" ]] && rm -f "$INSTALL_DIR/storage-config-fix.sh" && removed_files+=("storage-config-fix.sh")
        [[ -f "$INSTALL_DIR/storage-config-fix" ]] && rm -f "$INSTALL_DIR/storage-config-fix"
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    if [[ ${#removed_files[@]} -gt 0 ]]; then
        print_status "$GREEN" "Uninstallation complete!"
        echo "Removed files:"
        for file in "${removed_files[@]}"; do
            echo "  ✓ $file"
        done
    else
        print_status "$YELLOW" "No files found to remove for $script_type tools"
    fi
    
    echo ""
    print_status "$YELLOW" "Log files remain at:"
    [[ -f "$LOG_DIR/network-fix.log" ]] && echo "  - $LOG_DIR/network-fix.log"
    [[ -f "$LOG_DIR/network-monitor.log" ]] && echo "  - $LOG_DIR/network-monitor.log"
    [[ -f "$LOG_DIR/storage-analyzer.log" ]] && echo "  - $LOG_DIR/storage-analyzer.log"
    [[ -f "$LOG_DIR/storage-cleanup.log" ]] && echo "  - $LOG_DIR/storage-cleanup.log"
    [[ -f "$LOG_DIR/storage-config-fix.log" ]] && echo "  - $LOG_DIR/storage-config-fix.log"
}

# Function to select uninstall type
select_uninstall_type() {
    print_status "$BLUE" "=== Selective Uninstall ==="
    echo ""
    print_status "$YELLOW" "What would you like to uninstall?"
    echo "1. All tools (network + storage)"
    echo "2. Network tools only"
    echo "3. Storage tools only"
    echo "4. Back to main menu"
    echo ""
    echo -n "Enter your choice (1-4): "
    read -r choice
    
    case "$choice" in
        1)
            echo ""
            uninstall_tools "all"
            ;;
        2)
            echo ""
            uninstall_tools "network"
            ;;
        3)
            echo ""
            uninstall_tools "storage"
            ;;
        4)
            interactive_mode
            ;;
        *)
            print_status "$RED" "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
}

# Function for manual update checking
manual_update_check() {
    print_status "$BLUE" "=== Manual Update Check ==="
    echo ""
    
    # Check what's currently installed
    local installed_network=false
    local installed_storage=false
    
    [[ -f "$INSTALL_DIR/fix-network.sh" ]] && installed_network=true
    [[ -f "$INSTALL_DIR/storage-analyzer.sh" ]] && installed_storage=true
    
    if [[ "$installed_network" == false && "$installed_storage" == false ]]; then
        print_status "$YELLOW" "No Proxmox tools are currently installed."
        echo "Would you like to install some tools instead?"
        echo "1. Yes, go to installation menu"
        echo "2. No, check for updates in current directory"
        echo "3. Back to main menu"
        echo ""
        echo -n "Enter your choice (1-3): "
        read -r choice
        
        case "$choice" in
            1)
                interactive_mode
                ;;
            2)
                print_status "$YELLOW" "Checking for updates in current directory..."
                ;;
            3)
                interactive_mode
                ;;
            *)
                print_status "$RED" "Invalid choice"
                interactive_mode
                ;;
        esac
    else
        print_status "$YELLOW" "Currently installed tools:"
        [[ "$installed_network" == true ]] && echo "  ✓ Network tools"
        [[ "$installed_storage" == true ]] && echo "  ✓ Storage tools"
        echo ""
    fi
    
    # Determine what to check based on what's installed
    local check_type="all"
    if [[ "$installed_network" == true && "$installed_storage" == false ]]; then
        check_type="network"
    elif [[ "$installed_network" == false && "$installed_storage" == true ]]; then
        check_type="storage"
    fi
    
    print_status "$YELLOW" "What would you like to check for updates?"
    echo "1. All available scripts (including installer)"
    echo "2. Network scripts only (including installer)"
    echo "3. Storage scripts only (including installer)"
    echo "4. Back to main menu"
    echo ""
    echo -n "Enter your choice (1-4): "
    read -r choice
    
    case "$choice" in
        1)
            check_type="all"
            ;;
        2)
            check_type="network"
            ;;
        3)
            check_type="storage"
            ;;
        4)
            interactive_mode
            ;;
        *)
            print_status "$RED" "Invalid choice"
            interactive_mode
            ;;
    esac
    
    echo ""
    print_status "$BLUE" "Checking for updates for $check_type scripts..."
    
    # Run update check
    if check_for_updates "$check_type" "true"; then
        print_status "$GREEN" "All checked scripts are up to date!"
    else
        print_status "$YELLOW" "Updates or new scripts were available, downloading now..."
        echo ""
        
        # Actually download the scripts
        if download_scripts "$check_type"; then
            print_status "$GREEN" "Download completed successfully!"
        else
            print_status "$RED" "Download failed!"
        fi
    fi
    
    echo ""
    echo "Press Enter to return to main menu..."
    read -r
    interactive_mode
}

# Function to auto-check for updates (silent, quick check)
auto_check_updates() {
    # Check what's currently installed
    local installed_network=false
    local installed_storage=false
    
    [[ -f "$INSTALL_DIR/fix-network.sh" ]] && installed_network=true
    [[ -f "$INSTALL_DIR/storage-analyzer.sh" ]] && installed_storage=true
    
    # If nothing is installed, skip auto-check
    if [[ "$installed_network" == false && "$installed_storage" == false ]]; then
        return
    fi
    
    # Define all available scripts
    local network_files=("fix-network.sh" "network-monitor.sh" "network-fix.service")
    local storage_files=("storage-analyzer.sh" "storage-cleanup.sh" "storage-config-fix.sh")
    local installer_files=("install.sh")
    
    # Check what's installed and what's available
    local installed_files=()
    local missing_files=()
    local updated_files=()
    
    # Check network files
    if [[ "$installed_network" == true ]]; then
        for file in "${network_files[@]}"; do
            local installed_file=""
            case "$file" in
                "fix-network.sh")
                    installed_file="$INSTALL_DIR/fix-network.sh"
                    ;;
                "network-monitor.sh")
                    installed_file="$INSTALL_DIR/network-monitor.sh"
                    ;;
                "network-fix.service")
                    # Service file is in current directory or service dir
                    if [[ -f "$file" ]]; then
                        installed_file="$file"
                    elif [[ -f "$SERVICE_DIR/network-fix.service" ]]; then
                        installed_file="$SERVICE_DIR/network-fix.service"
                    fi
                    ;;
            esac
            
            if [[ -n "$installed_file" && -f "$installed_file" ]]; then
                installed_files+=("$installed_file")
            else
                missing_files+=("$file")
            fi
        done
    fi
    
    # Check storage files
    if [[ "$installed_storage" == true ]]; then
        for file in "${storage_files[@]}"; do
            local installed_file=""
            case "$file" in
                "storage-analyzer.sh")
                    installed_file="$INSTALL_DIR/storage-analyzer.sh"
                    ;;
                "storage-cleanup.sh")
                    installed_file="$INSTALL_DIR/storage-cleanup.sh"
                    ;;
                "storage-config-fix.sh")
                    installed_file="$INSTALL_DIR/storage-config-fix.sh"
                    ;;
            esac
            
            if [[ -n "$installed_file" && -f "$installed_file" ]]; then
                installed_files+=("$installed_file")
            else
                missing_files+=("$file")
            fi
        done
    fi
    
    # Check installer
    if [[ "$0" == "$INSTALL_DIR/install.sh" ]]; then
        installed_files+=("$INSTALL_DIR/install.sh")
    elif [[ -f "install.sh" ]]; then
        installed_files+=("install.sh")
    fi
    
    # Quick check for updates to existing files (silent)
    for installed_file in "${installed_files[@]}"; do
        # Get the base filename for URL
        local base_file=$(basename "$installed_file")
        local url="$REPO_URL/$base_file"
        local temp_file="${base_file}.tmp"
        
        # Download to temp file silently
        local http_code=$(curl -s -L -w "%{http_code}" -o "$temp_file" "$url" 2>/dev/null)
        
        if [[ "$http_code" == "200" && -f "$temp_file" && -s "$temp_file" ]]; then
            # Check if file contains actual content (not 404 page)
            # Look for GitHub's specific 404 error page structure
            if ! (grep -q "<!DOCTYPE html>" "$temp_file" 2>/dev/null && grep -q "404.*Not Found" "$temp_file" 2>/dev/null); then
                # Compare files
                if ! diff -q "$installed_file" "$temp_file" >/dev/null 2>&1; then
                    updated_files+=("$base_file")
                fi
            fi
        fi
        rm -f "$temp_file"
    done
    
    # Display status
    echo ""
    if [[ ${#updated_files[@]} -gt 0 && ${#missing_files[@]} -gt 0 ]]; then
        print_status "$YELLOW" "⚠ Updates available for: ${updated_files[*]}"
        print_status "$YELLOW" "⚠ New scripts available: ${missing_files[*]}"
        echo "   Use option 5 to check and download updates"
    elif [[ ${#updated_files[@]} -gt 0 ]]; then
        print_status "$YELLOW" "⚠ Updates available for: ${updated_files[*]}"
        echo "   Use option 5 to check and download updates"
    elif [[ ${#missing_files[@]} -gt 0 ]]; then
        print_status "$YELLOW" "⚠ New scripts available: ${missing_files[*]}"
        echo "   Use option 5 to check and download new scripts"
    else
        print_status "$GREEN" "✓ All installed scripts are up to date"
    fi
}

# Handle command line arguments
case "${1:-interactive}" in
    "install"|"1")
        main "all"
        ;;
    "install-network")
        main "network"
        ;;
    "install-storage")
        main "storage"
        ;;
    "download"|"2")
        select_download_type
        ;;
    "uninstall"|"3")
        check_root
        uninstall_tools "interactive"
        ;;
    "test"|"4")
        check_root
        test_installation
        ;;
    "check-updates"|"update-check")
        manual_update_check
        ;;
    "interactive"|"")
        interactive_mode
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)        - Interactive mode with menu options"
        echo "  install          - Download and install all Proxmox tools"
        echo "  install-network  - Download and install network tools only"
        echo "  install-storage  - Download and install storage tools only"
        echo "  download         - Download scripts from repository only"
        echo "  uninstall        - Remove all Proxmox tools"
        echo "  test             - Test installation"
        echo "  check-updates    - Check for script updates"
        echo "  help             - Show this help message"
        echo ""
        echo "Interactive Options:"
        echo "  1. Download and install all Proxmox tools (network + storage)"
        echo "  2. Download and install network tools only"
        echo "  3. Download and install storage tools only"
        echo "  4. Download scripts only (no installation)"
        echo "  5. Check for script updates"
        echo "  6. Uninstall Proxmox tools"
        echo "  7. Test current installation"
        echo "  8. Exit"
        echo ""
        echo "Repository: https://github.com/TrueBankai416/Scripts"
        echo "Script location: $REPO_URL"
        ;;
    *)
        print_status "$RED" "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
