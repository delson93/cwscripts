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

    # Robust Validation: Check for any 3-letter month and 4-digit year (handles 2026+)
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
    # Using full timestamp is more precise for web restores than just YYYY-MM-DD
    formatted_date=$(date -d "$backup_date" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
    
    if [ -z "$formatted_date" ]; then
        echo "Error: Invalid date format. Please copy and paste the date exactly from the list."
        exit 1
    fi
    echo "Parsed date for Duplicity: $formatted_date"
}

# Function to restore the website files
restore_backup() {
    echo "************************************************"
    echo "Restoring website files for $app_name..."
    echo "Source Time: $formatted_date"
    echo "************************************************"

    # Restoring with -w flag for web files
    /var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -v 4 -w --dst './' --time "$formatted_date"
    
    if [ $? -eq 0 ]; then
        echo "SUCCESS: Website file restoration completed."
    else
        echo "FAILURE: Website restoration encountered an error."
    fi
}

# Function to fix permissions for web folders
fix_permissions() {
    echo "************************************************"
    echo "Checking for folders to update ownership..."
    
    # Define targets to check
    targets=("public_html" "private_html")
    
    for folder in "${targets[@]}"; do
        if [ -d "$folder" ]; then
            echo "Updating ownership for '$folder' to $app_name:www-data..."
            chown -R "$app_name":www-data "$folder"
            # Ensure directories are searchable/writable and files readable
            find "$folder" -type d -exec chmod 775 {} +
            find "$folder" -type f -exec chmod 664 {} +
        fi
    done
    
    echo "Ownership and permissions update complete."
    echo "************************************************"
}

# Execute the functions
list_backups
convert_date_format
restore_backup
fix_permissions
