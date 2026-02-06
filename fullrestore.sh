#!/bin/bash

# Function to fetch available backups
list_backups() {
    echo "Enter the app name:"
    # Use /dev/tty to ensure read works even when piped/redirected
    read app_name < /dev/tty

    echo "Fetching available backups for $app_name..."
    backup_dates=$(/var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -c 2>&1)

    # Debugging: Show raw output
    echo "----------------------------"
    echo "Raw output received:"
    echo "$backup_dates"
    echo "----------------------------"

    # Check if backups are found (Updated regex to handle any year 2000-2099)
    if [[ -z "$backup_dates" || ! "$backup_dates" =~ [0-9]{1,2}\ [A-Za-z]{3}\ 20[0-9]{2} ]]; then
        echo "Error: No valid backup dates found in the output. Exiting."
        exit 1
    fi

    echo "Available backups list loaded."
    echo "Enter the backup date exactly as shown (e.g., '6 Feb 2026 10:28:15'):"
    read backup_date < /dev/tty
}

# Function to convert date format
convert_date_format() {
    # We use date -d to parse the human-readable string into ISO 8601
    formatted_date=$(date -d "$backup_date" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
    
    if [ -z "$formatted_date" ]; then
        echo "Error: Could not parse '$backup_date'. Please ensure it matches the format shown above."
        exit 1
    fi
    echo "Target format: $formatted_date"
}

# Function to restore backup
restore_backup() {
    local backup_type=$1  # "mysql" or "web"
    
    echo "--- Starting $backup_type restore ---"
    if [[ "$backup_type" == "mysql" ]]; then
        /var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -v 4 -d --dst './' --time "$formatted_date"
    else
        /var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -v 4 -w --dst './' --time "$formatted_date"
    fi
    echo "--- $backup_type restoration finished ---"
}

# Main Execution
list_backups
convert_date_format
restore_backup "mysql"
restore_backup "web"
