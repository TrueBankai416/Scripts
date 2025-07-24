#!/bin/bash

# Proxmox APT Repository Fix Script
# Diagnoses and fixes common APT repository issues including broken local repos and duplicates
# Usage: ./apt-fix.sh

# Configuration
LOG_FILE="/var/log/apt-fix.log"
BACKUP_DIR="/var/backups/apt-fix"

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
    echo -e "${BLUE}=== System Overview ===${NC}"
    
    echo "Operating System:"
    if command -v pveversion &> /dev/null; then
        echo "Proxmox Virtual Environment"
        pveversion
    else
        lsb_release -d 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2
    fi
    echo ""
    
    echo "APT Version:"
    apt --version 2>/dev/null || echo "APT not available"
    echo ""
    
    echo "Current disk usage (important for APT operations):"
    df -h / | tail -1
    echo ""
}

# Function to create backup directory and backup APT configuration
create_backups() {
    echo -e "${BLUE}=== Creating Configuration Backups ===${NC}"
    
    mkdir -p "$BACKUP_DIR"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Backup main sources.list
    if [[ -f "/etc/apt/sources.list" ]]; then
        cp "/etc/apt/sources.list" "$BACKUP_DIR/sources.list.backup.$timestamp"
        echo -e "${GREEN}✓ Backed up /etc/apt/sources.list${NC}"
        log_message "INFO" "Backed up /etc/apt/sources.list"
    fi
    
    # Backup sources.list.d directory
    if [[ -d "/etc/apt/sources.list.d" ]]; then
        tar -czf "$BACKUP_DIR/sources.list.d.backup.$timestamp.tar.gz" /etc/apt/sources.list.d/ 2>/dev/null
        echo -e "${GREEN}✓ Backed up /etc/apt/sources.list.d/${NC}"
        log_message "INFO" "Backed up /etc/apt/sources.list.d/"
    fi
    
    # Backup APT preferences if they exist
    if [[ -f "/etc/apt/preferences" ]]; then
        cp "/etc/apt/preferences" "$BACKUP_DIR/preferences.backup.$timestamp"
        echo -e "${GREEN}✓ Backed up /etc/apt/preferences${NC}"
    fi
    
    echo "Backup location: $BACKUP_DIR"
    echo ""
}

# Function to check APT repository health
check_apt_repositories() {
    echo -e "${BLUE}=== Checking APT Repository Health ===${NC}"
    
    local issues_found=false
    
    # Test current APT update status
    echo "Testing current APT update..."
    local apt_output=$(apt update 2>&1)
    local apt_exit_code=$?
    
    if [[ $apt_exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ APT update completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ APT update failed with exit code: $apt_exit_code${NC}"
        echo ""
        echo "APT update output:"
        echo "$apt_output"
        echo ""
        issues_found=true
        
        # Store APT output for use by other functions
        echo "$apt_output" > /tmp/apt-fix-output.txt
    fi
    
    # Analyze common error patterns
    echo "Analyzing APT errors..."
    
    # Check for broken local repositories
    if echo "$apt_output" | grep -q "file:.*Release.*No such file or directory"; then
        echo -e "${RED}✗ Broken local repository detected${NC}"
        local broken_repos=$(echo "$apt_output" | grep "file:.*Release.*No such file or directory" | sed 's/.*file:\([^ ]*\).*/\1/')
        echo "Broken local repositories:"
        echo "$broken_repos"
        log_message "ERROR" "Broken local repositories found: $broken_repos"
        issues_found=true
    fi
    
    # Check for duplicate repository warnings
    if echo "$apt_output" | grep -q "configured multiple times"; then
        echo -e "${YELLOW}⚠ Duplicate repository configurations detected${NC}"
        echo "Duplicate repository warnings:"
        echo "$apt_output" | grep "configured multiple times"
        log_message "WARN" "Duplicate repository configurations detected"
        issues_found=true
    fi
    
    # Check for GPG key errors
    if echo "$apt_output" | grep -qi "gpg.*error\|key.*error\|signature.*error"; then
        echo -e "${YELLOW}⚠ GPG key issues detected${NC}"
        echo "$apt_output" | grep -i "gpg.*error\|key.*error\|signature.*error"
        log_message "WARN" "GPG key issues detected"
        issues_found=true
    fi
    
    # Check for network connectivity issues
    if echo "$apt_output" | grep -qi "network\|connection\|timeout\|resolve"; then
        echo -e "${YELLOW}⚠ Network connectivity issues detected${NC}"
        echo "$apt_output" | grep -i "network\|connection\|timeout\|resolve"
        log_message "WARN" "Network connectivity issues detected"
    fi
    
    echo ""
    if [[ "$issues_found" == true ]]; then
        return 1
    else
        return 0
    fi
}

# Function to identify broken local repositories
identify_broken_repositories() {
    echo -e "${BLUE}=== Identifying Broken Local Repositories ===${NC}"
    
    local broken_repos=()
    
    # First check APT output for broken repositories reported by APT itself
    if [[ -f "/tmp/apt-fix-output.txt" ]]; then
        echo "Analyzing APT update output for broken repositories..."
        local apt_broken_repos=$(grep -o "file:[^ ]*" /tmp/apt-fix-output.txt | grep -o "/[^[:space:]]*" | sort -u)
        if [[ -n "$apt_broken_repos" ]]; then
            echo "APT reported broken local repositories:"
            while IFS= read -r repo_path; do
                if [[ -n "$repo_path" ]]; then
                    echo -e "${RED}✗ APT-reported broken repository: $repo_path${NC}"
                    broken_repos+=("APT-DETECTED:deb file:$repo_path /")
                    log_message "ERROR" "APT-reported broken repository: $repo_path"
                fi
            done <<< "$apt_broken_repos"
            echo ""
        fi
    fi
    
    # Check sources.list for file:// repositories
    local file_repos=$(grep -E "^[[:space:]]*deb[[:space:]]+file:" /etc/apt/sources.list 2>/dev/null || true)
    if [[ -n "$file_repos" ]]; then
        echo "Local repositories found in /etc/apt/sources.list:"
        echo "$file_repos"
        echo ""
        
        # Check if the directories exist
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local repo_path=$(echo "$line" | sed 's/^[[:space:]]*deb[[:space:]]\+file:\([^ ]*\).*/\1/')
                if [[ ! -d "$repo_path" || ! -f "$repo_path/Release" ]]; then
                    echo -e "${RED}✗ Broken local repository: $repo_path${NC}"
                    broken_repos+=("/etc/apt/sources.list:$line")
                    log_message "ERROR" "Broken local repository found: $repo_path"
                else
                    echo -e "${GREEN}✓ Valid local repository: $repo_path${NC}"
                fi
            fi
        done <<< "$file_repos"
    fi
    
    # Check sources.list.d for file:// repositories
    if [[ -d "/etc/apt/sources.list.d" ]]; then
        local sources_d_files=$(find /etc/apt/sources.list.d -name "*.list" -type f 2>/dev/null)
        for file in $sources_d_files; do
            local file_repos_d=$(grep -E "^[[:space:]]*deb[[:space:]]+file:" "$file" 2>/dev/null || true)
            if [[ -n "$file_repos_d" ]]; then
                echo "Local repositories found in $file:"
                echo "$file_repos_d"
                
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        local repo_path=$(echo "$line" | sed 's/^[[:space:]]*deb[[:space:]]\+file:\([^ ]*\).*/\1/')
                        if [[ ! -d "$repo_path" || ! -f "$repo_path/Release" ]]; then
                            echo -e "${RED}✗ Broken local repository in $file: $repo_path${NC}"
                            broken_repos+=("$file:$line")
                            log_message "ERROR" "Broken local repository found in $file: $repo_path"
                        else
                            echo -e "${GREEN}✓ Valid local repository in $file: $repo_path${NC}"
                        fi
                    fi
                done <<< "$file_repos_d"
            fi
        done
    fi
    
    if [[ ${#broken_repos[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Summary: ${#broken_repos[@]} broken local repositories found${NC}"
        return 1
    else
        echo -e "${GREEN}✓ No broken local repositories found${NC}"
        return 0
    fi
    
    echo ""
}

# Function to identify duplicate repositories
identify_duplicate_repositories() {
    echo -e "${BLUE}=== Identifying Duplicate Repository Configurations ===${NC}"
    
    local duplicates_found=false
    
    # Create temporary file with all repository entries
    local temp_repos=$(mktemp)
    
    # Collect all deb/deb-src entries from sources.list and sources.list.d
    {
        [[ -f "/etc/apt/sources.list" ]] && grep -E "^[[:space:]]*(deb|deb-src)[[:space:]]" /etc/apt/sources.list 2>/dev/null | sed 's|^|/etc/apt/sources.list:|'
        if [[ -d "/etc/apt/sources.list.d" ]]; then
            find /etc/apt/sources.list.d -name "*.list" -type f -exec grep -HE "^[[:space:]]*(deb|deb-src)[[:space:]]" {} \; 2>/dev/null
        fi
    } > "$temp_repos"
    
    # Normalize entries for comparison (remove comments, normalize whitespace)
    local normalized_repos=$(mktemp)
    while IFS= read -r line; do
        local file=$(echo "$line" | cut -d: -f1)
        local repo=$(echo "$line" | cut -d: -f2- | sed 's/#.*$//' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        if [[ -n "$repo" ]]; then
            echo "$file:$repo" >> "$normalized_repos"
        fi
    done < "$temp_repos"
    
    # Find duplicates
    local seen_repos=$(mktemp)
    local duplicate_repos=$(mktemp)
    
    while IFS= read -r line; do
        local file=$(echo "$line" | cut -d: -f1)
        local repo=$(echo "$line" | cut -d: -f2-)
        
        if grep -Fxq "$repo" "$seen_repos"; then
            echo "$line" >> "$duplicate_repos"
            duplicates_found=true
        else
            echo "$repo" >> "$seen_repos"
        fi
    done < "$normalized_repos"
    
    if [[ "$duplicates_found" == true ]]; then
        echo -e "${YELLOW}⚠ Duplicate repository configurations found:${NC}"
        echo ""
        
        # Group duplicates by repository
        while IFS= read -r dup_line; do
            local dup_repo=$(echo "$dup_line" | cut -d: -f2-)
            echo "Duplicate repository: $dup_repo"
            echo "  Found in:"
            
            while IFS= read -r all_line; do
                local all_repo=$(echo "$all_line" | cut -d: -f2-)
                if [[ "$all_repo" == "$dup_repo" ]]; then
                    local all_file=$(echo "$all_line" | cut -d: -f1)
                    echo "    - $all_file"
                fi
            done < "$normalized_repos"
            echo ""
        done < "$duplicate_repos" | sort -u
        
        log_message "WARN" "Duplicate repository configurations found"
    else
        echo -e "${GREEN}✓ No duplicate repository configurations found${NC}"
    fi
    
    # Cleanup
    rm -f "$temp_repos" "$normalized_repos" "$seen_repos" "$duplicate_repos"
    
    echo ""
    if [[ "$duplicates_found" == true ]]; then
        return 1
    else
        return 0
    fi
}

# Function to fix broken local repositories
fix_broken_repositories() {
    echo -e "${BLUE}=== Fixing Broken Local Repositories ===${NC}"
    
    if confirm_action "Remove or comment out broken local repositories"; then
        log_message "INFO" "Starting broken repository cleanup"
        
        local repos_fixed=0
        
        # Get list of broken repositories from previous identification
        local broken_repos=()
        
        # Re-run identification to get current broken repos list
        echo "Re-identifying broken repositories for fixing..."
        
        # Check APT output for broken repositories
        if [[ -f "/tmp/apt-fix-output.txt" ]]; then
            local apt_broken_repos=$(grep -o "file:[^ ]*" /tmp/apt-fix-output.txt | grep -o "/[^[:space:]]*" | sort -u)
            if [[ -n "$apt_broken_repos" ]]; then
                while IFS= read -r repo_path; do
                    if [[ -n "$repo_path" ]]; then
                        broken_repos+=("APT-DETECTED:$repo_path")
                    fi
                done <<< "$apt_broken_repos"
            fi
        fi
        
        # Check sources.list for file:// repositories
        local file_repos=$(grep -E "^[[:space:]]*deb[[:space:]]+file:" /etc/apt/sources.list 2>/dev/null || true)
        if [[ -n "$file_repos" ]]; then
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    local repo_path=$(echo "$line" | sed 's/^[[:space:]]*deb[[:space:]]\+file:\([^ ]*\).*/\1/')
                    if [[ ! -d "$repo_path" || ! -f "$repo_path/Release" ]]; then
                        broken_repos+=("/etc/apt/sources.list:$line")
                    fi
                fi
            done <<< "$file_repos"
        fi
        
        # Fix broken repositories in sources.list
        if [[ -f "/etc/apt/sources.list" ]]; then
            local temp_sources=$(mktemp)
            local fixed_sources=false
            
            while IFS= read -r line; do
                local should_disable=false
                local disable_reason=""
                
                # Check if this line matches any broken repository
                for broken_repo in "${broken_repos[@]}"; do
                    if [[ "$broken_repo" =~ ^APT-DETECTED: ]]; then
                        local broken_path=$(echo "$broken_repo" | sed 's/APT-DETECTED://')
                        if [[ "$line" =~ file:$broken_path ]]; then
                            should_disable=true
                            disable_reason="APT-reported broken repository"
                            break
                        fi
                    elif [[ "$broken_repo" =~ ^/etc/apt/sources.list: ]]; then
                        local broken_line=$(echo "$broken_repo" | sed 's|^/etc/apt/sources.list:||')
                        if [[ "$line" == "$broken_line" ]]; then
                            should_disable=true
                            disable_reason="broken local repository"
                            break
                        fi
                    fi
                done
                
                if [[ "$should_disable" == true ]]; then
                    echo "# DISABLED by apt-fix.sh - $disable_reason: $line" >> "$temp_sources"
                    echo -e "${GREEN}✓ Commented out $disable_reason in sources.list${NC}"
                    log_message "INFO" "Commented out $disable_reason in sources.list: $line"
                    fixed_sources=true
                    ((repos_fixed++))
                else
                    echo "$line" >> "$temp_sources"
                fi
            done < "/etc/apt/sources.list"
            
            if [[ "$fixed_sources" == true ]]; then
                mv "$temp_sources" "/etc/apt/sources.list"
                chmod 644 "/etc/apt/sources.list"
            else
                rm -f "$temp_sources"
            fi
        fi
        
        # Fix broken repositories in sources.list.d
        if [[ -d "/etc/apt/sources.list.d" ]]; then
            local sources_d_files=$(find /etc/apt/sources.list.d -name "*.list" -type f 2>/dev/null)
            for file in $sources_d_files; do
                local temp_file=$(mktemp)
                local fixed_file=false
                
                while IFS= read -r line; do
                    if [[ "$line" =~ ^[[:space:]]*deb[[:space:]]+file: ]]; then
                        local repo_path=$(echo "$line" | sed 's/^[[:space:]]*deb[[:space:]]\+file:\([^ ]*\).*/\1/')
                        if [[ ! -d "$repo_path" || ! -f "$repo_path/Release" ]]; then
                            echo "# DISABLED by apt-fix.sh - broken local repository: $line" >> "$temp_file"
                            echo -e "${GREEN}✓ Commented out broken repository in $file: $repo_path${NC}"
                            log_message "INFO" "Commented out broken repository in $file: $repo_path"
                            fixed_file=true
                            ((repos_fixed++))
                        else
                            echo "$line" >> "$temp_file"
                        fi
                    else
                        echo "$line" >> "$temp_file"
                    fi
                done < "$file"
                
                if [[ "$fixed_file" == true ]]; then
                    mv "$temp_file" "$file"
                    chmod 644 "$file"
                else
                    rm -f "$temp_file"
                fi
            done
        fi
        
        echo -e "${GREEN}✓ Fixed $repos_fixed broken repositories${NC}"
        log_message "INFO" "Fixed $repos_fixed broken repositories"
        return 0
    fi
    
    return 1
}

# Function to fix duplicate repositories
fix_duplicate_repositories() {
    echo -e "${BLUE}=== Fixing Duplicate Repository Configurations ===${NC}"
    
    echo "Strategy for fixing duplicates:"
    echo "1. Keep repositories in /etc/apt/sources.list.d/ (more specific)"
    echo "2. Comment out duplicates in /etc/apt/sources.list (general)"
    echo "3. Preserve original functionality"
    echo ""
    
    if confirm_action "Automatically resolve duplicate repository configurations"; then
        log_message "INFO" "Starting duplicate repository resolution"
        
        # Create a list of all repositories from sources.list.d
        local sourceslist_d_repos=$(mktemp)
        if [[ -d "/etc/apt/sources.list.d" ]]; then
            find /etc/apt/sources.list.d -name "*.list" -type f -exec grep -hE "^[[:space:]]*(deb|deb-src)[[:space:]]" {} \; 2>/dev/null | \
                sed 's/#.*$//' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | \
                grep -v '^$' > "$sourceslist_d_repos"
        fi
        
        # Process sources.list to comment out duplicates
        if [[ -f "/etc/apt/sources.list" && -s "$sourceslist_d_repos" ]]; then
            local temp_sources=$(mktemp)
            local duplicates_fixed=0
            
            while IFS= read -r line; do
                if [[ "$line" =~ ^[[:space:]]*(deb|deb-src)[[:space:]] ]]; then
                    local normalized_line=$(echo "$line" | sed 's/#.*$//' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
                    
                    if [[ -n "$normalized_line" ]] && grep -Fxq "$normalized_line" "$sourceslist_d_repos"; then
                        echo "# DISABLED by apt-fix.sh - duplicate of sources.list.d entry: $line" >> "$temp_sources"
                        echo -e "${GREEN}✓ Commented out duplicate in sources.list: $normalized_line${NC}"
                        log_message "INFO" "Commented out duplicate in sources.list: $normalized_line"
                        ((duplicates_fixed++))
                    else
                        echo "$line" >> "$temp_sources"
                    fi
                else
                    echo "$line" >> "$temp_sources"
                fi
            done < "/etc/apt/sources.list"
            
            if [[ $duplicates_fixed -gt 0 ]]; then
                mv "$temp_sources" "/etc/apt/sources.list"
                chmod 644 "/etc/apt/sources.list"
                echo -e "${GREEN}✓ Fixed $duplicates_fixed duplicate repositories${NC}"
                log_message "INFO" "Fixed $duplicates_fixed duplicate repositories"
            else
                rm -f "$temp_sources"
                echo -e "${GREEN}✓ No duplicates found to fix${NC}"
            fi
        fi
        
        rm -f "$sourceslist_d_repos"
        return 0
    fi
    
    return 1
}

# Function to clean APT cache and refresh
clean_and_refresh_apt() {
    echo -e "${BLUE}=== Cleaning APT Cache and Refreshing ===${NC}"
    
    if confirm_action "Clean APT cache and refresh package lists"; then
        log_message "INFO" "Starting APT cleanup and refresh"
        
        # Clean APT cache
        echo "Cleaning APT cache..."
        apt clean
        echo -e "${GREEN}✓ APT cache cleaned${NC}"
        
        # Remove partial downloads
        echo "Removing partial downloads..."
        rm -rf /var/lib/apt/lists/partial/*
        echo -e "${GREEN}✓ Partial downloads removed${NC}"
        
        # Update package lists
        echo "Updating package lists..."
        if apt update; then
            echo -e "${GREEN}✓ Package lists updated successfully${NC}"
            log_message "INFO" "APT update completed successfully"
            return 0
        else
            echo -e "${RED}✗ Failed to update package lists${NC}"
            log_message "ERROR" "APT update failed after cleanup"
            return 1
        fi
    fi
    
    return 1
}

# Function to test APT functionality
test_apt_functionality() {
    echo -e "${BLUE}=== Testing APT Functionality ===${NC}"
    
    # Test APT update
    echo "Testing APT update..."
    local update_output=$(apt update 2>&1)
    local update_exit_code=$?
    
    if [[ $update_exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ APT update successful${NC}"
        log_message "INFO" "APT update test successful"
    else
        echo -e "${RED}✗ APT update failed${NC}"
        echo "Error output:"
        echo "$update_output"
        log_message "ERROR" "APT update test failed"
        return 1
    fi
    
    # Test APT cache search (non-invasive test)
    echo "Testing APT search functionality..."
    if apt-cache search "proxmox" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ APT search functionality working${NC}"
        log_message "INFO" "APT search test successful"
    else
        echo -e "${YELLOW}⚠ APT search test inconclusive${NC}"
        log_message "WARN" "APT search test inconclusive"
    fi
    
    # Check for remaining warnings
    echo "Checking for remaining warnings..."
    local warnings=$(echo "$update_output" | grep -i "warning\|configured multiple times" | wc -l)
    if [[ $warnings -eq 0 ]]; then
        echo -e "${GREEN}✓ No warnings in APT output${NC}"
    else
        echo -e "${YELLOW}⚠ $warnings warning(s) still present${NC}"
        echo "Remaining warnings:"
        echo "$update_output" | grep -i "warning\|configured multiple times"
    fi
    
    echo ""
    return 0
}

# Function to create repair report
create_repair_report() {
    local report_file="/tmp/apt-fix-report.txt"
    
    echo -e "${BLUE}=== Generating APT Repair Report ===${NC}"
    
    {
        echo "Proxmox APT Repository Fix Report"
        echo "Generated: $(date)"
        echo "==============================="
        echo ""
        
        echo "SYSTEM INFORMATION:"
        if command -v pveversion &> /dev/null; then
            echo "System: Proxmox Virtual Environment"
            pveversion
        else
            echo "System: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
        fi
        echo "APT Version: $(apt --version 2>/dev/null || echo 'Not available')"
        echo ""
        
        echo "REPAIR ACTIONS PERFORMED:"
        if [[ -f "$LOG_FILE" ]]; then
            grep "INFO" "$LOG_FILE" | tail -20
        fi
        echo ""
        
        echo "CURRENT APT STATUS:"
        echo "Latest APT update test:"
        apt update 2>&1 | head -20
        echo ""
        
        echo "REPOSITORY CONFIGURATION:"
        echo "Active repositories in /etc/apt/sources.list:"
        grep -E "^[[:space:]]*(deb|deb-src)" /etc/apt/sources.list 2>/dev/null | head -10
        echo ""
        echo "Active repositories in /etc/apt/sources.list.d/:"
        find /etc/apt/sources.list.d -name "*.list" -exec grep -HE "^[[:space:]]*(deb|deb-src)" {} \; 2>/dev/null | head -10
        echo ""
        
        echo "BACKUP LOCATION:"
        echo "Configuration backups saved to: $BACKUP_DIR"
        ls -la "$BACKUP_DIR" 2>/dev/null || echo "No backups created"
        echo ""
        
        echo "RECOMMENDATIONS:"
        echo "1. Monitor APT operations for any remaining issues"
        echo "2. Run 'apt update' periodically to ensure continued functionality"
        echo "3. Keep backups until system stability is confirmed"
        echo "4. Consider removing unused repository entries"
        echo ""
        
    } > "$report_file"
    
    echo "APT repair report saved to: $report_file"
    echo ""
}

# Interactive mode function
interactive_mode() {
    echo -e "${CYAN}=== Interactive APT Fix Mode ===${NC}"
    echo ""
    
    echo "What would you like to do?"
    echo "1. Check APT repository health"
    echo "2. Fix broken local repositories"
    echo "3. Fix duplicate repository configurations"
    echo "4. Clean APT cache and refresh"
    echo "5. Run complete APT diagnosis and repair"
    echo "6. Test APT functionality only"
    echo "7. Exit"
    echo ""
    
    echo -n "Enter your choice (1-7): "
    read -r choice
    
    case "$choice" in
        1) 
            check_apt_repositories
            identify_broken_repositories
            identify_duplicate_repositories
            ;;
        2) 
            identify_broken_repositories
            fix_broken_repositories
            ;;
        3) 
            identify_duplicate_repositories
            fix_duplicate_repositories
            ;;
        4) 
            clean_and_refresh_apt
            ;;
        5) 
            echo -e "${CYAN}Running complete APT diagnosis and repair...${NC}"
            create_backups
            echo ""
            echo "Step 1: Checking and fixing broken repositories..."
            identify_broken_repositories
            fix_broken_repositories
            echo ""
            echo "Step 2: Checking and fixing duplicate repositories..."
            identify_duplicate_repositories
            fix_duplicate_repositories
            echo ""
            echo "Step 3: Cleaning APT cache and refreshing..."
            clean_and_refresh_apt
            echo ""
            echo "Step 4: Testing final functionality..."
            test_apt_functionality
            ;;
        6) 
            test_apt_functionality
            ;;
        7) 
            echo "Exiting..."
            exit 0
            ;;
        *) 
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
}

# Main function
main() {
    echo -e "${CYAN}=== Proxmox APT Repository Fix ===${NC}"
    echo ""
    
    # Check if running as root
    check_root
    
    # Create log file
    touch "$LOG_FILE"
    log_message "INFO" "APT fix script started"
    
    # Show system overview
    display_system_overview
    
    # Run interactive mode or specific operation
    if [[ "$1" == "interactive" || "$1" == "" ]]; then
        interactive_mode
    elif [[ "$1" == "check" ]]; then
        check_apt_repositories
        identify_broken_repositories
        identify_duplicate_repositories
    elif [[ "$1" == "fix" ]]; then
        echo -e "${CYAN}Running automatic APT fix...${NC}"
        create_backups
        echo ""
        echo "Step 1: Checking and fixing broken repositories..."
        identify_broken_repositories
        fix_broken_repositories
        echo ""
        echo "Step 2: Checking and fixing duplicate repositories..."
        identify_duplicate_repositories
        fix_duplicate_repositories
        echo ""
        echo "Step 3: Cleaning APT cache and refreshing..."
        clean_and_refresh_apt
        echo ""
        echo "Step 4: Testing final functionality..."
        test_apt_functionality
    elif [[ "$1" == "test" ]]; then
        test_apt_functionality
    else
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use 'interactive', 'check', 'fix', 'test', or run without arguments for interactive mode"
        exit 1
    fi
    
    # Generate final report
    create_repair_report
    
    echo -e "${GREEN}APT repository fix completed!${NC}"
    echo "Check log file: $LOG_FILE"
    
    log_message "INFO" "APT fix script completed"
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [mode]"
    echo ""
    echo "Proxmox APT Repository Fix Script"
    echo "Diagnoses and fixes common APT repository issues"
    echo ""
    echo "Modes:"
    echo "  (no args)     - Interactive mode with menu"
    echo "  interactive   - Interactive mode with menu"
    echo "  check         - Check repository health only"
    echo "  fix           - Automatically fix all detected issues"
    echo "  test          - Test APT functionality only"
    echo ""
    echo "Common issues resolved:"
    echo "  • Broken local repositories (file:// URLs)"
    echo "  • Duplicate repository configurations"
    echo "  • Corrupted APT cache"
    echo "  • Invalid repository entries"
    echo ""
    echo "Safety features:"
    echo "  • Automatic configuration backups"
    echo "  • Non-destructive fixes (comments out broken entries)"
    echo "  • Detailed logging and reporting"
    echo "  • User confirmation for major changes"
    echo ""
    echo "Examples:"
    echo "  $0                  # Interactive mode"
    echo "  $0 check            # Check repository health"
    echo "  $0 fix              # Automatically fix all issues"
    echo "  $0 test             # Test APT functionality"
    exit 0
fi

# Run main function
main "$@"
