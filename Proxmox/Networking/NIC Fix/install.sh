#!/bin/bash

# Installation script for Proxmox Network Fix Tools
# This script sets up the network fix and monitoring tools

# Configuration
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log"

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

# Function to show usage options
show_usage_options() {
    print_status "$BLUE" "=== Installation Complete! ==="
    echo ""
    print_status "$YELLOW" "Usage Options:"
    echo ""
    echo "1. Manual network fix:"
    echo "   sudo fix-network"
    echo "   sudo fix-network eth0"
    echo ""
    echo "2. Single connectivity check:"
    echo "   sudo network-monitor check"
    echo ""
    echo "3. View monitoring status:"
    echo "   network-monitor status"
    echo ""
    echo "4. Setup automatic monitoring:"
    echo ""
    print_status "$YELLOW" "   Option A: Systemd Service (recommended)"
    echo "   sudo systemctl enable network-fix.service"
    echo "   sudo systemctl start network-fix.service"
    echo "   sudo systemctl status network-fix.service"
    echo ""
    print_status "$YELLOW" "   Option B: Cron Job (every 5 minutes)"
    echo "   sudo crontab -e"
    echo "   # Add this line:"
    echo "   */5 * * * * /usr/local/bin/network-monitor check"
    echo ""
    echo "5. View logs:"
    echo "   sudo tail -f /var/log/network-fix.log"
    echo "   sudo tail -f /var/log/network-monitor.log"
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
        print_status "$RED" "Error: Missing required files:"
        printf ' - %s\n' "${missing_files[@]}"
        echo ""
        print_status "$YELLOW" "Please run this script from the directory containing all the files."
        exit 1
    fi
    
    # Perform installation
    install_scripts
    install_service
    setup_logging
    
    # Test installation
    if test_installation; then
        show_usage_options
        exit 0
    else
        print_status "$RED" "Installation completed but tests failed. Please check the output above."
        exit 1
    fi
}

# Handle command line arguments
case "${1:-install}" in
    "install")
        main
        ;;
    "uninstall")
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
        
        # Reload systemd
        systemctl daemon-reload
        
        print_status "$GREEN" "Uninstallation complete!"
        print_status "$YELLOW" "Log files remain at:"
        echo "  - $LOG_DIR/network-fix.log"
        echo "  - $LOG_DIR/network-monitor.log"
        ;;
    "test")
        check_root
        test_installation
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  install    - Install network fix tools (default)"
        echo "  uninstall  - Remove network fix tools"
        echo "  test       - Test installation"
        echo "  help       - Show this help message"
        ;;
    *)
        print_status "$RED" "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
