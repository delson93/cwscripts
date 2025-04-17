#!/bin/bash

# Load duplicity config
source /root/.duplicity

# Ask for app name
read -p "Enter the app name (e.g., gtmekqazxd): " APP_NAME

# Show available backups using official Cloudways helper
echo -e "\nAvailable backups for $APP_NAME:"
/var/cw/scripts/bash/duplicity_restore.sh --src "$APP_NAME" -c

# Ask user to enter date from the list shown
read -p $'\nEnter the backup date and time (e.g., 13 Apr 2025  06:40:41): ' BACKUP_DATE

# Ask user for file/folder path
read -p "Enter the relative file/folder path to restore (e.g., public_html/index.js or public_html/wp-includes): " FILE_PATH

# Extract just the last folder/file name
RESTORE_NAME=$(basename "$FILE_PATH")
DEST_PATH="$(pwd)/$RESTORE_NAME"

# Convert to ISO 8601 format
RESTORE_DATE=$(date -d "$BACKUP_DATE" +"%Y-%m-%dT%H:%M:%S")

echo -e "\n🔄 Restoring \"$FILE_PATH\" to \"$DEST_PATH\""

# Actual restore
duplicity restore \
    --file-to-restore "$FILE_PATH" \
    --no-encryption \
    --no-print-statistics \
    --s3-use-new-style \
    -t "$RESTORE_DATE" \
    "$S3_url/apps/$APP_NAME" \
    "$DEST_PATH"

# Result check
if [[ $? -eq 0 && -e "$DEST_PATH" ]]; then
  echo -e "\n✅ Restore complete. Saved to: $DEST_PATH"
else
  echo -e "\n❌ Restore failed or file/folder not found at: $DEST_PATH"
fi

