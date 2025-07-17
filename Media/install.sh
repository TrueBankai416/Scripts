#!/bin/bash

# Media Monitor Installation Script for Linux
# Installs dependencies and sets up the media monitoring system

# Configuration
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log"
SCRIPT_NAME="media-monitor"
SERVICE_NAME="media-monitor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print colored output
print_color() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "$RED" "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
    else
        print_color "$RED" "Cannot detect OS. This script supports Ubuntu/Debian systems."
        exit 1
    fi
    
    print_color "$BLUE" "Detected OS: $OS $VERSION"
}

# Function to install dependencies
install_dependencies() {
    print_color "$BLUE" "Installing dependencies..."
    
    # Update package lists
    apt update
    
    # Install required packages
    if apt install -y inotify-tools; then
        print_color "$GREEN" "Dependencies installed successfully"
    else
        print_color "$RED" "Failed to install dependencies"
        exit 1
    fi
}

# Function to download media monitor script
download_script() {
    print_color "$BLUE" "Downloading media monitor script..."
    
    local script_url="https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Media/media-monitor.sh"
    local temp_file="/tmp/media-monitor.sh"
    
    if curl -fsSL "$script_url" -o "$temp_file"; then
        print_color "$GREEN" "Script downloaded successfully"
        
        # Make executable and move to install directory
        chmod +x "$temp_file"
        mv "$temp_file" "$INSTALL_DIR/$SCRIPT_NAME"
        
        print_color "$GREEN" "Script installed to $INSTALL_DIR/$SCRIPT_NAME"
    else
        print_color "$RED" "Failed to download script"
        exit 1
    fi
}

# Function to configure the script
configure_script() {
    print_color "$BLUE" "Configuring media monitor..."
    
    echo "Please provide the following paths:"
    
    # Get source directories
    read -p "Movies source directory (Tdarr output): " movies_source
    read -p "TV source directory (Tdarr output): " tv_source
    
    # Get destination directories
    read -p "Movies destination directory (Jellyfin): " movies_dest
    read -p "TV destination directory (Jellyfin): " tv_dest
    
    # Get delay
    read -p "Delay in hours before moving files [1]: " delay_hours
    delay_hours=${delay_hours:-1}
    
    # Validate paths
    if [[ ! -d "$movies_source" ]]; then
        print_color "$YELLOW" "Warning: Movies source directory does not exist: $movies_source"
    fi
    
    if [[ ! -d "$tv_source" ]]; then
        print_color "$YELLOW" "Warning: TV source directory does not exist: $tv_source"
    fi
    
    # Create destination directories if they don't exist
    mkdir -p "$movies_dest" "$tv_dest"
    
    # Update script configuration
    sed -i "s|MOVIES_SOURCE=\".*\"|MOVIES_SOURCE=\"$movies_source\"|" "$INSTALL_DIR/$SCRIPT_NAME"
    sed -i "s|TV_SOURCE=\".*\"|TV_SOURCE=\"$tv_source\"|" "$INSTALL_DIR/$SCRIPT_NAME"
    sed -i "s|MOVIES_DEST=\".*\"|MOVIES_DEST=\"$movies_dest\"|" "$INSTALL_DIR/$SCRIPT_NAME"
    sed -i "s|TV_DEST=\".*\"|TV_DEST=\"$tv_dest\"|" "$INSTALL_DIR/$SCRIPT_NAME"
    sed -i "s|DELAY_HOURS=.*|DELAY_HOURS=$delay_hours|" "$INSTALL_DIR/$SCRIPT_NAME"
    
    print_color "$GREEN" "Configuration updated successfully"
}

# Function to create systemd service
create_service() {
    print_color "$BLUE" "Creating systemd service..."
    
    cat > "$SERVICE_DIR/$SERVICE_NAME.service" << EOF
[Unit]
Description=Media Monitor Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/$SCRIPT_NAME
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    print_color "$GREEN" "Systemd service created and enabled"
}

# Function to start service
start_service() {
    print_color "$BLUE" "Starting media monitor service..."
    
    if systemctl start "$SERVICE_NAME"; then
        print_color "$GREEN" "Service started successfully"
        
        # Show service status
        systemctl status "$SERVICE_NAME" --no-pager
    else
        print_color "$RED" "Failed to start service"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  install     - Install media monitor"
    echo "  uninstall   - Uninstall media monitor"
    echo "  status      - Show service status"
    echo "  logs        - Show service logs"
    echo "  restart     - Restart service"
    echo "  help        - Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0 install"
    echo "  sudo $0 uninstall"
    echo "  $0 status"
    echo "  $0 logs"
}

# Function to uninstall
uninstall() {
    print_color "$BLUE" "Uninstalling media monitor..."
    
    # Stop and disable service
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    
    # Remove service file
    rm -f "$SERVICE_DIR/$SERVICE_NAME.service"
    
    # Remove script
    rm -f "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Reload systemd
    systemctl daemon-reload
    
    print_color "$GREEN" "Media monitor uninstalled successfully"
}

# Function to show service status
show_status() {
    systemctl status "$SERVICE_NAME" --no-pager
}

# Function to show service logs
show_logs() {
    journalctl -u "$SERVICE_NAME" -f
}

# Function to restart service
restart_service() {
    print_color "$BLUE" "Restarting media monitor service..."
    
    if systemctl restart "$SERVICE_NAME"; then
        print_color "$GREEN" "Service restarted successfully"
        show_status
    else
        print_color "$RED" "Failed to restart service"
        exit 1
    fi
}

# Function to run interactive installation
interactive_install() {
    print_color "$GREEN" "=== Media Monitor Installation ==="
    print_color "$BLUE" "This script will install and configure the media monitor service."
    echo
    
    # Check for existing installation
    if [[ -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        print_color "$YELLOW" "Media monitor is already installed."
        read -p "Do you want to reinstall? (y/N): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            print_color "$BLUE" "Installation cancelled."
            exit 0
        fi
        
        # Uninstall existing
        uninstall
    fi
    
    # Run installation steps
    detect_os
    install_dependencies
    download_script
    configure_script
    create_service
    start_service
    
    print_color "$GREEN" "=== Installation Complete ==="
    echo
    print_color "$BLUE" "The media monitor service is now running and will start automatically on boot."
    echo
    print_color "$BLUE" "Useful commands:"
    echo "  sudo systemctl status $SERVICE_NAME    - Check service status"
    echo "  sudo systemctl stop $SERVICE_NAME      - Stop service"
    echo "  sudo systemctl start $SERVICE_NAME     - Start service"
    echo "  sudo systemctl restart $SERVICE_NAME   - Restart service"
    echo "  sudo journalctl -u $SERVICE_NAME -f    - View live logs"
    echo "  sudo tail -f $LOG_DIR/media-monitor.log - View application logs"
}

# Main script execution
main() {
    case "${1:-install}" in
        install)
            check_root
            interactive_install
            ;;
        uninstall)
            check_root
            uninstall
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        restart)
            check_root
            restart_service
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_color "$RED" "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
