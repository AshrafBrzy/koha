#!/bin/bash
# Developer: ashraf brzy 00201211159150
# Assistant: Gemini
# Topic: Koha Universal Diagnostic, Auto-Hardening & Telegram Reporting Tool
# Version: 5.5

# ---------------------------------------------------------
# Variables & Configurations
# ---------------------------------------------------------
START_TIME=$(date +%s)
# Pointing to actual Koha Plack access logs based on server configuration
KOHA_OPAC_LOGS="/var/log/koha/*/plack.log"
KOHA_INTRA_LOGS="/var/log/koha/*/plack.log"
ERR_LOG="/var/log/apache2/error.log"

# --- Telegram API Configuration ---
TG_TOKEN=""
TG_CHAT_IDS=()
TELEGRAM_ALERT=""
TELEGRAM_REPORT=""
TELEGRAM_SERVICES=""
TELEGRAM_SITES=""
TELEGRAM_SECURITY=""
TELEGRAM_DIAGNOSTIC=""

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
echo " Koha Universal Diagnostic & Auto-Hardening Tool (v5.5)"
echo " Auto-Detected $DOMAIN_COUNT Domains for Testing."
echo " Started at: $(date)"
echo "============================================================"
echo ""

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)."
   exit 1
fi

# --- Operation Mode Prompt ---
echo "Select Operation Mode:"
echo "  [1] Diagnostic Only (Safe mode, no system changes)"
echo "  [2] Diagnostic & Auto-Healing (Restarts down services & applies hardening)"
read -p "Enter your choice [1 or 2]: " MODE_CHOICE

if [ "$MODE_CHOICE" == "2" ]; then
    ENABLE_HEALING="true"
    echo "--> Running in: Auto-Healing Mode."
else
    ENABLE_HEALING="false"
    echo "--> Running in: Diagnostic Only Mode."
fi
echo ""

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
        if [ "$category" == "service" ]; then TELEGRAM_SERVICES="${TELEGRAM_SERVICES}%0A🟡 $name (Recovered/Applied)"; fi
        if [ "$category" == "site" ]; then TELEGRAM_SITES="${TELEGRAM_SITES}%0A🟡 $name (Issues)"; fi
        if [ "$category" == "security" ]; then TELEGRAM_SECURITY="${TELEGRAM_SECURITY}%0A🟡 $name (Action Taken)"; fi
    else
        printf "[FAIL] %-50s\n" "$name"
        TELEGRAM_ALERT="${TELEGRAM_ALERT}%0A❌ [FAIL] $name"
        if [ "$category" == "service" ]; then TELEGRAM_SERVICES="${TELEGRAM_SERVICES}%0A🔴 $name (FAILED)"; fi
        if [ "$category" == "site" ]; then TELEGRAM_SITES="${TELEGRAM_SITES}%0A🔴 $name (FAILED)"; fi
        if [ "$category" == "security" ]; then TELEGRAM_SECURITY="${TELEGRAM_SECURITY}%0A🔴 $name (FAILED)"; fi
    fi
}

# NEW FUNCTION: Auto-Backup any file before modifying it
backup_file() {
    local target_file=$1
    if [ -f "$target_file" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_name="${target_file}.bak_${timestamp}"
        cp -p "$target_file" "$backup_name"
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
        if [ "$ENABLE_HEALING" == "true" ]; then
            printf "\r%-60s\n" "[WARN] $name is DOWN! Attempting auto-restart..."
            systemctl restart "$srv"
            sleep 3
            if systemctl is-active --quiet "$srv"; then
                print_result "WARN" "$name was DOWN but Auto-Recovered" "service"
            else
                print_result "FAIL" "$name Auto-Recovery FAILED" "service"
            fi
        else
            print_result "FAIL" "$name is DOWN! (Auto-healing disabled)" "service"
        fi
    fi
}

# Function to check HTTP status of OPAC/Staff interfaces with local fallback
check_website() {
    local url=$1
    local name=$2
    local domain=$(echo "$url" | awk -F/ '{print $3}' | cut -d: -f1)
    
    show_progress "$name"
    
    HTTP_CODE=$(curl -k -L -o /dev/null -s -w "%{http_code}\n" --max-time 10 "$url")
    
    if [ "$HTTP_CODE" -eq 000 ]; then
        HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}\n" -H "Host: $domain" http://127.0.0.1 --max-time 10)
    fi
    
    if [[ "$HTTP_CODE" =~ ^(200|301|302|401|403)$ ]]; then
        print_result "OK" "$name (HTTP $HTTP_CODE)" "site"
    else
        print_result "FAIL" "$name returned HTTP $HTTP_CODE" "site"
    fi
}

# Universal Security Hardening Auto-Deployer
apply_security_hardening() {
    show_progress "Applying Security Hardening Configs"
    local HARDENING_FILE="/etc/koha/security-hardening.conf"
    local APACHE_CONF="/etc/apache2/conf-available/security-hardening.conf"
    local NEEDS_RELOAD=0

    local STAFF_DOMAIN=$(grep -ih "^\s*ServerName" /etc/apache2/sites-enabled/* 2>/dev/null | grep -i "staff\|admin\|intra" | awk '{print $2}' | head -n 1)
    
    cat << 'EOF' > "$HARDENING_FILE"
<IfModule mod_rewrite.c>
RewriteEngine On

# 1. Prevent Insecure HTTP Methods (XST Attacks)
RewriteCond %{REQUEST_METHOD} ^(TRACE|TRACK)
RewriteRule .* - [F]

# 2. Block Resource-Heavy Bots & Alibaba Scrapers
RewriteCond %{HTTP_USER_AGENT} (meta-externalagent|facebookexternalhit|BLEXBot|PetalBot|Amazonbot|AliyunSecBot|bingbot|GPTBot|SemrushBot|AhrefsBot|OAI-SearchBot|YandexBot|DotBot|MJ12bot|rogerbot|MegaIndex|Baiduspider|Turnitin|YisouSpider|Alibaba) [NC]
RewriteRule ^ - [F,L]

# 3. Block Heavy Exports by Bots
RewriteCond %{QUERY_STRING} format=(marcstd|bibtex|utf8|isbd) [NC]
RewriteCond %{HTTP_USER_AGENT} (bot|crawler|spider|slurp|meta-externalagent) [NC]
RewriteRule ^/cgi-bin/koha/opac-export\.pl - [F,L]

# 4. Protect Search Engine from Bots (CPU Protection)
RewriteCond %{HTTP_USER_AGENT} (bot|crawler|spider|slurp|meta-externalagent) [NC]
RewriteRule ^/cgi-bin/koha/opac-search\.pl - [F,L]

# 5. Ultimate Deep Pagination Protection (Block offset >= 1000)
RewriteCond %{QUERY_STRING} offset=([1-9][0-9]{3,}) [NC]
RewriteRule ^/cgi-bin/koha/opac-search\.pl - [F,L]

</IfModule>

<IfModule mod_security2.c>
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess Off
IncludeOptional /usr/share/modsecurity-crs/crs-setup.conf
IncludeOptional /usr/share/modsecurity-crs/rules/*.conf

# Staff & Admin Whitelist (Auto-generated by Koha Diagnostic Tool)
SecRule REQUEST_HEADERS:Host "@contains admin" "id:1000500,phase:1,pass,nolog,ctl:ruleEngine=Off"
EOF

    if [ -n "$STAFF_DOMAIN" ]; then
        echo "SecRule REQUEST_HEADERS:Host \"@contains $STAFF_DOMAIN\" \"id:1000501,phase:1,pass,nolog,ctl:ruleEngine=Off\"" >> "$HARDENING_FILE"
    fi
    echo "</IfModule>" >> "$HARDENING_FILE"

    a2enmod rewrite >/dev/null 2>&1
    a2enmod security2 >/dev/null 2>&1

    if [ ! -f "$APACHE_CONF" ] || ! cmp -s "$HARDENING_FILE" "$APACHE_CONF"; then
        backup_file "$APACHE_CONF"
        
        cp "$HARDENING_FILE" "$APACHE_CONF"
        a2enconf security-hardening >/dev/null 2>&1
        NEEDS_RELOAD=1
    fi

    if [ $NEEDS_RELOAD -eq 1 ]; then
        systemctl reload apache2
        print_result "WARN" "Security Hardening Deployed & Apache Reloaded" "security"
    else
        print_result "OK" "Security Hardening is Active & Up-to-date" "security"
    fi
}

# NEW FUNCTION: Auto-apply UFW Priority Blocks for Malicious Subnets
apply_ufw_hardening() {
    show_progress "Applying UFW Network Hardening"
    
    # Check if UFW is installed and active
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        local RELOAD_UFW=0
        
        # Block Alibaba Scraper Subnet at Position 1
        if ! ufw status numbered | grep -q "47.82.0.0/16"; then
            ufw insert 1 deny from 47.82.0.0/16 >/dev/null 2>&1
            RELOAD_UFW=1
        fi
        
        # Block Malicious FBW Scanner Subnet at Position 1
        if ! ufw status numbered | grep -q "185.177.72.0/24"; then
            ufw insert 1 deny from 185.177.72.0/24 >/dev/null 2>&1
            RELOAD_UFW=1
        fi
        
        if [ $RELOAD_UFW -eq 1 ]; then
            ufw reload >/dev/null 2>&1
            print_result "WARN" "UFW Priority Blocks Applied (Alibaba/FBW)" "security"
        else
            print_result "OK" "UFW Priority Blocks are Active & Up-to-date" "security"
        fi
    else
        print_result "WARN" "UFW is inactive or not installed (Skipped)" "security"
    fi
}

# ---------------------------------------------------------
# PHASE 1: System Health, Services & Auto-Recovery
# ---------------------------------------------------------
echo ">>> PHASE 1: System Health & Services"

check_and_heal_service "mariadb" "MariaDB Database"
check_and_heal_service "apache2" "Apache Web Server"
check_and_heal_service "memcached" "Memcached"

# Execute Auto-Hardening based on Mode
if [ "$ENABLE_HEALING" == "true" ]; then
    apply_security_hardening
    apply_ufw_hardening
else
    show_progress "Security & Network Hardening Configs"
    print_result "WARN" "Security & UFW Hardening Skipped (Diagnostic Mode)" "security"
fi

# Koha Common (Smarter Check handling oom-kill scenarios & Parent Healing)
show_progress "Koha Common Service"
if systemctl is-active --quiet koha-common; then
    print_result "OK" "Koha Common Service" "service"
else
    # Parent service is down. Are child processes running?
    if pgrep -f "koha-indexer" > /dev/null; then
        if [ "$ENABLE_HEALING" == "true" ]; then
            printf "\r%-60s\n" "[WARN] Koha Common parent is dead! Healing service state..."
            systemctl restart koha-common
            sleep 3
            print_result "WARN" "Koha Common Parent Service Auto-Recovered" "service"
        else
            print_result "WARN" "Koha Common dead but processes running (Healing disabled)" "service"
        fi
    else
        # Nothing is running
        if [ "$ENABLE_HEALING" == "true" ]; then
            printf "\r%-60s\n" "[WARN] Koha Common is DOWN! Attempting auto-restart..."
            systemctl restart koha-common
            sleep 3
            if systemctl is-active --quiet koha-common || pgrep -f "koha-indexer" > /dev/null; then
                print_result "WARN" "Koha Common Auto-Recovered" "service"
            else
                print_result "FAIL" "Koha Common Auto-Recovery FAILED" "service"
            fi
        else
            print_result "FAIL" "Koha Common is DOWN! (Auto-healing disabled)" "service"
        fi
    fi
fi

# Koha Plack (Starman Process Check)
show_progress "Koha Plack Service"
if pgrep -f "starman" > /dev/null || pgrep -f "koha-plack" > /dev/null; then
    print_result "OK" "Koha Plack (Starman)" "service"
else
    if [ "$ENABLE_HEALING" == "true" ]; then
        printf "\r%-60s\n" "[WARN] Koha Plack is DOWN! Attempting auto-restart..."
        koha-plack --restart $(koha-list --enabled) 2>/dev/null || systemctl restart koha-common
        sleep 3
        if pgrep -f "starman" > /dev/null || pgrep -f "koha-plack" > /dev/null; then
            print_result "WARN" "Koha Plack Auto-Recovered" "service"
        else
            print_result "FAIL" "Koha Plack Auto-Recovery FAILED" "service"
        fi
    else
        print_result "FAIL" "Koha Plack is DOWN! (Auto-healing disabled)" "service"
    fi
fi

# Zebra Indexer
show_progress "Zebra Indexer"
if pgrep -x "zebrasrv" > /dev/null || ps aux | grep -v grep | grep -q "zebra"; then
    print_result "OK" "Zebra Indexer" "service"
else
    if [ "$ENABLE_HEALING" == "true" ]; then
        printf "\r%-60s\n" "[WARN] Zebra is DOWN! Attempting auto-restart via koha-common..."
        systemctl restart koha-common
        sleep 3
        if pgrep -x "zebrasrv" > /dev/null || ps aux | grep -v grep | grep -q "zebra"; then
            print_result "WARN" "Zebra Auto-Recovered" "service"
        else
            print_result "FAIL" "Zebra Auto-Recovery FAILED" "service"
        fi
    else
        print_result "FAIL" "Zebra is DOWN! (Auto-healing disabled)" "service"
    fi
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
# PHASE 3: System Resources (Disk, RAM, CPU) & Process Health
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
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print int($1)}')
CPU_USAGE=$((100 - CPU_IDLE))
print_result "OK" "Overall CPU Usage: ${CPU_USAGE}%"

echo "  -- Top 4 CPU Consuming Processes --"
ps -eo %cpu,user,comm --sort=-%cpu | head -n 5 | awk 'NR==1 {printf "     %-8s | %-12s | %s\n", "CPU%", "USER", "COMMAND"} NR>1 {printf "     %-8s | %-12s | %s\n", $1"%", $2, substr($3,1,30)}'
echo ""

# Stuck Plack/Starman Diagnostic
show_progress "Stuck Plack/Starman Processes"
STUCK_COUNT=$(ps -eo etimes,comm | grep -i starman | awk '{if ($1 > 1800) print $0}' | wc -l)

if [ "$STUCK_COUNT" -gt 0 ]; then
    print_result "FAIL" "Found $STUCK_COUNT Stuck Plack Processes (>30m) consuming CPU"
else
    print_result "OK" "No stuck Plack/Starman processes detected"
fi

# --- DEEP CPU PROFILING ---
if [ "$CPU_USAGE" -gt 75 ] || [ "$STUCK_COUNT" -gt 0 ]; then
    echo "  [!] HIGH CPU DETECTED: Running Deep Diagnostic Profiling..."
    TELEGRAM_DIAGNOSTIC="%0A%0A🔍 *Deep Diagnostic (High CPU):*"
    
    TOP_ACTIVE_IPS=$(ss -tn src :80 or src :443 | awk '{print $5}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -nr | head -n 3)
    if [ ! -z "$TOP_ACTIVE_IPS" ]; then
        TELEGRAM_DIAGNOSTIC="${TELEGRAM_DIAGNOSTIC}%0A🔌 *Top Active Conn IPs:*%0A$(echo "$TOP_ACTIVE_IPS" | awk '{print "    " $1 " conns from " $2}')"
    fi

    if ls $KOHA_INTRA_LOGS 1> /dev/null 2>&1; then
        TOP_INTRA_URLS=$(tail -n 1000 $KOHA_INTRA_LOGS 2>/dev/null | awk -F'\"' '{print $2}' | awk '{print $2}' | sort | uniq -c | sort -nr | head -n 3)
        if [ ! -z "$TOP_INTRA_URLS" ]; then
            TELEGRAM_DIAGNOSTIC="${TELEGRAM_DIAGNOSTIC}%0A📊 *Heavy Staff URLs (Last 1k):*%0A$(echo "$TOP_INTRA_URLS" | awk '{print "    " $1 " hits: " substr($2,1,40)}')"
        fi
    fi

    if ls $KOHA_OPAC_LOGS 1> /dev/null 2>&1; then
        TOP_OPAC_URLS=$(tail -n 1000 $KOHA_OPAC_LOGS 2>/dev/null | awk -F'\"' '{print $2}' | awk '{print $2}' | sort | uniq -c | sort -nr | head -n 3)
        if [ ! -z "$TOP_OPAC_URLS" ]; then
             TELEGRAM_DIAGNOSTIC="${TELEGRAM_DIAGNOSTIC}%0A🌐 *Heavy OPAC URLs (Last 1k):*%0A$(echo "$TOP_OPAC_URLS" | awk '{print "    " $1 " hits: " substr($2,1,40)}')"
        fi
    fi
fi

# ---------------------------------------------------------
# PHASE 4: Security & Log Analysis (Bot Attacks)
# ---------------------------------------------------------
echo ">>> PHASE 4: Security & Log Analysis (Using Koha OPAC Logs)"

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

TELEGRAM_REPORT="📊 *Koha Server Status Report* 📊%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}🕒 *Time:* $(date +'%Y-%m-%d %H:%M:%S')%0A%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}💻 *Server Resources:*%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}▪️ *CPU Used:* ${CPU_USAGE}%%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}▪️ *RAM Used:* ${FREE_RAM}%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}▪️ *Disk Used:* ${DISK_USAGE}%%0A"

TELEGRAM_REPORT="${TELEGRAM_REPORT}%0A🛡️ *Security Status:*${TELEGRAM_SECURITY}%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}%0A⚙️ *Core Services:*${TELEGRAM_SERVICES}%0A"
TELEGRAM_REPORT="${TELEGRAM_REPORT}%0A🌐 *Koha Instances (Domains):*${TELEGRAM_SITES}%0A"

if [ ! -z "$TELEGRAM_ALERT" ]; then
    TELEGRAM_REPORT="${TELEGRAM_REPORT}%0A🚨 *ALERTS & FAILURES:*${TELEGRAM_ALERT}%0A"
fi

if [ ! -z "$TELEGRAM_DIAGNOSTIC" ]; then
    TELEGRAM_REPORT="${TELEGRAM_REPORT}${TELEGRAM_DIAGNOSTIC}%0A"
fi

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
