#!/bin/bash

# Configuration
# Matches generic access log patterns including .gz and .1
LOG_PATTERN="*.access.log*"
TOP_N=10

# --------------------------------------------------
# 1. Identify and Sort Files (Oldest -> Newest)
# --------------------------------------------------
# We need to process files in chronological order:
# 1. *.gz files (usually access.log.30.gz is older than access.log.2.gz) -> Sort Reverse Version
# 2. *.1 files (older than main log)
# 3. *.access.log (newest)

# Get list of GZ files sorted naturally in reverse (e.g. 30.gz, 29.gz ... 2.gz)
GZ_FILES=$(ls ${LOG_PATTERN}.gz 2>/dev/null | sort -V -r)
# Get .1 file
ONE_FILE=$(ls ${LOG_PATTERN}.1 2>/dev/null)
# Get main log file (strictly ending in .log)
MAIN_FILE=$(ls *.access.log 2>/dev/null)

# Combine into a single list for processing order
ALL_FILES="$GZ_FILES $ONE_FILE $MAIN_FILE"

if [ -z "$(echo $ALL_FILES | xargs)" ]; then
    echo "No log files found matching $LOG_PATTERN"
    exit 1
fi

# --------------------------------------------------
# 2. Extract Available Time Frame
# --------------------------------------------------
get_time() {
    local file=$1
    local mode=$2 # head or tail
    local cmd="cat"
    
    # Use zcat for compressed files
    if [[ "$file" == *.gz ]]; then
        cmd="zcat"
    fi
    
    if [ "$mode" == "head" ]; then
        # First line timestamp
        $cmd "$file" 2>/dev/null | head -n 1 | awk -F'[][]' '{print $2}'
    else
        # Last line timestamp
        $cmd "$file" 2>/dev/null | tail -n 1 | awk -F'[][]' '{print $2}'
    fi
}

# Pick the very first file (Oldest) and very last file (Newest) from our sorted list
FIRST_FILE=$(echo "$ALL_FILES" | head -n 1 | awk '{print $1}')
# To get the last file, we iterate or just grab the main file if it exists
LAST_FILE=$(echo "$ALL_FILES" | fmt -1 | tail -n 1)

GLOBAL_START=$(get_time "$FIRST_FILE" "head")
GLOBAL_END=$(get_time "$LAST_FILE" "tail")

echo "========================================================"
echo "Analysing Log Files in: $PWD"
echo "Total Files Found: $(echo "$ALL_FILES" | wc -w)"
echo "Available Data: $GLOBAL_START  <-->  $GLOBAL_END"
echo "========================================================"
echo "Enter time frame to analyze (Copy-paste from above works best)."
echo "Format: dd/Mon/yyyy:HH:MM:SS"
echo "Example: 06/Feb/2026:10:00"
echo ""

read -p "Start Time: " INPUT_START
read -p "End Time:   " INPUT_END

# Defaults if empty
if [ -z "$INPUT_START" ]; then INPUT_START="01/Jan/1970"; fi
if [ -z "$INPUT_END" ]; then INPUT_END="31/Dec/2099"; fi

echo ""
echo "Processing logs... (This may take a moment for .gz files)"
echo "--------------------------------------------------"
printf "%-40s | %s\n" "User Agent" "Count"
echo "--------------------------------------------------"

# --------------------------------------------------
# 3. Stream, Filter & Analyze
# --------------------------------------------------

# Function to stream all files in valid order
stream_logs() {
    for f in $ALL_FILES; do
        [ -e "$f" ] || continue
        if [[ "$f" == *.gz ]]; then
            zcat "$f" 2>/dev/null
        else
            cat "$f" 2>/dev/null
        fi
    done
}

# Pipeline:
# 1. stream_logs: Concatenates all logs
# 2. awk (Filter): Converts timestamps to numbers and filters by User Input range
# 3. awk (Field): Extracts User Agent column
# 4. sed (Clean): Normalizes Bot/Browser names
# 5. sort/uniq: Counts top agents

stream_logs | awk -v start="$INPUT_START" -v end="$INPUT_END" '
BEGIN {
    # Map months to numbers for comparison
    m["Jan"]="01"; m["Feb"]="02"; m["Mar"]="03"; m["Apr"]="04"; m["May"]="05"; m["Jun"]="06";
    m["Jul"]="07"; m["Aug"]="08"; m["Sep"]="09"; m["Oct"]="10"; m["Nov"]="11"; m["Dec"]="12";
}

function parse_date(d_str) {
    # Input format: 06/Feb/2026:10:51:05
    split(d_str, p, "[/: ]") 
    # Returns YYYYMMDDHHMMSS (e.g. 20260206105105)
    # Pads with 0 if parts are missing (like seconds)
    return sprintf("%04d%02d%02d%02d%02d%02d", p[3], m[p[2]], p[1], p[4], p[5], p[6])
}

{
    # Log timestamp is usually field $4: [06/Feb/2026:10:51:05
    ts = $4
    gsub(/^\[/, "", ts) # Remove leading [
    
    # Convert dates to numbers once per run
    if (s_num == 0) s_num = parse_date(start)
    if (e_num == 0) e_num = parse_date(end)
    
    current_num = parse_date(ts)
    
    # Check range
    if (current_num >= s_num && current_num <= e_num) {
        print $0
    }
}' | \
awk -F'"' '$6!="" && $6!="-" {print $6}' | \
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
