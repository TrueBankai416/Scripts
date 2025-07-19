#!/bin/bash
set -e

# Parse command line arguments
LIMIT=10
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--limit)
            LIMIT="$2"
            shift 2
            ;;
        -l=*|--limit=*)
            LIMIT="${1#*=}"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-l|--limit NUMBER]"
            echo "  -l, --limit NUMBER    Number of background jobs to display (default: 10)"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

echo "Nextcloud Background Jobs Cleanup Script"
echo "========================================"

# Load environment variables from .env file
if [ -f .env ]; then
    echo "Loading configuration from .env file..."
    # Parse .env file safely, only extracting valid variable assignments
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Only process lines that look like valid variable assignments
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            export "$line"
        fi
    done < .env
else
    echo "Warning: .env file not found. Please ensure you're running this from the directory containing your .env file."
    exit 1
fi

# Function to run commands in the nextcloud container
run_in_container() {
    docker exec -u www-data nextcloud "$@"
}

# Function to run database commands
run_db_command() {
    if [ -z "$MYSQL_PASSWORD" ]; then
        echo "Error: MYSQL_PASSWORD not found in .env file"
        exit 1
    fi
    docker exec -i mariadb mysql -u "${MYSQL_USER:-nextcloud}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE:-nextcloud}" -h "${MYSQL_HOST:-mariadb}" -e "$1"
}

# Check if containers are running
if ! docker ps | grep -q "nextcloud"; then
    echo "Error: Nextcloud container is not running!"
    exit 1
fi

if ! docker ps | grep -q "mariadb"; then
    echo "Error: MariaDB container is not running!"
    exit 1
fi

echo "Checking current background jobs status (showing up to $LIMIT jobs)..."
# Try different command variations as they vary between Nextcloud versions
run_in_container php occ background-job:list --limit "$LIMIT" 2>/dev/null || \
run_in_container php occ background:job:list --limit "$LIMIT" 2>/dev/null || \
echo "Note: Unable to list background jobs - command format may vary by Nextcloud version"

echo ""
echo "Counting stuck jobs (jobs with timestamp 1970-01-01 or 0)..."
echo "Note: This scans ALL jobs in the database, not just the $LIMIT displayed above."

# Count stuck jobs
STUCK_COUNT=$(run_db_command "SELECT COUNT(*) as count FROM oc_jobs WHERE last_run = 0 OR last_run < 946684800;" | tail -n1)
echo "Found $STUCK_COUNT stuck jobs (out of total database scan)"

if [ "$STUCK_COUNT" -gt 0 ]; then
    echo ""
    echo "WARNING: This will delete $STUCK_COUNT background jobs from the database."
    echo "This action cannot be undone!"
    echo ""
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Cleaning up stuck jobs in batches of 1000..."
        
        while true; do
            DELETED=$(run_db_command "DELETE FROM oc_jobs WHERE (last_run = 0 OR last_run < 946684800) LIMIT 1000; SELECT ROW_COUNT();" | tail -n1)
            
            if [ "$DELETED" -eq 0 ]; then
                break
            fi
            
            echo "Deleted $DELETED jobs..."
            sleep 1
        done
        
        echo "Cleanup completed!"
        
        # Reset the background job system to use cron
        echo "Setting background job system to use cron..."
        run_in_container php occ background:cron || echo "Note: background:cron command may not exist in your Nextcloud version - this is OK."
        
        echo "Testing by running cron.php directly..."
        run_in_container php /var/www/html/cron.php
        
        echo ""
        echo "Cleanup completed successfully!"
        echo "The cron system should now work properly."
    else
        echo "Cleanup cancelled."
    fi
else
    echo "No stuck jobs found. Your background job system appears to be healthy."
fi

echo ""
echo "Current status:"
run_in_container php occ status
