#!/bin/bash

# Function to fetch available backups
list_backups() {
    echo "Enter the app name:"
    read app_name

    echo "Fetching available backups for $app_name..."
    backup_dates=$(/var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -c 2>&1)

    # Debugging: Show raw output
    echo "Raw output received:"
    echo "$backup_dates"

    # Check if backups are found
    if [[ -z "$backup_dates" || ! "$backup_dates" =~ [0-9]{1,2}\ [A-Za-z]{3}\ 2025 ]]; then
        echo "No backups found for $app_name. Exiting."
        exit 1
    fi

    echo "Available backups:"
    echo "$backup_dates"

    echo "Enter the backup date exactly as shown (e.g., '19 Mar 2025 06:40:40'):"
    read backup_date
}

# Function to convert date format to required format (YYYY-MM-DDTHH:MM:SS)
convert_date_format() {
    formatted_date=$(date -d "$backup_date" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
    if [ -z "$formatted_date" ]; then
        echo "Invalid date format. Please enter the correct date."
        exit 1
    fi
}

# Function to restore backup
restore_backup() {
    local backup_type=$1  # "mysql" or "web"
    
    echo "Restoring $backup_type backup for $app_name from $formatted_date..."
    if [[ "$backup_type" == "mysql" ]]; then
        /var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -v 4 -d --dst './' --time "$formatted_date"
    else
        /var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -v 4 -w --dst './' --time "$formatted_date"
    fi
    echo "$backup_type Backup restoration completed."
}

# Execute the functions once and use the same details for both restores
list_backups
convert_date_format
restore_backup "mysql"
restore_backup "web"

