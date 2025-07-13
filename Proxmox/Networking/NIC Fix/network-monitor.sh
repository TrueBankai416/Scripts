#!/bin/bash

# Network Monitor Script for Proxmox
# Continuously monitors network connectivity and automatically fixes issues
# This script can be run as a cron job or systemd service

# Configuration
LOG_FILE="/var/log/network-monitor.log"
PING_TARGET="8.8.8.8"
PING_TIMEOUT=5
CHECK_INTERVAL=300  # 5 minutes
MAX_FAILURES=2      # Require 2 consecutive failures before attempting fix
FIX_SCRIPT="/usr/local/bin/fix-network.sh"

# Failure counter
FAILURE_COUNT=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to check network connectivity
check_connectivity() {
    if ping -c 1 -W "$PING_TIMEOUT" "$PING_TARGET" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to attempt network fix
attempt_fix() {
    log_message "WARN" "Attempting to fix network connectivity"
    
    if [[ -x "$FIX_SCRIPT" ]]; then
        log_message "INFO" "Running network fix script: $FIX_SCRIPT"
        "$FIX_SCRIPT" >> "$LOG_FILE" 2>&1
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            log_message "INFO" "Network fix script completed successfully"
            return 0
        else
            log_message "ERROR" "Network fix script failed with exit code: $exit_code"
            return 1
        fi
    else
        log_message "ERROR" "Network fix script not found or not executable: $FIX_SCRIPT"
        return 1
    fi
}

# Function to send notification (placeholder for future enhancement)
send_notification() {
    local message="$1"
    # Could be enhanced to send email, slack, etc.
    log_message "NOTIFY" "$message"
}

# Main monitoring function
monitor_network() {
    log_message "INFO" "Network monitoring started (PID: $$)"
    log_message "INFO" "Check interval: ${CHECK_INTERVAL}s, Max failures: $MAX_FAILURES"
    
    while true; do
        if check_connectivity; then
            if [[ $FAILURE_COUNT -gt 0 ]]; then
                log_message "INFO" "Network connectivity restored"
                send_notification "Network connectivity restored after $FAILURE_COUNT failures"
                FAILURE_COUNT=0
            else
                log_message "DEBUG" "Network connectivity OK"
            fi
        else
            ((FAILURE_COUNT++))
            log_message "WARN" "Network connectivity failed (failure $FAILURE_COUNT/$MAX_FAILURES)"
            
            if [[ $FAILURE_COUNT -ge $MAX_FAILURES ]]; then
                log_message "ERROR" "Network connectivity failed $MAX_FAILURES consecutive times"
                send_notification "Network connectivity failed, attempting automatic fix"
                
                if attempt_fix; then
                    log_message "INFO" "Network fix attempted, will verify on next check"
                    FAILURE_COUNT=0
                else
                    log_message "ERROR" "Network fix failed, manual intervention may be required"
                    send_notification "Automatic network fix failed, manual intervention required"
                    # Reset counter to prevent spam
                    FAILURE_COUNT=0
                fi
            fi
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Function to run single check (for cron usage)
single_check() {
    if ! check_connectivity; then
        log_message "WARN" "Network connectivity failed, attempting fix"
        attempt_fix
    else
        log_message "DEBUG" "Network connectivity OK"
    fi
}

# Handle command line arguments
case "${1:-monitor}" in
    "monitor")
        # Check if running as root
        if [[ $EUID -ne 0 ]]; then
            echo -e "${RED}Error: This script must be run as root${NC}"
            exit 1
        fi
        
        # Create log file if it doesn't exist
        touch "$LOG_FILE"
        
        # Start monitoring
        monitor_network
        ;;
    "check")
        # Single check mode (for cron)
        if [[ $EUID -ne 0 ]]; then
            echo -e "${RED}Error: This script must be run as root${NC}"
            exit 1
        fi
        
        # Create log file if it doesn't exist
        touch "$LOG_FILE"
        
        # Perform single check
        single_check
        ;;
    "status")
        # Show recent log entries
        if [[ -f "$LOG_FILE" ]]; then
            echo "Recent network monitor log entries:"
            tail -20 "$LOG_FILE"
        else
            echo "No log file found at $LOG_FILE"
        fi
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  monitor  - Start continuous network monitoring (default)"
        echo "  check    - Perform single connectivity check (for cron)"
        echo "  status   - Show recent log entries"
        echo "  help     - Show this help message"
        echo ""
        echo "Configuration (edit script to change):"
        echo "  Check interval: ${CHECK_INTERVAL}s"
        echo "  Max failures: $MAX_FAILURES"
        echo "  Ping target: $PING_TARGET"
        echo "  Log file: $LOG_FILE"
        echo "  Fix script: $FIX_SCRIPT"
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
