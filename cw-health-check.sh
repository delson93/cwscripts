#!/bin/bash

###############################################################################
# Cloudways Debian Server Health Check
# - CPU load, memory, swap
# - iostat CPU (steal, iowait)
# - High CPU and memory processes
# - Disk space and inodes
# - Key services
# - Apache and system logs (OOM, killed, Consumed)
# - Cloudways APM per application (excluding master user)
###############################################################################

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RED="\e[31m"
YELLOW="\e[33m"
GREEN="\e[32m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

issues_found=0

print_header() {
    echo -e "${BOLD}${CYAN}\n========== $1 ==========${RESET}"
}

warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
    issues_found=1
}

crit() {
    echo -e "${RED}[CRIT]${RESET} $1"
    issues_found=1
}

ok() {
    echo -e "${GREEN}[OK]${RESET} $1"
}

check_basic_info() {
    print_header "BASIC SYSTEM INFO"
    echo "Hostname       : $(hostname)"
    echo "Date           : $(date)"
    echo "Uptime         : $(uptime -p 2>/dev/null || uptime)"
    echo "Kernel         : $(uname -r)"
    echo "Distro         : $(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '\"')"
    echo "CPU cores      : $(nproc)"
}

check_load_and_cpu() {
    print_header "CPU LOAD AND HIGH CPU PROCESSES"

    cores=$(nproc)
    read -r load1 load5 load15 rest < /proc/loadavg

    echo "Load average   : 1m=$load1  5m=$load5  15m=$load15  (cores=$cores)"

    high_load=$(awk -v l="$load1" -v c="$cores" 'BEGIN { if (l > c*1.5) print 1; else print 0 }')
    if [ "$high_load" -eq 1 ]; then
        crit "1 minute load ($load1) is higher than 1.5 x CPU cores ($cores)"
    else
        ok "Load average is within normal range"
    fi

    echo
    echo -e "${BOLD}Top 15 processes by CPU usage:${RESET}"
    ps -eo pid,ppid,user,comm,%cpu,%mem,etimes --sort=-%cpu | head -n 16

    echo
    echo -e "${BOLD}PHP related processes using high CPU (>30 percent CPU):${RESET}"

    php_high=$(ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu \
        | awk 'NR>1 && /php/ && $4 > 30.0 {printf "%6s %-10s %-25s %6s %6s\n", $1,$2,$3,$4,$5}')

    if [ -n "$php_high" ]; then
        printf "  PID   USER       COMMAND                     %%CPU  %%MEM\n"
        echo "$php_high"
        warn "One or more PHP processes are using high CPU. Review PHP-FPM pools, cron jobs, and application code."
    else
        ok "No PHP processes above 30 percent CPU"
    fi
}

check_iostat() {
    print_header "CPU USAGE DETAILS (IOSTAT)"

    if ! command -v iostat >/dev/null 2>&1; then
        warn "iostat command not found. Install sysstat package for detailed CPU stats."
        return
    fi

    # Take two samples and use the second one
    output=$(LC_ALL=C iostat -c 2 2 2>/dev/null)
    line=$(echo "$output" | awk '/^avg-cpu:/ {getline; l=$0} END {print l}')

    if [ -z "$line" ]; then
        warn "Could not parse iostat output."
        return
    fi

    read user nice system iowait steal idle <<EOF
$(echo "$line" | awk '{print $1,$2,$3,$4,$5,$6}')
EOF

    echo "avg-cpu line   : $line"
    echo "User           : ${user}%"
    echo "System         : ${system}%"
    echo "IO wait        : ${iowait}%"
    echo "Steal          : ${steal}%"
    echo "Idle           : ${idle}%"

    if awk -v s="$steal" 'BEGIN { exit !(s > 5.0) }'; then
        crit "CPU steal is high (${steal} percent). Possible noisy neighbor or host contention."
    fi

    if awk -v w="$iowait" 'BEGIN { exit !(w > 10.0) }'; then
        warn "IO wait is elevated (${iowait} percent). Possible disk I/O bottleneck."
    fi
}

check_memory() {
    print_header "MEMORY AND SWAP"

    if grep -q "^MemTotal" /proc/meminfo; then
        mem_line=$(grep "^MemTotal" /proc/meminfo)
        mem_avail_line=$(grep "^MemAvailable" /proc/meminfo)
        swap_total_line=$(grep "^SwapTotal" /proc/meminfo)
        swap_free_line=$(grep "^SwapFree" /proc/meminfo)

        mem_total_kb=$(echo "$mem_line" | awk '{print $2}')
        mem_avail_kb=$(echo "$mem_avail_line" | awk '{print $2}')
        mem_used_kb=$((mem_total_kb - mem_avail_kb))

        mem_used_perc=$(awk -v u="$mem_used_kb" -v t="$mem_total_kb" 'BEGIN { if (t == 0) print 0; else printf "%.1f", (u*100)/t }')

        echo "Memory total   : $((mem_total_kb/1024)) MB"
        echo "Memory used    : $((mem_used_kb/1024)) MB (${mem_used_perc}%)"
        echo "Memory avail   : $((mem_avail_kb/1024)) MB"

        if awk -v p="$mem_used_perc" 'BEGIN { exit !(p > 85.0) }'; then
            crit "Memory usage above 85 percent"
        else
            ok "Memory usage is within normal range"
        fi

        if [ -n "$swap_total_line" ]; then
            swap_total_kb=$(echo "$swap_total_line" | awk '{print $2}')
            swap_free_kb=$(echo "$swap_free_line" | awk '{print $2}')
            swap_used_kb=$((swap_total_kb - swap_free_kb))
            if [ "$swap_total_kb" -gt 0 ]; then
                swap_used_perc=$(awk -v u="$swap_used_kb" -v t="$swap_total_kb" 'BEGIN { printf "%.1f", (u*100)/t }')
                echo "Swap total     : $((swap_total_kb/1024)) MB"
                echo "Swap used      : $((swap_used_kb/1024)) MB (${swap_used_perc}%)"
                if awk -v p="$swap_used_perc" 'BEGIN { exit !(p > 70.0) }'; then
                    warn "Swap usage above 70 percent. Possible memory pressure."
                else
                    ok "Swap usage is acceptable"
                fi
            else
                echo "Swap           : No swap configured"
            fi
        fi
    else
        warn "Cannot read /proc/meminfo"
    fi
}

check_disk() {
    print_header "DISK SPACE"

    echo -e "${BOLD}Disk usage (df -h):${RESET}"
    df -hP

    echo
    echo -e "${BOLD}Checking for partitions above 80 percent usage:${RESET}"
    df -hP | awk '
        NR==1 { next }
        {
            gsub("%","",$5);
            if ($5 >= 80) {
                printf "Partition %s on %s is at %s%% usage\n", $1, $6, $5;
                has_high=1;
            }
        }
        END {
            if (!has_high) print "No partitions above 80 percent usage.";
        }' | while read -r line; do
            if echo "$line" | grep -q "Partition"; then
                crit "$line"
            else
                ok "$line"
            fi
        done
}

check_inodes() {
    print_header "INODE USAGE"

    echo -e "${BOLD}Inode usage (df -hi):${RESET}"
    df -hiP

    echo
    echo -e "${BOLD}Checking for partitions above 80 percent inode usage:${RESET}"
    df -hiP | awk '
        NR==1 { next }
        {
            gsub("%","",$5);
            if ($5 >= 80) {
                printf "Partition %s on %s is at %s%% inode usage\n", $1, $6, $5;
                has_high=1;
            }
        }
        END {
            if (!has_high) print "No partitions above 80 percent inode usage.";
        }' | while read -r line; do
            if echo "$line" | grep -q "Partition"; then
                crit "$line"
            else
                ok "$line"
            fi
        done
}

check_services() {
    print_header "KEY SERVICES STATUS"

    if command -v systemctl >/dev/null 2>&1; then
        base_services=("nginx" "apache2" "mysql" "varnish" "memcached")

        for svc in "${base_services[@]}"; do
            if systemctl list-unit-files | grep -q "^${svc}\.service"; then
                if systemctl is-active --quiet "$svc"; then
                    ok "Service $svc is active"
                else
                    crit "Service $svc is not active"
                fi
            fi
        done

        php_services=$(systemctl list-units 'php*-fpm.service' --no-legend 2>/dev/null | awk '{print $1}')
        if [ -n "$php_services" ]; then
            echo
            echo -e "${BOLD}PHP-FPM services:${RESET}"
            for svc in $php_services; do
                if systemctl is-active --quiet "$svc"; then
                    ok "Service $svc is active"
                else
                    crit "Service $svc is not active"
                fi
            done
        fi
    else
        warn "systemctl not found. Skipping service status checks."
    fi
}

check_logs_and_oom() {
    print_header "APACHE AND SYSTEM LOG EVENTS (LAST 24 HOURS)"

    # Apache ap_thread_create
    if [ -f /var/log/apache2/error.log ]; then
        ap_threads=$(grep -i "ap_thread_create" /var/log/apache2/error.log | tail -n 20)
        if [ -n "$ap_threads" ]; then
            warn "Apache reported ap_thread_create issues in error.log (last 20 matches):"
            echo "$ap_threads"
        else
            ok "No ap_thread_create errors found in Apache error.log"
        fi
    else
        warn "Apache error log not found at /var/log/apache2/error.log"
    fi

    if command -v journalctl >/dev/null 2>&1; then
        echo
        echo -e "${BOLD}OOM or killed processes (journalctl, last 24 hours):${RESET}"
        oom=$(journalctl --since "24 hours ago" 2>/dev/null | grep -Ei "killed|oom|out of memory" | tail -n 20)
        if [ -n "$oom" ]; then
            crit "OOM or killed process events detected in the last 24 hours (showing last 20 lines):"
            echo "$oom"
        else
            ok "No OOM or killed process events detected in the last 24 hours"
        fi

        echo
        echo -e "${BOLD}Consumed events (journalctl, last 24 hours):${RESET}"
        consumed=$(journalctl --since "24 hours ago" 2>/dev/null | grep "Consumed" | tail -n 20)
        if [ -n "$consumed" ]; then
            warn "Resource consumption events detected (showing last 20 lines):"
            echo "$consumed"
        else
            ok "No 'Consumed' events detected in the last 24 hours"
        fi
    else
        warn "journalctl not available. Skipping system log checks."
    fi
}

check_top_processes() {
    print_header "CURRENT TOP PROCESSES"

    echo -e "${BOLD}Top processes by CPU (ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head):${RESET}"
    ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head

    echo
    echo -e "${BOLD}Top processes by memory (ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head):${RESET}"
    ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head
}

check_apm_php() {
    print_header "CLOUDWAYS APM PHP STATS"

    if [ -x /usr/local/sbin/apm ]; then
        echo "APM binary     : /usr/local/sbin/apm"
        echo

        echo "Detecting application system users from 'apm users'..."

        # Extract all usernames, then exclude master_* users
        app_users=$(/usr/local/sbin/apm users --no_upgrade 2>/dev/null \
            | grep -o '"username":"[^"]*"' \
            | cut -d'"' -f4 \
            | grep -v '^master_' \
            | sort -u)

        if [ -z "$app_users" ]; then
            warn "Could not detect any non-master application sys_user from 'apm users'."
            return
        fi

        for u in $app_users; do
            echo
            echo "===== APM PHP stats for sys_user: $u (last 1 hour) ====="
            output=$(/usr/local/sbin/apm php -s "$u" -l 1h --processes --no_upgrade 2>/dev/null)
            if [ -z "$output" ]; then
                warn "apm php returned no output for sys_user $u"
                continue
            fi
            echo "$output"

            # Parse max CPU percentage from the table output
            max_cpu=$(echo "$output" | awk '
/│/ {
    line=$0
    gsub(/│/,"", line)
    if (line ~ /PID/ && line ~ /CPU/) next
    n=split(line, a, " ")
    cpu=""
    for (i=1; i<=n; i++) {
        if (a[i] ~ /^[0-9.]+%$/) {cpu=a[i]; break}
    }
    if (cpu != "") {
        gsub("%","",cpu)
        val=cpu+0
        if (val > max) max=val
    }
}
END {
    if (max > 0) printf "%.2f\n", max
}')

            if [ -n "$max_cpu" ]; then
                if awk -v v="$max_cpu" 'BEGIN { exit !(v > 90.0) }'; then
                    crit "APM reports high PHP CPU usage for sys_user $u: ${max_cpu}% in the last 1 hour"
                fi
            fi
        done

        echo
        echo "You can also run manually, for example:"
        echo "  apm php -s <sys_user> -l 1h --processes"
    else
        warn "Cloudways APM tool (/usr/local/sbin/apm) is not installed or not executable."
    fi
}

main() {
    check_basic_info
    check_load_and_cpu
    check_iostat
    check_memory
    check_disk
    check_inodes
    check_services
    check_logs_and_oom
    check_top_processes
    check_apm_php

    print_header "SUMMARY"

    if [ "$issues_found" -eq 0 ]; then
        echo -e "${GREEN}Overall health: OK. No critical issues detected.${RESET}"
        exit 0
    else
        echo -e "${RED}Overall health: ISSUES FOUND. Review warnings and critical messages above.${RESET}"
        exit 1
    fi
}

main
