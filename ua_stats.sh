#!/bin/bash

# Configuration
LOG_FILES="*.access.log"
TOP_N=10

echo "Processing logs..."
echo "--------------------------------------------------"
printf "%-40s | %s\n" "User Agent" "Count"
echo "--------------------------------------------------"

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
