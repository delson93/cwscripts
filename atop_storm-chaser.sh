#!/bin/bash

# Colors
BRED='\033[1;31m' 
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' 

cd /var/log/atop 2>/dev/null || exit 1

clear
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}      STORM-CHASER v17.0: TIME-STAMPED AUDIT        ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. File Selection
FILES=($(ls -1 atop_2* | sort -r))
for i in "${!FILES[@]}"; do printf "%3d) %s\n" "$((i+1))" "${FILES[$i]}"; done
read -p "Select file number: " FILE_INDEX
SELECTED_FILE=${FILES[$((FILE_INDEX-1))]}
LOG_DATE=$(echo $SELECTED_FILE | grep -oE '[0-9]{8}')

# 2. Time Selection
read -p "Start Time (HH:MM): " START_HHMM
read -p "End Time   (HH:MM): " END_HHMM
START_PARAM="${LOG_DATE}${START_HHMM//:/}"
END_PARAM="${LOG_DATE}${END_HHMM//:/}"

echo -e "\n${YELLOW}Mapping wall-clock time to disk spikes...${NC}"

echo -e "\n${BLUE}🔥 TIME-STAMPED DISK EVENTS 🔥${NC}"
echo -e "${BLUE}================================================================================${NC}"
printf "%-10s | %-18s | %-10s | %-10s | %-6s\n" "CLOCK TIME" "COMMAND" "READ (KB)" "WRITE (KB)" "DSK %"
echo "--------------------------------------------------------------------------------"

# We use awk to keep track of the last seen Time header
atop -r "$SELECTED_FILE" -b "$START_PARAM" -e "$END_PARAM" -d | awk -v yellow="$YELLOW" -v green="$GREEN" -v nc="$NC" '
    # Extract HH:MM:SS from the ATOP header line
    /ATOP - / { 
        for(i=1; i<=NF; i++) {
            if ($i ~ /[0-9]{2}:[0-9]{2}:[0-9]{2}/) {
                current_time = $i
            }
        }
    }
    
    # Identify the top process line (starts with a PID)
    /^[ ]*[0-9]+/ {
        # Only print the first process found after a new timestamp header
        if (current_time != last_printed_time && ($3 != "0K" || $4 != "0K")) {
            printf "%-10s | %-18s | %-10s | %-10s | %-6s\n", yellow current_time nc, green $NF nc, $3, $4, $6;
            last_printed_time = current_time;
        }
    }
'

echo -e "${BLUE}================================================================================${NC}"
