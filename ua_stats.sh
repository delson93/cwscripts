cat > ua_stats.sh << 'EOF'
#!/bin/bash
LOG_DIR="/home/1579090.cloudwaysapps.com/ndbfpdjvpn/logs"
TOP_N="${1:-10}"

echo "=========================================="
echo "      USER AGENT ANALYSIS REPORT"
echo "=========================================="
echo ""

echo "📅 TIME RANGE:"
echo "------------------------------------------"
FIRST=$(grep -h '^[0-9]' $LOG_DIR/*.access.log 2>/dev/null | head -1 | awk '{print $4}' | tr -d '[')
LAST=$(grep -h '^[0-9]' $LOG_DIR/*.access.log 2>/dev/null | tail -1 | awk '{print $4}' | tr -d '[')
echo "  First: $FIRST"
echo "  Last:  $LAST"
echo ""

echo "📊 TOTAL HITS: $(grep -h '^[0-9]' $LOG_DIR/*.access.log 2>/dev/null | wc -l)"
echo ""

echo "🏆 TOP $TOP_N USER AGENTS:"
echo "------------------------------------------"
echo "Count      | User Agent"
echo "-----------|-------------------------------------------"

grep -h '" [0-9][0-9][0-9] ' $LOG_DIR/*.access.log 2>/dev/null | grep -o '"[^"]*"$' | sed 's/^"//; s/"$//' | sort | uniq -c | sort -rn | head -$TOP_N | awk '{count=$1; $1=""; printf "%-10s | %s\n", count, substr($0,2)}'

echo "=========================================="
EOF

chmod +x ua_stats.sh && ./ua_stats.sh
