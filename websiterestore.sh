#!/bin/bash

# Function to display available backups and prompt user for a date
list_backups() {
    echo "Enter the app name:"
    read app_name
    echo "Fetching available backups for $app_name..."

    # Fetch available backups
    backup_dates=$(/var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -c 2>&1)

    # Debug: Show raw output
    echo "DEBUG: Raw output received:"
    echo "$backup_dates"

    # Check if output is empty or does not match expected date pattern
    if [[ -z "$backup_dates" || ! "$backup_dates" =~ [0-9]{1,2}\ [A-Za-z]{3}\ 2025 ]]; then
        echo "No backups found for $app_name. Exiting."
        exit 1
    fi

    echo "Available backups:"
    echo "$backup_dates"

    echo "Enter the backup date exactly as shown (e.g., '19 Mar 2025 06:40:40'):"
    read backup_date
}

# Function to convert date format to YYYY-MM-DD
convert_date_format() {
    formatted_date=$(date -d "$backup_date" "+%Y-%m-%d" 2>/dev/null)
    if [ -z "$formatted_date" ]; then
        echo "Invalid date format. Please enter the correct date."
        exit 1
    fi
}

# Function to restore the backup
restore_backup() {
    echo "Restoring website files for $app_name from $formatted_date..."
    /var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -v 4 -w --dst './' --time "$formatted_date"
    echo "Website file restoration completed."
}

# Execute the functions
list_backups
convert_date_format
restore_backup

