#!/bin/bash

# Installation script for Proxmox Network Fix Tools
# This script downloads and sets up the network fix and monitoring tools

# Configuration
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log"
REPO_URL="https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Proxmox/Networking/NIC%20Fix"

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

# Function to download required files from the Scripts repository
download_scripts() {
    print_status "$BLUE" "Downloading scripts from repository..."
    
    local files=(
        "fix-network.sh"
        "network-monitor.sh"
        "network-fix.service"
    )
    
    local download_success=true
    
    for file in "${files[@]}"; do
        local url="$REPO_URL/$file"
        print_status "$YELLOW" "Downloading $file..."
        
        if curl -L -o "$file" "$url" 2>/dev/null; then
            print_status "$GREEN" "✓ Downloaded $file successfully"
        else
            print_status "$RED" "✗ Failed to download $file"
            download_success=false
        fi
    done
    
    if [[ "$download_success" == true ]]; then
        print_status "$GREEN" "All files downloaded successfully!"
        return 0
    else
        print_status "$RED" "Failed to download some files. Please check your internet connection."
        return 1
    fi
}

# Function to install scripts
install_scripts() {
    print_status "$BLUE" "Installing network fix scripts..."
    
    # Copy scripts to system location
    cp fix-network.sh "$INSTALL_DIR/fix-network.sh"
    cp network-monitor.sh "$INSTALL_DIR/network-monitor.sh"
    
    # Make them executable
    chmod +x "$INSTALL_DIR/fix-network.sh"
    chmod +x "$INSTALL_DIR/network-monitor.sh"
    
    # Create convenient symlinks
    ln -sf "$INSTALL_DIR/fix-network.sh" "$INSTALL_DIR/fix-network"
    ln -sf "$INSTALL_DIR/network-monitor.sh" "$INSTALL_DIR/network-monitor"
    
    print_status "$GREEN" "Scripts installed successfully!"
    echo "  - fix-network.sh -> $INSTALL_DIR/fix-network.sh"
    echo "  - network-monitor.sh -> $INSTALL_DIR/network-monitor.sh"
    echo "  - Created symlinks: fix-network, network-monitor"
}

# Function to install systemd service
install_service() {
    print_status "$BLUE" "Installing systemd service..."
    
    # Copy service file
    cp network-fix.service "$SERVICE_DIR/network-fix.service"
    
    # Reload systemd
    systemctl daemon-reload
    
    print_status "$GREEN" "Systemd service installed successfully!"
    echo "  - Service file: $SERVICE_DIR/network-fix.service"
}

# Function to setup logging
setup_logging() {
    print_status "$BLUE" "Setting up logging..."
    
    # Create log files with proper permissions
    touch "$LOG_DIR/network-fix.log"
    touch "$LOG_DIR/network-monitor.log"
    
    # Set permissions
    chmod 644 "$LOG_DIR/network-fix.log"
    chmod 644 "$LOG_DIR/network-monitor.log"
    
    print_status "$GREEN" "Logging setup complete!"
    echo "  - Network fix log: $LOG_DIR/network-fix.log"
    echo "  - Network monitor log: $LOG_DIR/network-monitor.log"
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
    print_status "$BLUE" "=== Installation Complete! ==="
    echo ""
    print_status "$YELLOW" "Manual Usage:"
    echo "  sudo fix-network            # Auto-detect interface"
    echo "  sudo fix-network eth0       # Specific interface"
    echo "  sudo network-monitor check  # Single connectivity check"
    echo "  network-monitor status      # View recent logs"
    echo ""
    print_status "$YELLOW" "View Logs:"
    echo "  sudo tail -f /var/log/network-fix.log"
    echo "  sudo tail -f /var/log/network-monitor.log"
    echo ""
    print_status "$GREEN" "For more information, see README.md"
}

# Function to test installation
test_installation() {
    print_status "$BLUE" "Testing installation..."
    
    # Test script execution
    if [[ -x "$INSTALL_DIR/fix-network.sh" ]]; then
        print_status "$GREEN" "✓ fix-network.sh is executable"
    else
        print_status "$RED" "✗ fix-network.sh is not executable"
        return 1
    fi
    
    if [[ -x "$INSTALL_DIR/network-monitor.sh" ]]; then
        print_status "$GREEN" "✓ network-monitor.sh is executable"
    else
        print_status "$RED" "✗ network-monitor.sh is not executable"
        return 1
    fi
    
    # Test service file
    if [[ -f "$SERVICE_DIR/network-fix.service" ]]; then
        print_status "$GREEN" "✓ systemd service file installed"
    else
        print_status "$RED" "✗ systemd service file not found"
        return 1
    fi
    
    # Test help commands
    if "$INSTALL_DIR/fix-network.sh" --help &>/dev/null; then
        print_status "$GREEN" "✓ fix-network help works"
    else
        print_status "$RED" "✗ fix-network help failed"
        return 1
    fi
    
    if "$INSTALL_DIR/network-monitor.sh" help &>/dev/null; then
        print_status "$GREEN" "✓ network-monitor help works"
    else
        print_status "$RED" "✗ network-monitor help failed"
        return 1
    fi
    
    print_status "$GREEN" "✓ All tests passed!"
    return 0
}

# Main installation function
main() {
    print_status "$BLUE" "=== Proxmox Network Fix Tools Installation ==="
    echo ""
    
    # Check if running as root
    check_root
    
    # Check if all files exist
    local missing_files=()
    [[ ! -f "fix-network.sh" ]] && missing_files+=("fix-network.sh")
    [[ ! -f "network-monitor.sh" ]] && missing_files+=("network-monitor.sh")
    [[ ! -f "network-fix.service" ]] && missing_files+=("network-fix.service")
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_status "$YELLOW" "Missing required files, attempting to download from repository..."
        printf ' - %s\n' "${missing_files[@]}"
        echo ""
        
        # Attempt to download missing files
        if ! download_scripts; then
            print_status "$RED" "Failed to download required files."
            print_status "$YELLOW" "Please manually download the files or run this script from the directory containing all the files."
            exit 1
        fi
        
        # Verify files were downloaded
        local still_missing=()
        [[ ! -f "fix-network.sh" ]] && still_missing+=("fix-network.sh")
        [[ ! -f "network-monitor.sh" ]] && still_missing+=("network-monitor.sh")
        [[ ! -f "network-fix.service" ]] && still_missing+=("network-fix.service")
        
        if [[ ${#still_missing[@]} -gt 0 ]]; then
            print_status "$RED" "Error: Still missing files after download attempt:"
            printf ' - %s\n' "${still_missing[@]}"
            exit 1
        fi
    fi
    
    # Perform installation
    install_scripts
    install_service
    setup_logging
    
    # Test installation
    if test_installation; then
        show_usage_options
        setup_automation
        exit 0
    else
        print_status "$RED" "Installation completed but tests failed. Please check the output above."
        exit 1
    fi
}

# Function for interactive mode
interactive_mode() {
    print_status "$BLUE" "=== Proxmox Network Fix Tools Setup ==="
    echo ""
    print_status "$YELLOW" "What would you like to do?"
    echo "1. Download and install network fix tools"
    echo "2. Download scripts only (no installation)"
    echo "3. Uninstall network fix tools"
    echo "4. Test current installation"
    echo "5. Exit"
    echo ""
    echo -n "Enter your choice (1-5): "
    read -r choice
    
    case "$choice" in
        1)
            echo ""
            main
            ;;
        2)
            echo ""
            print_status "$BLUE" "Downloading Proxmox Network Fix Tools..."
            if download_scripts; then
                print_status "$GREEN" "Download completed successfully!"
                print_status "$YELLOW" "Run '$0 1' to install the downloaded scripts."
            else
                print_status "$RED" "Download failed!"
                exit 1
            fi
            ;;
        3)
            echo ""
            uninstall_tools
            ;;
        4)
            echo ""
            check_root
            test_installation
            ;;
        5)
            print_status "$YELLOW" "Exiting..."
            exit 0
            ;;
        *)
            print_status "$RED" "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
}

# Function to handle uninstall
uninstall_tools() {
    print_status "$BLUE" "Uninstalling Proxmox Network Fix Tools..."
    
    # Stop and disable service
    systemctl stop network-fix.service 2>/dev/null
    systemctl disable network-fix.service 2>/dev/null
    
    # Remove files
    rm -f "$INSTALL_DIR/fix-network.sh"
    rm -f "$INSTALL_DIR/network-monitor.sh"
    rm -f "$INSTALL_DIR/fix-network"
    rm -f "$INSTALL_DIR/network-monitor"
    rm -f "$SERVICE_DIR/network-fix.service"
    
    # Remove ethtool workaround services
    rm -f "$SERVICE_DIR/ethtool-workaround-"*.service 2>/dev/null
    
    # Reload systemd
    systemctl daemon-reload
    
    # Remove cron job if it exists
    if crontab -l 2>/dev/null | grep -q "network-monitor check"; then
        print_status "$YELLOW" "Removing cron job..."
        local temp_cron="/tmp/crontab.tmp"
        crontab -l | grep -v "network-monitor check" > "$temp_cron"
        crontab "$temp_cron" 2>/dev/null
        rm -f "$temp_cron"
        print_status "$GREEN" "✓ Cron job removed"
    fi
    
    print_status "$GREEN" "Uninstallation complete!"
    print_status "$YELLOW" "Log files remain at:"
    echo "  - $LOG_DIR/network-fix.log"
    echo "  - $LOG_DIR/network-monitor.log"
}

# Handle command line arguments
case "${1:-interactive}" in
    "install"|"1")
        main
        ;;
    "download"|"2")
        print_status "$BLUE" "Downloading Proxmox Network Fix Tools..."
        if download_scripts; then
            print_status "$GREEN" "Download completed successfully!"
            print_status "$YELLOW" "Run '$0 install' to install the downloaded scripts."
        else
            print_status "$RED" "Download failed!"
            exit 1
        fi
        ;;
    "uninstall"|"3")
        uninstall_tools
        ;;
    "test"|"4")
        check_root
        test_installation
        ;;
    "interactive"|"")
        interactive_mode
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)  - Interactive mode with menu options"
        echo "  install    - Download and install network fix tools"
        echo "  download   - Download scripts from repository only"
        echo "  uninstall  - Remove network fix tools"
        echo "  test       - Test installation"
        echo "  help       - Show this help message"
        echo ""
        echo "Interactive Options:"
        echo "  1. Download and install network fix tools"
        echo "  2. Download scripts only (no installation)"  
        echo "  3. Uninstall network fix tools"
        echo "  4. Test current installation"
        echo "  5. Exit"
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
