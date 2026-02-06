#!/bin/bash

# Load duplicity config for S3 credentials
if [ -f /root/.duplicity ]; then
    source /root/.duplicity
else
    echo "Error: /root/.duplicity not found. Cannot load S3 credentials."
    exit 1
fi

# Function to fetch available backups
list_backups() {
    # Using /dev/tty ensures 'read' works when script is executed via wget/curl
    echo -n "Enter the app name (e.g., gtmekqazxd): "
    read app_name < /dev/tty

    if [[ -z "$app_name" ]]; then
        echo "App name cannot be empty."
        exit 1
    fi

    echo "Fetching available backups for $app_name..."
    # Capture output and clean potential non-breaking spaces or ANSI codes
    raw_output=$(/var/cw/scripts/bash/duplicity_restore.sh --src "$app_name" -c 2>&1)
    backup_dates=$(echo "$raw_output" | sed 's/[[:space:]]/ /g' | grep -v '^$')

    echo "------------------------------------------------"
    echo "Available backups for $app_name:"
    echo "$backup_dates"
    echo "------------------------------------------------"

    # Validation: Check for month and year pattern (2025, 2026, etc.)
    if [[ -z "$backup_dates" || ! "$backup_dates" =~ [A-Za-z]{3}\ [0-9]{4} ]]; then
        echo "No valid backups found for $app_name. Exiting."
        exit 1
    fi

    echo "Enter the backup date exactly as shown above:"
    echo "(Example: 6 Feb 2026  10:28:15)"
    read backup_date < /dev/tty
}

# Function to handle file path and target names
get_restore_path() {
    echo -n "Enter the relative file/folder path to restore (e.g., public_html/index.php): "
    read FILE_PATH < /dev/tty

    if [[ -z "$FILE_PATH" ]]; then
        echo "File path cannot be empty."
        exit 1
    fi

    # Extract just the last folder/file name for the destination
    RESTORE_NAME=$(basename "$FILE_PATH")
    DEST_PATH="$(pwd)/$RESTORE_NAME"
}

# Function to convert date format to ISO 8601
convert_date_format() {
    formatted_date=$(date -d "$backup_date" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
    
    if [ -z "$formatted_date" ]; then
        echo "Error: Invalid date format. Please copy and paste correctly."
        exit 1
    fi
}

# Function to perform the actual duplicity restore
restore_specific_path() {
    echo -e "\n🔄 Restoring \"$FILE_PATH\" to \"$DEST_PATH\""
    echo "Source Time: $formatted_date"
    echo "************************************************"

    duplicity restore \
        --file-to-restore "$FILE_PATH" \
        --no-encryption \
        --no-print-statistics \
        --s3-use-new-style \
        -t "$formatted_date" \
        "$S3_url/apps/$app_name" \
        "$DEST_PATH"

    # Result check
    if [[ $? -eq 0 && -e "$DEST_PATH" ]]; then
        echo -e "\n✅ Restore complete. Saved to: $DEST_PATH"
    else
        echo -e "\n❌ Restore failed or file/folder not found."
        exit 1
    fi
}

# Function to fix permissions for the restored file/folder
fix_permissions() {
    if [ -e "$DEST_PATH" ]; then
        echo "************************************************"
        echo "Updating ownership and permissions for $RESTORE_NAME..."
        
        # Change ownership to app_name:www-data
        chown -R "$app_name":www-data "$DEST_PATH"
        
        # Apply standard permissions (775 for dirs, 664 for files)
        if [ -d "$DEST_PATH" ]; then
            find "$DEST_PATH" -type d -exec chmod 775 {} +
            find "$DEST_PATH" -type f -exec chmod 664 {} +
        else
            chmod 664 "$DEST_PATH"
        fi
        
        echo "Permissions updated to $app_name:www-data."
        echo "************************************************"
    fi
}

# Main execution flow
list_backups
get_restore_path
convert_date_format
restore_specific_path
fix_permissions
