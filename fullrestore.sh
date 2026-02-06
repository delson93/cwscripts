#!/bin/bash

# Function to fetch available backups
list_backups() {
    # Using /dev/tty ensures 'read' works when script is executed via wget/curl
    echo -n "Enter the app name: "
    read app_name < /dev/tty

    if [[ -z "$app_name" ]]; then
        echo "App name cannot be empty."
        exit 1
    fi

    echo "Fetching available backups for $app_name..."
    # Capture output and remove empty lines
    raw_output=$(/var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -c 2>&1)
    
    # Clean the output: remove potential ANSI codes and non-breaking spaces
    backup_dates=$(echo "$raw_output" | sed 's/[[:space:]]/ /g' | grep -v '^$')

    # Debugging: Show raw output
    echo "------------------------------------------------"
    echo "Raw output received:"
    echo "$backup_dates"
    echo "------------------------------------------------"

    # Robust Validation: Check if we have at least one line containing a month and a 4-digit year
    if [[ -z "$backup_dates" || ! "$backup_dates" =~ [A-Za-z]{3}\ [0-9]{4} ]]; then
        echo "No valid backups found for $app_name. Please check the app name or backup status."
        exit 1
    fi

    echo "Available backups list loaded."
    echo "Enter the backup date exactly as shown above:"
    echo "(Example: 6 Feb 2026  10:28:15)"
    read backup_date < /dev/tty
}

# Function to convert date format to required format (YYYY-MM-DDTHH:MM:SS)
convert_date_format() {
    # Attempt to parse the date provided by the user
    formatted_date=$(date -d "$backup_date" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
    
    if [ -z "$formatted_date" ]; then
        echo "Error: Invalid date format. Please copy and paste the date exactly from the list."
        exit 1
    fi
    echo "Parsed date for Duplicity: $formatted_date"
}

# Function to restore backup
restore_backup() {
    local backup_type=$1  # "mysql" or "web"
    
    echo "************************************************"
    echo "Restoring $backup_type backup for $app_name..."
    echo "Source Time: $formatted_date"
    echo "************************************************"

    if [[ "$backup_type" == "mysql" ]]; then
        /var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -v 4 -d --dst './' --time "$formatted_date"
    else
        /var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -v 4 -w --dst './' --time "$formatted_date"
    fi
    
    if [ $? -eq 0 ]; then
        echo "SUCCESS: $backup_type backup restoration completed."
    else
        echo "FAILURE: $backup_type restoration encountered an error."
    fi
}

# Function to fix permissions for MySQL folder
fix_permissions() {
    if [ -d "mysql" ]; then
        echo "************************************************"
        echo "Updating ownership and permissions for 'mysql' directory..."
        
        # Change ownership to app_name:www-data
        chown -R "$app_name":www-data mysql/
        
        # Set file permissions to 644 inside mysql directory
        chmod -R 644 mysql/*
        
        echo "Permissions updated: $app_name:www-data (644)"
        echo "************************************************"
    fi
}

# Main script flow
list_backups
convert_date_format
restore_backup "mysql"
restore_backup "web"
fix_permissions
