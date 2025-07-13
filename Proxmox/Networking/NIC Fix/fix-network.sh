#!/bin/bash

# Network Interface Restart Script for Proxmox
# This script restarts the network interface when connectivity is lost
# Usage: ./fix-network.sh [interface_name]

# Configuration
LOG_FILE="/var/log/network-fix.log"
MAX_RETRIES=3
RETRY_DELAY=5
PING_TARGET="8.8.8.8"
CONNECTIVITY_TIMEOUT=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Function to check network connectivity
check_connectivity() {
    local target="$1"
    local timeout="$2"
    
    if ping -c 1 -W "$timeout" "$target" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check if interface is a bridge
is_bridge_interface() {
    local interface="$1"
    [[ -d "/sys/class/net/$interface/bridge" ]]
}

# Function to get bridge members (physical interfaces attached to bridge)
get_bridge_members() {
    local bridge="$1"
    if [[ -d "/sys/class/net/$bridge/brif" ]]; then
        ls "/sys/class/net/$bridge/brif" 2>/dev/null | tr '\n' ' '
    fi
}

# Function to detect hardware hangs from kernel logs
detect_hardware_hang() {
    local interface="$1"
    local recent_minutes=5
    
    # Check for hardware hang messages in recent kernel logs
    if dmesg -T | tail -200 | grep -i "detected hardware unit hang" | grep "$interface" >/dev/null 2>&1; then
        return 0
    fi
    
    # Also check journalctl for recent hang messages
    if journalctl --since="$recent_minutes minutes ago" --no-pager 2>/dev/null | grep -i "detected hardware unit hang" | grep "$interface" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Function to get network controller driver
get_interface_driver() {
    local interface="$1"
    if [[ -L "/sys/class/net/$interface/device/driver" ]]; then
        basename $(readlink "/sys/class/net/$interface/device/driver")
    fi
}

# Function to check if interface is virtual (not physical hardware)
is_virtual_interface() {
    local interface="$1"
    
    # Common virtual interface patterns in Proxmox
    if [[ "$interface" =~ ^(fwpr|fwbr|fwln|veth|tap|tun|vmbr|lo|dummy|bond|team).*$ ]]; then
        return 0
    fi
    
    # Check if interface has no physical device (virtual)
    if [[ ! -e "/sys/class/net/$interface/device" ]]; then
        return 0
    fi
    
    # Additional check for virtual drivers
    local driver=$(get_interface_driver "$interface")
    if [[ "$driver" =~ ^(veth|dummy|bridge|bonding|team).*$ ]]; then
        return 0
    fi
    
    return 1
}

# Function to disable problematic ethtool features (Proxmox forum workaround)
disable_problematic_features() {
    local interface="$1"
    
    echo -e "${YELLOW}Applying Proxmox forum workaround: disabling problematic features...${NC}"
    log_message "INFO" "Disabling problematic ethtool features for $interface (Proxmox forum workaround)"
    
    # Disable features known to cause issues with Intel e1000e in recent Proxmox kernels
    # Based on: https://forum.proxmox.com/threads/proxmox-6-8-12-9-pve-kernel-has-introduced-a-problem-with-e1000e-driver-and-network-connection-lost-after-some-hours.164439/
    local features_to_disable="gso gro tso tx rx rxvlan txvlan sg"
    local features_applied=()
    
    for feature in $features_to_disable; do
        if ethtool -K "$interface" "$feature" off 2>/dev/null; then
            log_message "INFO" "Disabled $feature for $interface"
            features_applied+=("$feature")
        else
            log_message "WARN" "Failed to disable $feature for $interface"
        fi
    done
    
    # Log current feature status
    log_message "INFO" "Current features for $interface: $(ethtool -k "$interface" 2>/dev/null | grep -E '(gso|gro|tso|tx|rx|rxvlan|txvlan|sg):' | tr '\n' ' ')"
    
    # Create persistent configuration if features were successfully applied
    if [[ ${#features_applied[@]} -gt 0 ]]; then
        create_persistent_ethtool_config "$interface" "${features_applied[@]}"
    fi
    
    sleep 3
    return 0
}

# Function to create persistent ethtool configuration
create_persistent_ethtool_config() {
    local interface="$1"
    shift
    local features=("$@")
    
    local config_file="/etc/systemd/system/ethtool-workaround-${interface}.service"
    
    echo -e "${YELLOW}Creating persistent configuration for $interface...${NC}"
    log_message "INFO" "Creating persistent ethtool configuration for $interface"
    
    # Create systemd service to apply settings on boot
    cat > "$config_file" << EOF
[Unit]
Description=Apply ethtool workaround for Intel e1000e hardware hang ($interface)
After=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/bin/bash -c 'sleep 10 && $(printf "ethtool -K $interface %s off; " "${features[@]}")'
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    if [[ -f "$config_file" ]]; then
        # Enable the service
        systemctl daemon-reload
        if systemctl enable "ethtool-workaround-${interface}.service" 2>/dev/null; then
            log_message "INFO" "Created and enabled persistent ethtool workaround service for $interface"
            echo -e "${GREEN}✓ Persistent configuration created: $config_file${NC}"
        else
            log_message "WARN" "Created ethtool workaround service but failed to enable it"
            echo -e "${YELLOW}⚠ Service created but not enabled: $config_file${NC}"
        fi
    else
        log_message "ERROR" "Failed to create persistent ethtool configuration"
    fi
}

# Function to perform hardware-level reset
hardware_reset_interface() {
    local interface="$1"
    local driver=$(get_interface_driver "$interface")
    local reset_success=false
    
    log_message "INFO" "Attempting hardware-level reset for $interface (driver: $driver)"
    echo -e "${YELLOW}Performing hardware reset for $interface...${NC}"
    
    # Step 1: Try ethtool reset first (if available)
    if command -v ethtool >/dev/null 2>&1; then
        echo -e "${YELLOW}Step 1: Attempting ethtool reset...${NC}"
        log_message "INFO" "Attempting ethtool reset for $interface"
        
        # Reset the interface using ethtool
        if ethtool -r "$interface" 2>/dev/null; then
            log_message "INFO" "ethtool reset successful for $interface"
            reset_success=true
        fi
        sleep 2
        
        # Try to reset specific features that might help
        ethtool -K "$interface" rx off tx off 2>/dev/null
        sleep 1
        ethtool -K "$interface" rx on tx on 2>/dev/null
        sleep 2
    fi
    
    # Step 2: For Intel e1000e controllers, try module reload
    if [[ "$driver" == "e1000e" ]]; then
        echo -e "${YELLOW}Step 2: Detected Intel e1000e controller, attempting module reload...${NC}"
        log_message "INFO" "Attempting e1000e module reload for hardware hang recovery"
        
        # Get PCI address for the interface
        local pci_addr=$(basename $(readlink "/sys/class/net/$interface/device") 2>/dev/null)
        
        if [[ -n "$pci_addr" ]]; then
            log_message "INFO" "Interface $interface PCI address: $pci_addr"
            
            # Bring interface down first
            ip link set "$interface" down
            sleep 2
            
            # Remove and reload the e1000e module
            if lsmod | grep -q "^e1000e"; then
                echo -e "${YELLOW}Removing e1000e module...${NC}"
                if modprobe -r e1000e 2>/dev/null; then
                    log_message "INFO" "e1000e module removed successfully"
                    sleep 3
                    
                    echo -e "${YELLOW}Reloading e1000e module...${NC}"
                    if modprobe e1000e 2>/dev/null; then
                        log_message "INFO" "e1000e module reload completed successfully"
                        reset_success=true
                    else
                        log_message "ERROR" "Failed to reload e1000e module"
                    fi
                    sleep 5
                else
                    log_message "WARN" "Failed to remove e1000e module (may be in use)"
                fi
            fi
        fi
        
        # Step 3: Apply Proxmox forum workaround (feature disabling)
        echo -e "${YELLOW}Step 3: Applying Proxmox community workaround...${NC}"
        disable_problematic_features "$interface"
        
        # If module reload failed, still mark as attempted since we applied the workaround
        if [[ "$reset_success" == false ]]; then
            log_message "INFO" "Module reload not successful, but applied feature workaround"
            reset_success=true
        fi
    fi
    
    # Step 4: For other drivers, try generic approaches
    if [[ "$driver" != "e1000e" && -n "$driver" ]]; then
        echo -e "${YELLOW}Step 4: Attempting generic hardware reset for $driver driver...${NC}"
        log_message "INFO" "Attempting generic hardware reset for $driver driver"
        
        # Try to reset via sysfs if available
        local pci_addr=$(basename $(readlink "/sys/class/net/$interface/device") 2>/dev/null)
        if [[ -n "$pci_addr" && -f "/sys/bus/pci/devices/$pci_addr/reset" ]]; then
            echo -e "${YELLOW}Attempting PCI reset for $pci_addr...${NC}"
            if echo 1 > "/sys/bus/pci/devices/$pci_addr/reset" 2>/dev/null; then
                log_message "INFO" "PCI reset successful for $interface"
                reset_success=true
            else
                log_message "WARN" "PCI reset failed for $interface"
            fi
            sleep 3
        fi
        
        # Apply feature workaround for any Intel-based drivers
        if [[ "$driver" =~ ^(e1000|igb|ixgbe|i40e).*$ ]]; then
            echo -e "${YELLOW}Intel-based driver detected, applying feature workaround...${NC}"
            disable_problematic_features "$interface"
            reset_success=true
        fi
    fi
    
    # Step 5: Final verification and summary
    if [[ "$reset_success" == true ]]; then
        echo -e "${GREEN}Hardware reset procedure completed for $interface${NC}"
        log_message "INFO" "Hardware reset procedure completed successfully for $interface"
    else
        echo -e "${YELLOW}Hardware reset attempted but success uncertain for $interface${NC}"
        log_message "WARN" "Hardware reset attempted for $interface but success uncertain"
    fi
    
    return 0
}

# Function to get primary network interface
get_primary_interface() {
    # Get the interface used for the default route
    local interface=$(ip route show default | head -1 | sed 's/.*dev \([^ ]*\).*/\1/')
    
    if [[ -z "$interface" ]]; then
        # Fallback: get first non-loopback interface
        interface=$(ip -o link show | grep -v "lo:" | head -1 | cut -d: -f2 | tr -d ' ')
    fi
    
    echo "$interface"
}

# Function to restart network interface
restart_interface() {
    local interface="$1"
    local is_bridge=false
    local bridge_members=""
    
    log_message "INFO" "Attempting to restart interface: $interface"
    
    # Check if this is a bridge interface (common in Proxmox)
    if is_bridge_interface "$interface"; then
        is_bridge=true
        bridge_members=$(get_bridge_members "$interface")
        log_message "INFO" "Interface $interface is a bridge with members: $bridge_members"
        echo -e "${YELLOW}Detected bridge interface $interface with members: $bridge_members${NC}"
    fi
    
    # If it's a bridge, restart underlying physical interfaces first
    if [[ "$is_bridge" == true && -n "$bridge_members" ]]; then
        local physical_members=0
        local virtual_members=0
        
        for member in $bridge_members; do
            # Skip virtual interfaces (VM/firewall interfaces)
            if is_virtual_interface "$member"; then
                log_message "DEBUG" "Skipping virtual interface: $member"
                ((virtual_members++))
                continue
            fi
            
            ((physical_members++))
            echo -e "${YELLOW}Restarting bridge member: $member${NC}"
            log_message "INFO" "Restarting physical bridge member: $member"
            
            # Get driver info for troubleshooting
            local driver=$(get_interface_driver "$member")
            log_message "INFO" "Bridge member $member uses driver: $driver"
            
            # Check if this interface has hardware hang issues OR is e1000e (proactive)
            local needs_hardware_reset=false
            if detect_hardware_hang "$member"; then
                echo -e "${RED}Hardware hang detected for $member, using hardware reset${NC}"
                log_message "WARN" "Hardware hang detected for $member, attempting hardware reset"
                needs_hardware_reset=true
            elif [[ "$driver" == "e1000e" ]]; then
                echo -e "${YELLOW}Intel e1000e controller detected for bridge member $member, using proactive hardware reset${NC}"
                log_message "INFO" "Intel e1000e controller detected for bridge member $member, applying proactive hardware reset"
                needs_hardware_reset=true
            fi
            
            if [[ "$needs_hardware_reset" == true ]]; then
                # Use hardware reset for hung interfaces
                hardware_reset_interface "$member"
            else
                # Standard software reset
                ip link set "$member" down
                if [[ $? -eq 0 ]]; then
                    log_message "INFO" "Bridge member $member brought down successfully"
                else
                    log_message "WARN" "Failed to bring down bridge member $member"
                fi
                
                sleep 2
                
                ip link set "$member" up
                if [[ $? -eq 0 ]]; then
                    log_message "INFO" "Bridge member $member brought up successfully"
                else
                    log_message "WARN" "Failed to bring up bridge member $member"
                fi
                
                sleep 3
            fi
        done
        
        # Log summary of processed interfaces
        echo -e "${BLUE}Bridge member summary: $physical_members physical, $virtual_members virtual (skipped)${NC}"
        log_message "INFO" "Bridge member summary: $physical_members physical interfaces processed, $virtual_members virtual interfaces skipped"
        
        # Extra delay for hardware resets to complete
        echo -e "${YELLOW}Waiting for bridge members to stabilize...${NC}"
        sleep 5
    fi
    
    # Check if the main interface itself has hardware issues
    local main_needs_hardware_reset=false
    if detect_hardware_hang "$interface"; then
        echo -e "${RED}Hardware hang detected for main interface $interface${NC}"
        log_message "WARN" "Hardware hang detected for main interface $interface"
        main_needs_hardware_reset=true
    fi
    
    # For non-bridge interfaces, also check if they might benefit from hardware reset
    if [[ "$is_bridge" == false ]]; then
        local driver=$(get_interface_driver "$interface")
        log_message "INFO" "Interface $interface uses driver: $driver"
        
        # Intel e1000e is known to have hardware hang issues
        if [[ "$driver" == "e1000e" ]]; then
            echo -e "${YELLOW}Intel e1000e controller detected, will use hardware reset approach${NC}"
            log_message "INFO" "Intel e1000e controller detected for $interface"
            main_needs_hardware_reset=true
        fi
    fi
    
    if [[ "$main_needs_hardware_reset" == true && "$is_bridge" == false ]]; then
        # Use hardware reset for the main interface
        hardware_reset_interface "$interface"
    else
        # Standard software reset for the main interface (or bridge)
        echo -e "${YELLOW}Bringing down interface $interface...${NC}"
        ip link set "$interface" down
        
        if [[ $? -eq 0 ]]; then
            log_message "INFO" "Interface $interface brought down successfully"
        else
            log_message "ERROR" "Failed to bring down interface $interface"
            return 1
        fi
        
        # Wait longer for bridges
        if [[ "$is_bridge" == true ]]; then
            sleep 3
        else
            sleep 2
        fi
        
        # Bring interface back up
        echo -e "${YELLOW}Bringing up interface $interface...${NC}"
        ip link set "$interface" up
        
        if [[ $? -eq 0 ]]; then
            log_message "INFO" "Interface $interface brought up successfully"
        else
            log_message "ERROR" "Failed to bring up interface $interface"
            return 1
        fi
    fi
    
    # Wait for interface to be ready (longer for bridges)
    if [[ "$is_bridge" == true ]]; then
        sleep 5
    else
        sleep 3
    fi
    
    # For Proxmox, try restarting networking service
    echo -e "${YELLOW}Restarting networking service...${NC}"
    if systemctl restart networking; then
        log_message "INFO" "Networking service restarted successfully"
    else
        log_message "WARN" "Failed to restart networking service, trying ifup/ifdown"
        
        # Alternative: try ifdown/ifup
        ifdown "$interface" 2>/dev/null
        sleep 2
        ifup "$interface" 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            log_message "INFO" "Interface $interface restarted with ifup/ifdown"
        else
            log_message "WARN" "ifup/ifdown also failed, but interface restart may still work"
        fi
    fi
    
    # Wait longer for network to stabilize (especially for bridges)
    if [[ "$is_bridge" == true ]]; then
        echo -e "${YELLOW}Waiting for bridge to stabilize...${NC}"
        sleep 10
    else
        sleep 5
    fi
    
    # Additional diagnostics
    log_message "INFO" "Interface status after restart: $(ip link show "$interface" | grep -E 'state|flags')"
    
    # Try DHCP renewal if interface appears to be up but no connectivity
    echo -e "${YELLOW}Attempting DHCP renewal...${NC}"
    log_message "INFO" "Attempting DHCP renewal for interface $interface"
    
    # Kill any existing dhclient processes for this interface
    pkill -f "dhclient.*$interface" 2>/dev/null
    sleep 1
    
    # Try to renew DHCP lease
    if dhclient -r "$interface" 2>/dev/null; then
        log_message "INFO" "DHCP release successful for $interface"
        sleep 2
        if dhclient "$interface" 2>/dev/null; then
            log_message "INFO" "DHCP renewal successful for $interface"
        else
            log_message "WARN" "DHCP renewal failed for $interface"
        fi
    else
        log_message "WARN" "DHCP release failed, trying direct renewal"
        dhclient "$interface" 2>/dev/null
    fi
    
    # Final wait for DHCP to complete
    sleep 5
    
    return 0
}

# Function to verify network fix
verify_fix() {
    local interface="$1"
    local max_attempts=15  # Increased for bridges
    local attempt=1
    local wait_time=3      # Increased wait time
    
    echo -e "${YELLOW}Verifying network connectivity...${NC}"
    
    # If it's a bridge, be more patient
    if is_bridge_interface "$interface"; then
        max_attempts=20
        wait_time=5
        echo -e "${YELLOW}Bridge interface detected, allowing extra time for stabilization...${NC}"
    fi
    
    while [[ $attempt -le $max_attempts ]]; do
        # Additional diagnostics on failed attempts
        if [[ $attempt -gt 5 ]]; then
            log_message "DEBUG" "Interface $interface status: $(ip addr show "$interface" 2>/dev/null | grep 'inet\|state')"
            log_message "DEBUG" "Default route: $(ip route show default 2>/dev/null)"
        fi
        
        if check_connectivity "$PING_TARGET" "$CONNECTIVITY_TIMEOUT"; then
            echo -e "${GREEN}Network connectivity restored!${NC}"
            log_message "INFO" "Network connectivity verified after $attempt attempts"
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts: Network still not reachable, waiting ${wait_time}s..."
        
        # Try alternative connectivity tests on later attempts
        if [[ $attempt -gt 10 ]]; then
            echo "Trying alternative connectivity tests..."
            # Try ping to gateway if we can find it
            local gateway=$(ip route show default 2>/dev/null | head -1 | sed 's/.*via \([^ ]*\).*/\1/')
            if [[ -n "$gateway" && "$gateway" != "$PING_TARGET" ]]; then
                echo "Testing connectivity to gateway: $gateway"
                if ping -c 1 -W 3 "$gateway" &>/dev/null; then
                    echo -e "${YELLOW}Gateway is reachable, DNS might be the issue${NC}"
                    log_message "INFO" "Gateway $gateway is reachable but external connectivity failed"
                fi
            fi
            
            # Try alternative DNS servers
            for alt_dns in "1.1.1.1" "208.67.222.222"; do
                if [[ "$alt_dns" != "$PING_TARGET" ]]; then
                    echo "Testing connectivity to $alt_dns..."
                    if ping -c 1 -W 3 "$alt_dns" &>/dev/null; then
                        echo -e "${GREEN}Alternative connectivity test successful to $alt_dns${NC}"
                        log_message "INFO" "Network connectivity verified using alternative target $alt_dns after $attempt attempts"
                        return 0
                    fi
                fi
            done
        fi
        
        sleep "$wait_time"
        ((attempt++))
    done
    
    echo -e "${RED}Network connectivity could not be verified after $max_attempts attempts${NC}"
    log_message "ERROR" "Network connectivity verification failed after $max_attempts attempts"
    
    # Final diagnostics
    echo -e "${YELLOW}Final diagnostic information:${NC}"
    echo "Interface status:"
    ip addr show "$interface" 2>/dev/null || echo "Could not get interface status"
    echo "Routing table:"
    ip route show 2>/dev/null || echo "Could not get routing table"
    echo "DNS resolution test:"
    nslookup google.com 2>/dev/null || echo "DNS resolution failed"
    
    return 1
}

# Main function
main() {
    local interface="$1"
    local retry_count=0
    
    echo -e "${YELLOW}=== Proxmox Network Interface Restart Script ===${NC}"
    log_message "INFO" "Script started"
    
    # Check if running as root
    check_root
    
    # Create log file if it doesn't exist
    touch "$LOG_FILE"
    
    # Get interface if not provided
    if [[ -z "$interface" ]]; then
        interface=$(get_primary_interface)
        if [[ -z "$interface" ]]; then
            echo -e "${RED}Error: Could not determine primary network interface${NC}"
            log_message "ERROR" "Could not determine primary network interface"
            exit 1
        fi
    fi
    
    echo "Using network interface: $interface"
    log_message "INFO" "Using network interface: $interface"
    
    # Check if interface exists
    if ! ip link show "$interface" &>/dev/null; then
        echo -e "${RED}Error: Interface $interface does not exist${NC}"
        log_message "ERROR" "Interface $interface does not exist"
        exit 1
    fi
    
    # Check current connectivity
    echo "Checking current network connectivity..."
    if check_connectivity "$PING_TARGET" "$CONNECTIVITY_TIMEOUT"; then
        echo -e "${GREEN}Network appears to be working. Are you sure you want to restart the interface? (y/N)${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Aborted by user."
            log_message "INFO" "Script aborted by user - network was working"
            exit 0
        fi
    else
        echo -e "${RED}Network connectivity issue detected. Proceeding with interface restart...${NC}"
        log_message "WARN" "Network connectivity issue detected"
    fi
    
    # Attempt to fix network with retries
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        ((retry_count++))
        
        echo -e "${YELLOW}Attempt $retry_count/$MAX_RETRIES to restart network interface...${NC}"
        
        if restart_interface "$interface"; then
            # Verify the fix worked
            if verify_fix "$interface"; then
                echo -e "${GREEN}Network interface restart completed successfully!${NC}"
                log_message "INFO" "Network interface restart completed successfully on attempt $retry_count"
                exit 0
            fi
        fi
        
        if [[ $retry_count -lt $MAX_RETRIES ]]; then
            echo -e "${YELLOW}Retry $retry_count failed. Waiting $RETRY_DELAY seconds before next attempt...${NC}"
            sleep "$RETRY_DELAY"
        fi
    done
    
    echo -e "${RED}Failed to restore network connectivity after $MAX_RETRIES attempts${NC}"
    log_message "ERROR" "Failed to restore network connectivity after $MAX_RETRIES attempts"
    
    echo -e "${YELLOW}Manual intervention may be required. Check:${NC}"
    echo "1. Physical cable connections"
    echo "2. Switch/router status"
    echo "3. Network configuration files"
    echo "4. Check logs: tail -f $LOG_FILE"
    echo "5. For Proxmox bridge issues, try:"
    echo "   - Check /etc/network/interfaces configuration"
    echo "   - Verify bridge members: ls /sys/class/net/$interface/brif/"
    echo "   - Check physical cable connections"
    echo "   - Restart with specific interface: $0 <physical_interface>"
    echo "   - Check ethtool workaround service: systemctl status ethtool-workaround-eno2.service"
    
    exit 1
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [interface_name]"
    echo ""
    echo "Network Interface Restart Script for Proxmox"
    echo "Restarts the network interface to fix connectivity issues"
    echo ""
    echo "Options:"
    echo "  interface_name    Specific network interface to restart (optional)"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0               # Auto-detect and restart primary interface"
    echo "  $0 eth0          # Restart specific interface"
    echo "  $0 enp0s3        # Restart specific interface"
    exit 0
fi

# Run main function
main "$@"
