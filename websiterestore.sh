#!/bin/bash

# Prompt for the app name
read -p "Enter the app name: " APP_NAME

# Fetch available backup dates
echo "Fetching available backups for $APP_NAME..."
AVAILABLE_BACKUPS=$(/var/cw/scripts/bash/duplicity_restore.sh --src "$APP_NAME" -c)

# Check if backups exist
if [ -z "$AVAILABLE_BACKUPS" ]; then
    echo "No backups found for $APP_NAME. Exiting."
    exit 1
fi

# Display available backups
echo "$AVAILABLE_BACKUPS"
echo

# Prompt for the backup date
read -p "Enter the backup date (YYYY-MM-DD format): " BACKUP_DATE

# Run the restore command
echo "Restoring backup for $APP_NAME from $BACKUP_DATE..."
/var/cw/scripts/bash/duplicity_restore.sh --src "$APP_NAME" -v 4 -w --dst './' --time "$BACKUP_DATE"

echo "Backup restoration complete!"

