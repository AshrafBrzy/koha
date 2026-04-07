#!/bin/bash
# Developer: ashraf brzy 00201211159150
# Assistant: Gemini
# Topic: Koha Advanced Diagnostic, Security, Auto-Healing & Telegram Reporting
# Version: 4.10

# ---------------------------------------------------------
# Variables & Configurations
# ---------------------------------------------------------
START_TIME=$(date +%s)
# Pointing to actual Koha instances logs instead of default Apache
KOHA_OPAC_LOGS="/var/log/koha/*/opac-access.log"
ERR_LOG="/var/log/apache2/error.log"

# --- Telegram API Configuration ---
TG_TOKEN=""
TG_CHAT_IDS=()
TELEGRAM_ALERT=""
TELEGRAM_REPORT=""
TELEGRAM_SERVICES=""
TELEGRAM_SITES=""
TELEGRAM_SECURITY=""

# --- Auto-Detect ALL Apache Domains (For Multi-tenant Testing) ---
get_all_koha_urls() {
    local urls=""
    # Extract ALL ServerNames configured in Apache sites-enabled
    local server_names=$(grep -ih "^\s*ServerName" /etc/apache2/sites-enabled/* 2>/dev/null | awk '{print $2}')
    
    for sn in $server_names; do
        urls="$urls https://${sn} "
    done
    
    if [ -n "$urls" ]; then
        # Return a unique, space-separated list of URLs
        echo "$urls" | tr ' ' '\n' | awk 'NF' | sort -u | tr '\n' ' '
    fi
}

ALL_URLS=$(get_all_koha_urls)
DOMAIN_COUNT=$(echo "$ALL_URLS" | wc -w)

# Clear screen for clean output
clear
echo "============================================================"
echo " Koha Advanced Diagnostic & Security Tool (v4.10)"
echo " Auto-Detected $DOMAIN_COUNT Domains for Testing."
echo " Started at: $(date)"
echo "============================================================"
echo ""

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)."
   exit 1
fi

# ---------------------------------------------------------
# Core Functions
# ---------------------------------------------------------
# Function for smart, single-line progress
show_progress() {
    printf "\r%-60s\r" "--> Checking: $1..."
}

# Enhanced Function for printing results cleanly and collecting Telegram data
print_result() {
    local status=$1
    local name=$2
    local category=$3 # Optional: "service", "site", "security"

    if [ "$status" == "OK" ]; then
        printf "[ OK ] %-50s\n" "$name"
        if [ "$category" == "service" ]; then TELEGRAM_SERVICES="${TELEGRAM_SERVICES}%0A🟢 $name"; fi
        if [ "$category" == "site" ]; then TELEGRAM_SITES="${TELEGRAM_SITES}%0A🌐 $name"; fi
        if [ "$category" == "security" ]; then TELEGRAM_SECURITY="${TELEGRAM_SECURITY}%0A🛡️ $name"; fi
    elif [ "$status" == "WARN" ]; then
        printf "[WARN] %-50s\n" "$name"
        TELEGRAM_ALERT="${TELEGRAM_ALERT}%0A⚠️ [WARN] $name"
        if [ "$category" == "service" ]; then TELEGRAM_SERVICES="${TELEGRAM_SERVICES}%0A🟡 $name (Recovered)"; fi
        if [ "$category" == "site" ]; then TELEGRAM_SITES="${TELEGRAM_SITES}%0A🟡 $name (Issues)"; fi
        if [ "$category" == "security" ]; then TELEGRAM_SECURITY="${TELEGRAM_SECURITY}%0A🟡 $name (Issues)"; fi
    else
        printf "[FAIL] %-50s\n" "$name"
        TELEGRAM_ALERT="${TELEGRAM_ALERT}%0A❌ [FAIL] $name"
        if [ "$category" == "service" ]; then TELEGRAM_SERVICES="${TELEGRAM_SERVICES}%0A🔴 $name (FAILED)"; fi
        if [ "$category" == "site" ]; then TELEGRAM_SITES="${TELEGRAM_SITES}%0A🔴 $name (FAILED)"; fi
        if [ "$category" == "security" ]; then TELEGRAM_SECURITY="${TELEGRAM_SECURITY}%0A🔴 $name (FAILED)"; fi
    fi
}

# Centralized Function to Check and Auto-Heal Systemctl Services
check_and_heal_service() {
    local srv=$1
    local name=$2
    show_progress "$name"
    
    if systemctl is-active --quiet "$srv"; then
        print_result "OK" "$name" "service"
    else
        printf "\r%-60s\n" "[WARN] $name is DOWN! Attempting auto-restart..."
        systemctl restart "$srv"
        sleep 3
        if systemctl is-active --quiet "$srv"; then
            print_result "WARN" "$name was DOWN but Auto-Recovered" "service"
        else
            print_result "FAIL" "$name Auto-Recovery FAILED" "service"
        fi
    fi
}

# Function to check HTTP status of OPAC/Staff interfaces with local fallback
check_website() {
    local url=$1
    local name=$2
    local domain=$(echo "$url" | awk -F/ '{print $3}' | cut -d: -f1)
    
    show_progress "$name"
    
    # Try public/HTTPS first
    HTTP_CODE=$(curl -k -L -o /dev/null -s -w "%{http_code}\n" --max-time 10 "$url")
    
    # If it fails (000 usually means connection refused locally), try direct local HTTP with Host Header
    if [ "$HTTP_CODE" -eq 000 ]; then
        HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}\n" -H "Host: $domain" http://127.0.0.1 --max-time 10)
    fi
    
    # Consider 200 (OK), 301/302 (Redirect to HTTPS), 401/403 (Protected Admin) as successful responses
    if [[ "$HTTP_CODE" =~ ^(200|301|302|401|403)$ ]]; then
        print_result "OK" "$name (HTTP $HTTP_CODE)" "site"
    else
        print_result "FAIL" "$name returned HTTP $HTTP_CODE" "site"
    fi
}

# ---------------------------------------------------------
# PHASE 1: System Health, Services & Auto-Recovery
# ---------------------------------------------------------
echo ">>> PHASE 1: System Health & Services"

check_and_heal_service "mariadb" "MariaDB Database"
check_and_heal_service "apache2" "Apache Web Server"
check_and_heal_service "memcached" "Memcached"
check_and_heal_service "koha-common" "Koha Common"

# Koha Plack (Starman Process Check)
show_progress "Koha Plack Service"
if pgrep -f "starman" > /dev/null || pgrep -f "koha-plack" > /dev/null; then
    print_result "OK" "Koha Plack (Starman)" "service"
else
    printf "\r%-60s\n" "[WARN] Koha Plack is DOWN! Attempting auto-restart..."
    koha-plack --restart $(koha-list --enabled) 2>/dev/null || systemctl restart koha-common
    sleep 3
    if pgrep -f "starman" > /dev/null || pgrep -f "koha-plack" > /dev/null; then
        print_result "WARN" "Koha Plack Auto-Recovered" "service"
    else
        print_result "FAIL" "Koha Plack Auto-Recovery FAILED" "service"
    fi
fi

# Zebra Indexer
show_progress "Zebra Indexer"
if pgrep -x "zebrasrv" > /dev/null || ps aux | grep -v grep | grep -q "zebra"; then
    print_result "OK" "Zebra Indexer" "service"
else
    printf "\r%-60s\n" "[WARN] Zebra is DOWN! Attempting auto-restart via koha-common..."
    systemctl restart koha-common
    sleep 3
    if pgrep -x "zebrasrv" > /dev/null || ps aux | grep -v grep | grep -q "zebra"; then
        print_result "WARN" "Zebra Auto-Recovered" "service"
    else
        print_result "FAIL" "Zebra Auto-Recovery FAILED" "service"
    fi
fi

# ModSecurity Check
show_progress "ModSecurity WAF"
if [ -f /etc/apache2/mods-enabled/security2.load ] || [ -L /etc/apache2/mods-enabled/security2.load ]; then
    print_result "OK" "ModSecurity WAF" "security"
else
    print_result "FAIL" "ModSecurity WAF Disabled" "security"
fi

# ---------------------------------------------------------
# PHASE 2: Koha Web Interfaces (Multi-tenant Check)
# ---------------------------------------------------------
echo ">>> PHASE 2: Web Interfaces Availability"

if [ -z "$ALL_URLS" ]; then
    print_result "WARN" "No domains found in Apache configs." "site"
else
    for url in $ALL_URLS; do
        clean_name=$(echo "$url" | awk -F/ '{print $3}')
        check_website "$url" "$clean_name"
    done
fi

# ---------------------------------------------------------
# PHASE 3: System Resources (Disk, RAM, CPU) & Stuck Processes
# ---------------------------------------------------------
echo ">>> PHASE 3: System Resources & Process Health"

# Disk Space
show_progress "Disk Space (/)"
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 85 ]; then
    print_result "WARN" "Disk Usage is High: ${DISK_USAGE}%"
else
    print_result "OK" "Disk Usage: ${DISK_USAGE}%"
fi

# RAM Usage
show_progress "Memory (RAM) Usage"
FREE_RAM=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
if [ $(echo "${FREE_RAM%\%}" | awk '{if ($1 > 90) print 1; else print 0}') -eq 1 ]; then
    print_result "WARN" "RAM Used is VERY HIGH: $FREE_RAM"
else
    print_result "OK" "RAM Used: $FREE_RAM"
fi

# CPU Top Processes & Overall Usage
show_progress "CPU Usage"
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
print_result "OK" "Overall CPU Usage: $CPU_USAGE"

echo "  -- Top 4 CPU Consuming Processes --"
ps -eo %cpu,user,comm --sort=-%cpu | head -n 5 | awk 'NR==1 {printf "     %-8s | %-12s | %s\n", "CPU%", "USER", "COMMAND"} NR>1 {printf "     %-8s | %-12s | %s\n", $1"%", $2, substr($3,1,30)}'
echo ""

# Stuck Plack/Starman Diagnostic (NEW)
show_progress "Stuck Plack/Starman Processes"
# Find processes named starman running for more than 30 minutes (00:30:00) using etime
STUCK_COUNT=$(ps -eo etimes,comm | grep -i starman | awk '{if ($1 > 1800) print $0}' | wc -l)

if [ "$STUCK_COUNT" -gt 0 ]; then
    print_result "FAIL" "Found $STUCK_COUNT Stuck Plack Processes (>30m) consuming CPU"
else
    print_result "OK" "No stuck Plack/Starman processes detected"
fi

# ---------------------------------------------------------
# PHASE 4: Security & Log Analysis (Bot Attacks)
# ---------------------------------------------------------
echo ">>> PHASE 4: Security & Log Analysis (Using Koha OPAC Logs)"

# Check if any Koha OPAC access log exists
if ls $KOHA_OPAC_LOGS 1> /dev/null 2>&1; then
    show_progress "Analyzing Top 5 IPs hitting Koha OPACs"
    printf "\r%-60s\n" "  -- Top 5 IP Addresses by Request Count --"
    cat $KOHA_OPAC_LOGS | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 5 | awk '{printf "     %5s requests from IP: %s\n", $1, $2}'
    
    show_progress "Analyzing Top 5 User-Agents (Bots)"
    printf "\r%-60s\n" "  -- Top 5 User-Agents (Potential Bots) --"
    cat $KOHA_OPAC_LOGS | awk -F'\"' '{print $6}' | sort | uniq -c | sort -nr | head -n 5 | awk '{printf "     %5s hits: %s\n", $1, substr($2,1,50)}'
    
    show_progress "Analyzing opac-search.pl queries"
    printf "\r%-60s\n" "  -- Top IPs hitting opac-search.pl --"
    cat $KOHA_OPAC_LOGS | grep "opac-search.pl" | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 5 | awk '{printf "     %5s searches from IP: %s\n", $1, $2}'
else
    echo "  [WARN] Koha OPAC access logs not found at $KOHA_OPAC_LOGS"
fi
echo ""

# ---------------------------------------------------------
# PHASE 5: Telegram Reporting & Dispatcher
# ---------------------------------------------------------
echo ">>> PHASE 5: Generating Telegram Report"
show_progress "Dispatching to Telegram"

# 1. Header & Resources
TELEGRAM_REPORT="📊 *Koha Server Status Report* 📊%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}🕒 *Time:* $(date +'%Y-%m-%d %H:%M:%S')%0A%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}💻 *Server Resources:*%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}▪️ *CPU Used:* ${CPU_USAGE}%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}▪️ *RAM Used:* ${FREE_RAM}%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}▪️ *Disk Used:* ${DISK_USAGE}%%0A"

# 2. Security
TELEGRAM_REPORT="${TELEGRAM_REPORT}%0A🛡️ *Security Status:*${TELEGRAM_SECURITY}%0A"

# 3. Services
TELEGRAM_REPORT="${TELEGRAM_REPORT}%0A⚙️ *Core Services:*${TELEGRAM_SERVICES}%0A"

# 4. Web Interfaces
TELEGRAM_REPORT="${TELEGRAM_REPORT}%0A🌐 *Koha Instances (Domains):*${TELEGRAM_SITES}%0A"

# 5. Alerts (Only if exists)
if [ ! -z "$TELEGRAM_ALERT" ]; then
    TELEGRAM_REPORT="${TELEGRAM_REPORT}%0A🚨 *ALERTS & FAILURES:*${TELEGRAM_ALERT}%0A"
fi

# Send the report via API to all Chat IDs using standard URL encoding for clean multiline
if [ ! -z "$TG_TOKEN" ] && [ "$TG_TOKEN" != "YOUR_BOT_TOKEN_HERE" ]; then
    for chat_id in "${TG_CHAT_IDS[@]}"; do
        curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            -d chat_id="${chat_id}" \
            -d text="${TELEGRAM_REPORT}" \
            -d parse_mode="Markdown" > /dev/null
    done
    print_result "OK" "Telegram report sent to ${#TG_CHAT_IDS[@]} chat(s)."
else
    print_result "WARN" "Telegram credentials missing. Report not sent."
fi

# ---------------------------------------------------------
# Finalization
# ---------------------------------------------------------
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo "------------------------------------------------------------"
echo " Finished at: $(date)"
echo " Total Execution Time: $DURATION seconds."
echo "============================================================"
