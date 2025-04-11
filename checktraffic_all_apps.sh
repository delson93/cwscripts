#!/bin/bash

# Output file
LOGFILE="log.txt"

# Clear the log file
> "$LOGFILE"

# Grab app names: look for lines that start with a │ and have a name in the first column
apm | grep '^│' | awk -F '│' '{gsub(/ /, "", $2); if(length($2)==10) print $2}' > apps.txt

# Loop through apps and collect traffic data
while read -r APP; do
    echo "===== Traffic for $APP =====" >> "$LOGFILE"
    apm -s "$APP" traffic -l 1h >> "$LOGFILE" 2>&1
    echo "" >> "$LOGFILE"
done < apps.txt

rm -f apps.txt

echo "Traffic data saved to $LOGFILE"

