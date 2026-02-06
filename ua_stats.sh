#!/bin/bash

# Configuration
LOG_FILES="*.access.log"
TOP_N=10

# --------------------------------------------------
# 1. Extract Time Frame
# --------------------------------------------------
# Get the list of files to identify the first and last log files
SORTED_FILES=$(ls $LOG_FILES 2>/dev/null | sort)

if [ -z "$SORTED_FILES" ]; then
    echo "No log files found matching $LOG_FILES"
    exit 1
fi

# Pick the first and last file from the sorted list
FIRST_FILE=$(echo "$SORTED_FILES" | head -n 1)
LAST_FILE=$(echo "$SORTED_FILES" | tail -n 1)

# Extract timestamp from the very first line of the first file
# Format expected: [06/Feb/2026:10:51:05 +0000] -> we grab content inside []
START_TIME=$(head -n 1 "$FIRST_FILE" | awk -F'[][]' '{print $2}')

# Extract timestamp from the very last line of the last file
END_TIME=$(tail -n 1 "$LAST_FILE" | awk -F'[][]' '{print $2}')

echo "Processing logs..."
echo "--------------------------------------------------"
echo "Time Frame: $START_TIME -- $END_TIME"
echo "--------------------------------------------------"
printf "%-40s | %s\n" "User Agent" "Count"
echo "--------------------------------------------------"

# --------------------------------------------------
# 2. Analyze User Agents
# --------------------------------------------------
# 1. awk extracts the 6th field (User Agent) from the logs.
# 2. sed cleans the User Agent string (Order matters!):
#    - Rule 1: Extract "compatible; BotName/1.0" (e.g., Pinterest, Google)
#    - Rule 2: Extract "Photon/1.0" or similar specific tools
#    - Rule 3: Extract any "NameBot/1.0" pattern found elsewhere
#    - Rule 4: Group Browsers (Chrome, Firefox, Safari, etc.)
# 3. sort | uniq -c counts them.
# 4. sort -nr puts highest count first.
# 5. The final awk formats it into "Agent | Count" table.

awk -F'"' '$6!="" && $6!="-" {print $6}' $LOG_FILES | \
sed -E '
  s/.*compatible; ([a-zA-Z0-9._-]+\/[0-9.]+).*/\1/; t end
  s/.*(Photon\/[0-9.]+).*/\1/; t end
  s/.* ([a-zA-Z0-9-]*[Bb]ot\/[0-9.]+).*/\1/; t end
  s/.*Chrome.*/Chrome (Browser)/; t end
  s/.*Firefox.*/Firefox (Browser)/; t end
  s/.*Safari.*/Safari (Browser)/; t end
  s/.*Edg.*/Edge (Browser)/; t end
  s/^([a-zA-Z0-9]+).*/\1/; t end
  :end
' | \
sort | uniq -c | sort -nr | head -n $TOP_N | \
awk '{
    count = $1; 
    $1 = ""; 
    sub(/^ /, "", $0); 
    printf "%-40s | %s\n", $0, count
}'
