#!/bin/bash

# Media Monitor Script for Linux
# Monitors movies and TV folders after Tdarr processing
# Waits 1 hour then moves files to Jellyfin folders

# Configuration - Edit these paths for your setup
MOVIES_SOURCE="/path/to/tdarr/movies"
TV_SOURCE="/path/to/tdarr/tv"
MOVIES_DEST="/path/to/jellyfin/movies"
TV_DEST="/path/to/jellyfin/tv"
DELAY_HOURS=1
LOG_FILE="/var/log/media-monitor.log"

# Advanced Configuration
DELAY_SECONDS=$((DELAY_HOURS * 3600))
MAX_RETRIES=3
RETRY_DELAY=30
SUPPORTED_EXTENSIONS=("mkv" "mp4" "avi" "mov" "wmv" "flv" "m4v" "ts" "m2ts")

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    # Also output to console with colors
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
}

# Function to check if file extension is supported
is_supported_file() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}" # Convert to lowercase
    
    for supported_ext in "${SUPPORTED_EXTENSIONS[@]}"; do
        if [[ "$ext" == "$supported_ext" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to extract movie name and year from filename
extract_movie_info() {
    local filename="$1"
    local basename="${filename%.*}"
    
    # Remove common quality indicators and convert dots to spaces
    local clean_name=$(echo "$basename" | sed -E 's/\.(bluray|web|dvd|hdtv|1080p|720p|480p|4k|hdr|x264|x265|h264|h265|remux|repack|proper|directors|cut|extended|unrated|theatrical).*//i' | tr '.' ' ')
    
    # Extract year (4 digits)
    local year=$(echo "$clean_name" | grep -oE '\b(19|20)[0-9]{2}\b' | head -1)
    
    # Remove year from name and clean up
    local movie_name=$(echo "$clean_name" | sed -E "s/\b$year\b//" | sed -E 's/^\s+|\s+$//g' | sed -E 's/\s+/ /g')
    
    # Capitalize first letter of each word
    movie_name=$(echo "$movie_name" | sed 's/\b\w/\U&/g')
    
    if [[ -n "$year" && -n "$movie_name" ]]; then
        echo "${movie_name} (${year})"
    else
        # Fallback to original name if parsing fails
        echo "$basename"
    fi
}

# Function to create directory if it doesn't exist
create_directory() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        log "INFO" "Creating directory: $dir"
        mkdir -p "$dir"
        if [[ $? -eq 0 ]]; then
            log "INFO" "Directory created successfully: $dir"
            return 0
        else
            log "ERROR" "Failed to create directory: $dir"
            return 1
        fi
    fi
    return 0
}

# Function to move file with retry logic
move_file() {
    local source="$1"
    local destination="$2"
    local retries=0
    
    while [[ $retries -lt $MAX_RETRIES ]]; do
        log "INFO" "Attempting to move file: $source -> $destination"
        
        # Check if source file still exists
        if [[ ! -f "$source" ]]; then
            log "ERROR" "Source file no longer exists: $source"
            return 1
        fi
        
        # Check if destination directory exists
        local dest_dir=$(dirname "$destination")
        if [[ ! -d "$dest_dir" ]]; then
            log "ERROR" "Destination directory does not exist: $dest_dir"
            return 1
        fi
        
        # Check if destination file already exists
        if [[ -f "$destination" ]]; then
            log "WARN" "Destination file already exists: $destination"
            local backup_dest="${destination}.backup.$(date +%s)"
            log "INFO" "Moving existing file to backup: $backup_dest"
            mv "$destination" "$backup_dest"
        fi
        
        # Perform the move
        mv "$source" "$destination"
        
        if [[ $? -eq 0 ]]; then
            log "INFO" "File moved successfully: $source -> $destination"
            return 0
        else
            retries=$((retries + 1))
            log "WARN" "Move failed (attempt $retries/$MAX_RETRIES): $source -> $destination"
            
            if [[ $retries -lt $MAX_RETRIES ]]; then
                log "INFO" "Retrying in $RETRY_DELAY seconds..."
                sleep $RETRY_DELAY
            fi
        fi
    done
    
    log "ERROR" "Failed to move file after $MAX_RETRIES attempts: $source -> $destination"
    return 1
}

# Function to process a detected file
process_file() {
    local file_path="$1"
    local source_type="$2"  # "movies" or "tv"
    
    log "INFO" "Processing $source_type file: $file_path"
    
    # Check if file is supported
    if ! is_supported_file "$file_path"; then
        log "DEBUG" "Skipping unsupported file: $file_path"
        return 0
    fi
    
    # Wait for the delay period
    log "INFO" "Waiting $DELAY_HOURS hour(s) before processing: $file_path"
    sleep $DELAY_SECONDS
    
    # Check if file still exists after delay
    if [[ ! -f "$file_path" ]]; then
        log "WARN" "File no longer exists after delay: $file_path"
        return 1
    fi
    
    local filename=$(basename "$file_path")
    local destination_dir=""
    local destination_path=""
    
    if [[ "$source_type" == "movies" ]]; then
        # Extract movie information and create subdirectory
        local movie_folder=$(extract_movie_info "$filename")
        destination_dir="$MOVIES_DEST/$movie_folder"
        destination_path="$destination_dir/$filename"
        
        log "INFO" "Movie folder name: $movie_folder"
    else
        # TV shows go directly to TV destination
        destination_dir="$TV_DEST"
        destination_path="$destination_dir/$filename"
    fi
    
    # Create destination directory
    if ! create_directory "$destination_dir"; then
        log "ERROR" "Failed to create destination directory: $destination_dir"
        return 1
    fi
    
    # Move the file
    if move_file "$file_path" "$destination_path"; then
        log "INFO" "Successfully processed $source_type file: $filename"
        return 0
    else
        log "ERROR" "Failed to process $source_type file: $filename"
        return 1
    fi
}

# Function to validate configuration
validate_config() {
    log "INFO" "Validating configuration..."
    
    # Check if inotify-tools is installed
    if ! command -v inotifywait &> /dev/null; then
        log "ERROR" "inotify-tools is not installed. Please install it with: sudo apt install inotify-tools"
        return 1
    fi
    
    # Check source directories
    if [[ ! -d "$MOVIES_SOURCE" ]]; then
        log "ERROR" "Movies source directory does not exist: $MOVIES_SOURCE"
        return 1
    fi
    
    if [[ ! -d "$TV_SOURCE" ]]; then
        log "ERROR" "TV source directory does not exist: $TV_SOURCE"
        return 1
    fi
    
    # Create destination directories if they don't exist
    if ! create_directory "$MOVIES_DEST"; then
        log "ERROR" "Failed to create movies destination directory: $MOVIES_DEST"
        return 1
    fi
    
    if ! create_directory "$TV_DEST"; then
        log "ERROR" "Failed to create TV destination directory: $TV_DEST"
        return 1
    fi
    
    log "INFO" "Configuration validation successful"
    return 0
}

# Function to handle signals
cleanup() {
    log "INFO" "Received signal, shutting down media monitor..."
    exit 0
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -c, --config            Show current configuration"
    echo "  -t, --test              Test configuration without monitoring"
    echo "  -v, --verbose           Enable verbose logging"
    echo ""
    echo "Configuration (edit script to change):"
    echo "  Movies Source: $MOVIES_SOURCE"
    echo "  TV Source: $TV_SOURCE"
    echo "  Movies Destination: $MOVIES_DEST"
    echo "  TV Destination: $TV_DEST"
    echo "  Delay: $DELAY_HOURS hour(s)"
    echo "  Log File: $LOG_FILE"
}

# Function to show current configuration
show_config() {
    echo "Current Configuration:"
    echo "====================="
    echo "Movies Source: $MOVIES_SOURCE"
    echo "TV Source: $TV_SOURCE"
    echo "Movies Destination: $MOVIES_DEST"
    echo "TV Destination: $TV_DEST"
    echo "Delay: $DELAY_HOURS hour(s) ($DELAY_SECONDS seconds)"
    echo "Log File: $LOG_FILE"
    echo "Max Retries: $MAX_RETRIES"
    echo "Retry Delay: $RETRY_DELAY seconds"
    echo "Supported Extensions: ${SUPPORTED_EXTENSIONS[*]}"
}

# Main monitoring function
start_monitoring() {
    log "INFO" "Starting media monitoring..."
    log "INFO" "Monitoring movies folder: $MOVIES_SOURCE"
    log "INFO" "Monitoring TV folder: $TV_SOURCE"
    log "INFO" "Delay before moving: $DELAY_HOURS hour(s)"
    
    # Start monitoring both directories
    inotifywait -m -r -e create,moved_to --format '%w%f %e' "$MOVIES_SOURCE" "$TV_SOURCE" | while read file_path event; do
        # Determine source type based on path
        if [[ "$file_path" == "$MOVIES_SOURCE"* ]]; then
            source_type="movies"
        elif [[ "$file_path" == "$TV_SOURCE"* ]]; then
            source_type="tv"
        else
            log "WARN" "Unknown source path: $file_path"
            continue
        fi
        
        log "INFO" "Detected new file: $file_path (event: $event)"
        
        # Process file in background to avoid blocking the monitor
        process_file "$file_path" "$source_type" &
    done
}

# Main script execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--config)
                show_config
                exit 0
                ;;
            -t|--test)
                validate_config
                exit $?
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check if running as root (recommended for system-wide monitoring)
    if [[ $EUID -ne 0 ]]; then
        log "WARN" "Not running as root. Some operations may fail."
    fi
    
    # Set up signal handlers
    trap cleanup SIGINT SIGTERM
    
    # Create log file directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Start logging
    log "INFO" "Media Monitor started (PID: $$)"
    
    # Validate configuration
    if ! validate_config; then
        log "ERROR" "Configuration validation failed. Exiting."
        exit 1
    fi
    
    # Start monitoring
    start_monitoring
}

# Run main function
main "$@"
