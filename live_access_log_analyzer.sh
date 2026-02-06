#!/bin/bash

# --- CONFIGURATION ---
ANALYSIS_DURATION=45        # Seconds to monitor
THRESHOLD_HIGH_FREQ=20      # Requests per IP to flag
LOG_FILE_PATTERN="*.access.log"

# Patterns to flag as "Bad" (Regex format)
BAD_UA_REGEX="bot|crawl|spider|scrap|python|curl|wget|libwww|Win 9x|Windows 98|MSIE 6.0|MSIE 9.0|Trident/4.0"

# Find the log file
if [ -z "$1" ]; then
    TARGET_LOG=$(ls $LOG_FILE_PATTERN 2>/dev/null | head -n 1)
else
    TARGET_LOG=$1
fi

if [ ! -f "$TARGET_LOG" ]; then
    echo "Error: Log file '$TARGET_LOG' not found."
    exit 1
fi

echo "[*] Starting live analysis on: $TARGET_LOG"
echo "[*] Duration: $ANALYSIS_DURATION seconds. Please wait..."

# Create a temporary file to store captured logs
TEMP_LOG=$(mktemp)

# Capture logs for the specified duration
timeout $ANALYSIS_DURATION tail -n 0 -f "$TARGET_LOG" > "$TEMP_LOG" 2>/dev/null

echo ""
echo "================================================================================"
echo " ANALYSIS SUMMARY"
echo "================================================================================"
printf "%-18s | %-5s | %-12s | %-12s | %s\n" "IP ADDRESS" "REQS" "STATUS" "SCORE" "NOTES"
echo "--------------------------------------------------------------------------------"

# Process the captured logs
grep -E "." "$TEMP_LOG" | awk '{print $1}' | sort | uniq -c | sort -rn | head -n 20 | while read count ip; do
    
    REASONS=""
    SCORE=0
    
    # 1. Frequency Check
    if [ "$count" -gt "$THRESHOLD_HIGH_FREQ" ]; then
        SCORE=$((SCORE + 3))
        REASONS="High Freq"
    fi
    
    # 2. Status Analysis (4xx/5xx)
    # Improved extraction: Look for the field immediately following the "METHOD PATH HTTP/1.x" block
    # In standard logs, this is the 9th field.
    ERROR_COUNT=$(grep "^$ip " "$TEMP_LOG" | awk '{print $9}' | grep -E "40[0-9]|50[0-9]" | wc -l)
    
    if [ "$count" -gt 0 ]; then
        ERROR_RATE=$(( (ERROR_COUNT * 100) / count ))
        if [ "$ERROR_RATE" -gt 30 ]; then
            SCORE=$((SCORE + 4))
            REASONS="${REASONS}${REASONS:+ | }High Errors (${ERROR_RATE}%)"
        fi
    fi
    
    # 3. User Agent Check
    UA_MATCH=$(grep "^$ip " "$TEMP_LOG" | cut -d '"' -f 6 | grep -Ei "$BAD_UA_REGEX" | head -n 1)
    if [ -n "$UA_MATCH" ]; then
        SCORE=$((SCORE + 5))
        REASONS="${REASONS}${REASONS:+ | }Bad UA: ${UA_MATCH:0:20}..."
    fi
    
    # Determine classification
    if [ "$SCORE" -ge 7 ]; then
        CLASS="CRITICAL"
    elif [ "$SCORE" -ge 3 ]; then
        CLASS="SUSPICIOUS"
    else
        CLASS="LEGIT"
    fi
    
    # Get status summary (using field 9 for reliability)
    STATUS_SUMMARY=$(grep "^$ip " "$TEMP_LOG" | awk '{print $9}' | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')

    printf "%-18s | %-5s | %-12s | %-12s | %s\n" "$ip" "$count" "${STATUS_SUMMARY:0:12}" "$CLASS" "$REASONS"
done

echo "================================================================================"
echo "[*] Analysis complete."

# Cleanup
rm "$TEMP_LOG"
