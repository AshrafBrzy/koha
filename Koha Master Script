#!/bin/bash

# ==============================================================================
# Koha Master Script (Installer & Optimizer)
# Developed for: Mr. Ashraf Brzy
# Version: v22.0 (XML Specialist - Editing koha-conf.xml)
# Features: Uses xmlstarlet to strictly enforce Plack workers in config file
# ==============================================================================

# --- Configuration File Definition ---
CONFIG_FILE=".koha_install_config"

# --- Setup Logging ---
LOG_FILE="koha_master_$(date +%F_%H-%M-%S).log"
exec > >(tee -i "$LOG_FILE") 2>&1

echo "======================================================"
echo "   Log recording started: $LOG_FILE"
echo "======================================================"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (sudo).${NC}"
    exit 1
fi

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}   Koha Master Script (v22.0 - XML Specialist)          ${NC}"
echo -e "${BLUE}======================================================${NC}"

# ==============================================================================
# [Step 0] Phase Selection & Configuration
# ==============================================================================

echo -e "\n${YELLOW}Please select the operation mode:${NC}"
echo -e "   [1] Phase 1 Only (Installation, SSL, Permission Fix)"
echo -e "   [2] Phase 2 Only (Modify XML, Force Plack 10, Tuning)"
echo -e "   [3] Full Installation (Phase 1 + Phase 2)"
echo -e "   [4] Emergency Fix (Repair Plack, Clear Cache, Warmup)"
echo -e ""

read -p "Select option [1-4]: " INSTALL_MODE < /dev/tty

if [[ ! "$INSTALL_MODE" =~ ^[1-4]$ ]]; then
    echo -e "${RED}Invalid option selected. Exiting.${NC}"
    exit 1
fi

# Function to save config
save_config() {
    set +x
    echo "INSTANCE=\"$INSTANCE\"" > "$CONFIG_FILE"
    echo "ROOT_DOMAIN=\"$ROOT_DOMAIN\"" >> "$CONFIG_FILE"
    echo "OPAC_DOMAIN=\"$OPAC_DOMAIN\"" >> "$CONFIG_FILE"
    echo "STAFF_DOMAIN=\"$STAFF_DOMAIN\"" >> "$CONFIG_FILE"
    echo "EMAIL_ADDR=\"$EMAIL_ADDR\"" >> "$CONFIG_FILE"
    echo -e "${GREEN}>>> Configuration saved to ($CONFIG_FILE).${NC}"
}

# --- BACKUP FUNCTION ---
backup_file() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        local backup_path="${file_path}.bak_$(date +%F_%H-%M-%S)"
        cp "$file_path" "$backup_path"
        echo -e "${BLUE}    [Backup] Created backup of $file_path -> $backup_path${NC}"
    fi
}

# Load or Ask for Config
if [ -f "$CONFIG_FILE" ]; then
    echo -e "\n${YELLOW}Previous configuration found!${NC}"
    source "$CONFIG_FILE"
    echo -e "   - Instance: ${GREEN}$INSTANCE${NC}"
    
    read -p "Use these settings? (y/n): " -n 1 -r USE_SAVED < /dev/tty
    echo
    if [[ ! $USE_SAVED =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}>>> Discarding saved config...${NC}"
        rm "$CONFIG_FILE"
        unset INSTANCE ROOT_DOMAIN OPAC_DOMAIN STAFF_DOMAIN EMAIL_ADDR
    fi
fi

if [[ -z "$INSTANCE" ]]; then
    echo -e "\n${YELLOW}>>> Enter Configuration Details:${NC}"
    read -p "Enter Instance Name (e.g., library): " INSTANCE < /dev/tty
    while [[ -z "$INSTANCE" ]]; do
        echo -e "${RED}Name is required!${NC}"
        read -p "Enter Instance Name: " INSTANCE < /dev/tty
    done

    # Only ask for domains if not running Fixer
    read -p "Enter Root Domain (e.g., adrle.com): " ROOT_DOMAIN < /dev/tty
    [ -z "$ROOT_DOMAIN" ] && read -p "Enter Root Domain: " ROOT_DOMAIN < /dev/tty
    DEFAULT_OPAC="$INSTANCE.$ROOT_DOMAIN"
    echo -e "Enter OPAC Domain [default: $DEFAULT_OPAC]: "
    read OPAC_DOMAIN < /dev/tty
    [ -z "$OPAC_DOMAIN" ] && OPAC_DOMAIN="$DEFAULT_OPAC"
    DEFAULT_STAFF="$INSTANCE-intra.$ROOT_DOMAIN"
    echo -e "Enter Staff Domain [default: $DEFAULT_STAFF]: "
    read STAFF_DOMAIN < /dev/tty
    [ -z "$STAFF_DOMAIN" ] && STAFF_DOMAIN="$DEFAULT_STAFF"
    read -p "Enter Email: " EMAIL_ADDR < /dev/tty
    save_config
fi

# ==============================================================================
# FUNCTIONS
# ==============================================================================

run_phase_1() {
    # Phase 1 Logic (Preserved)
    echo -e "\n${GREEN}>>> [Phase 1] System Setup...${NC}"
    set -x
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get upgrade -y
    apt-get install -y wget gnupg2 software-properties-common curl git unzip vim cpanminus xmlstarlet

    # Locales
    apt-get install -y locales
    export LANGUAGE=en_US.UTF-8; export LANG=en_US.UTF-8; export LC_ALL=en_US.UTF-8
    locale-gen en_US.UTF-8
    dpkg-reconfigure --frontend=noninteractive locales
    if ! grep -q "LC_ALL=en_US.UTF-8" /etc/environment; then
        sh -c "echo 'LC_ALL=en_US.UTF-8\nLANG=en_US.UTF-8\nLANGUAGE=en_US.UTF-8' >> /etc/environment"
    fi

    # Koha Repos & Install
    wget -O - https://debian.koha-community.org/koha/gpg.asc | gpg --dearmor -o /usr/share/keyrings/koha-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/koha-keyring.gpg] http://debian.koha-community.org/koha stable main' | tee /etc/apt/sources.list.d/koha.list
    apt-get update
    apt-get install --reinstall -y javascript-common
    a2enconf javascript-common 2>/dev/null || true
    apt-get install -y koha-common mariadb-server certbot python3-certbot-apache libgd-barcode-perl libio-socket-ssl-perl libnet-ssleay-perl
    
    set +x; cpanm --force GD::Barcode::QRcode; set -x

    # Ports
    sed -i "s/^DOMAIN=.*/DOMAIN=\"$ROOT_DOMAIN\"/" /etc/koha/koha-sites.conf
    sed -i 's/^INTRAPORT=.*/INTRAPORT="80"/' /etc/koha/koha-sites.conf
    sed -i 's/^OPACPORT=.*/OPACPORT="80"/' /etc/koha/koha-sites.conf

    # Apache Mods
    a2enmod rewrite cgi headers proxy_http deflate mpm_itk expires
    systemctl restart apache2

    # Create Instance
    if ! koha-list | grep -q "^$INSTANCE$"; then
        if ! koha-create --create-db "$INSTANCE"; then
            echo -e "${RED}CRITICAL ERROR: Failed to create Instance.${NC}"; exit 1
        fi
    fi

    # Permissions
    if getent passwd "$INSTANCE-koha" > /dev/null; then
        chown -R "$INSTANCE-koha":"$INSTANCE-koha" "/var/cache/koha/$INSTANCE"
        chown -R "$INSTANCE-koha":"$INSTANCE-koha" "/var/lib/koha/$INSTANCE"
        chown -R "$INSTANCE-koha":"$INSTANCE-koha" "/var/log/koha/$INSTANCE"
    fi

    # Apache Config Setup
    APACHE_SITE_CONF="/etc/apache2/sites-available/$INSTANCE.conf"
    if [ -f "$APACHE_SITE_CONF" ]; then
        sed -i "s/ServerName $INSTANCE.$ROOT_DOMAIN/ServerName $OPAC_DOMAIN/g" "$APACHE_SITE_CONF"
        sed -i "s/ServerName $INSTANCE-intra.$ROOT_DOMAIN/ServerName $STAFF_DOMAIN/g" "$APACHE_SITE_CONF"
        grep -q "ServerAlias $OPAC_DOMAIN" "$APACHE_SITE_CONF" || sed -i "/ServerName $OPAC_DOMAIN/a \ \ \ \ ServerAlias $OPAC_DOMAIN" "$APACHE_SITE_CONF"
        grep -q "ServerAlias $STAFF_DOMAIN" "$APACHE_SITE_CONF" || sed -i "/ServerName $STAFF_DOMAIN/a \ \ \ \ ServerAlias $STAFF_DOMAIN" "$APACHE_SITE_CONF"
    fi

    a2ensite "$INSTANCE"
    systemctl restart apache2

    # SSL
    set +x
    certbot --apache --non-interactive --agree-tos -m "$EMAIL_ADDR" -d "$OPAC_DOMAIN" -d "$STAFF_DOMAIN"
    set +x
    echo -e "\n${GREEN}>>> Phase 1 Completed.${NC}"
}

run_phase_2() {
    echo -e "\n${GREEN}>>> [Phase 2] Enterprise Optimization & XML MODIFICATION...${NC}"
    
    # 1. KILL ZOMBIES
    echo -e "${YELLOW}[!] Killing old Starman processes...${NC}"
    killall -9 starman 2>/dev/null
    rm -f /var/run/koha/$INSTANCE/plack.pid
    
    set -x

    # --- A. Enterprise Performance Tuning ---
    echo -e "${YELLOW}[A] Enabling Enterprise Mode (48GB RAM)...${NC}"
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    
    # 1. MariaDB
    DB_BUFFER_POOL_SIZE=$((TOTAL_RAM_MB * 60 / 100))
    DB_LOG_FILE_SIZE=2048
    DB_INSTANCES=$((DB_BUFFER_POOL_SIZE / 1024))
    [ $DB_INSTANCES -gt 64 ] && DB_INSTANCES=64
    [ $DB_INSTANCES -lt 1 ] && DB_INSTANCES=1

    MARIADB_CONF="/etc/mysql/mariadb.conf.d/99-koha-tuning.cnf"
    backup_file "$MARIADB_CONF"
    
    cat > "$MARIADB_CONF" <<EOF
[mysqld]
innodb_buffer_pool_size = ${DB_BUFFER_POOL_SIZE}M
innodb_buffer_pool_instances = ${DB_INSTANCES}
innodb_log_file_size = ${DB_LOG_FILE_SIZE}M
innodb_log_buffer_size = 64M
tmp_table_size = 128M
max_heap_table_size = 128M
sort_buffer_size = 4M
join_buffer_size = 4M
skip-name-resolve
max_connections = 1200
thread_cache_size = 128
max_allowed_packet = 1G
innodb_flush_log_at_trx_commit = 2
innodb_file_per_table = 1
innodb_io_capacity = 2000
query_cache_type = 0
query_cache_size = 0
table_open_cache = 10000
table_definition_cache = 10000
EOF

    # 2. Memcached
    MEMCACHED_SIZE=4096
    sed -i "s/^-m .*/-m $MEMCACHED_SIZE/" /etc/memcached.conf
    grep -q "^-c" /etc/memcached.conf || echo "-c 8192" >> /etc/memcached.conf

    # 3. Apache MPM
    MAX_WORKERS=1200
    cat > "/etc/apache2/mods-available/mpm_prefork.conf" <<EOF
<IfModule mpm_prefork_module>
    StartServers             15
    MinSpareServers          15
    MaxSpareServers          30
    MaxRequestWorkers        $MAX_WORKERS
    MaxConnectionsPerChild   5000
    ServerLimit              $MAX_WORKERS
</IfModule>
EOF

    # --- B. Indexer Daemon ---
    echo -e "${YELLOW}[B] Enabling Indexer Daemon...${NC}"
    KOHA_COMMON_DEFAULT="/etc/default/koha-common"
    if grep -q "USE_INDEXER_DAEMON" "$KOHA_COMMON_DEFAULT"; then
        sed -i 's/^USE_INDEXER_DAEMON=.*/USE_INDEXER_DAEMON="yes"/' "$KOHA_COMMON_DEFAULT"
    else
        echo 'USE_INDEXER_DAEMON="yes"' >> "$KOHA_COMMON_DEFAULT"
    fi
    koha-indexer --stop "$INSTANCE" 2>/dev/null
    koha-indexer --start "$INSTANCE"

    # --- C. Plack Scaling (XML MODIFICATION - THE FINAL FIX) ---
    echo -e "${YELLOW}[C] MODIFYING KOHA-CONF.XML (Forcing 10 Workers)...${NC}"
    
    apt-get install -y xmlstarlet
    
    KOHA_XML_CONF="/etc/koha/sites/$INSTANCE/koha-conf.xml"
    if [ -f "$KOHA_XML_CONF" ]; then
        backup_file "$KOHA_XML_CONF"
        
        # Use XMLStarlet to edit the file safely
        # 1. Update/Add plack_workers -> 10
        if xmlstarlet sel -t -v "//yazgfs/config/plack_workers" "$KOHA_XML_CONF" >/dev/null 2>&1; then
            xmlstarlet ed -L -u "//yazgfs/config/plack_workers" -v "10" "$KOHA_XML_CONF"
        else
            xmlstarlet ed -L -s "//yazgfs/config" -t elem -n "plack_workers" -v "10" "$KOHA_XML_CONF"
        fi
        
        # 2. Update/Add plack_max_requests -> 1000
        if xmlstarlet sel -t -v "//yazgfs/config/plack_max_requests" "$KOHA_XML_CONF" >/dev/null 2>&1; then
            xmlstarlet ed -L -u "//yazgfs/config/plack_max_requests" -v "1000" "$KOHA_XML_CONF"
        else
            xmlstarlet ed -L -s "//yazgfs/config" -t elem -n "plack_max_requests" -v "1000" "$KOHA_XML_CONF"
        fi
        
        echo -e "${GREEN}    Successfully updated koha-conf.xml with xmlstarlet.${NC}"
        
        # Verify the change
        NEW_VAL=$(xmlstarlet sel -t -v "//yazgfs/config/plack_workers" "$KOHA_XML_CONF")
        echo -e "${YELLOW}    Verified plack_workers value: $NEW_VAL${NC}"
        
    else
        echo -e "${RED}    Error: $KOHA_XML_CONF not found!${NC}"
    fi
    
    # 2. Patch plack.psgi (API Crash Fix)
    PLACK_PSGI="/etc/koha/plack.psgi"
    backup_file "$PLACK_PSGI"
    
    if ! grep -q "use lib '/usr/share/koha/lib';" "$PLACK_PSGI"; then
        sed -i "1i use lib '/usr/share/koha/lib';" "$PLACK_PSGI"
    fi
    if ! grep -q "MOJO_APP_LOADER" "$PLACK_PSGI"; then
       sed -i "/my \$app = builder {/i \$ENV{MOJO_APP_LOADER} = 1;" "$PLACK_PSGI"
    fi

    # 3. Systemd Environment Fix
    OVERRIDE_DIR="/etc/systemd/system/koha-plack@.service.d"
    mkdir -p "$OVERRIDE_DIR"
    cat > "$OVERRIDE_DIR/override.conf" <<EOF
[Service]
Environment="PERL5LIB=/usr/share/koha/lib"
Environment="KOHA_HOME=/usr/share/koha"
Environment="KOHA_CONF=/etc/koha/sites/%i/koha-conf.xml"
EnvironmentFile=/etc/default/koha-common
EOF
    systemctl daemon-reload

    # START CLEAN
    koha-plack --enable "$INSTANCE"
    koha-plack --start "$INSTANCE"

    # Patch SSL for Plack
    SSL_CONF="/etc/apache2/sites-available/$INSTANCE-le-ssl.conf"
    if [ -f "$SSL_CONF" ]; then
        if ! grep -q "apache-shared-opac-plack.conf" "$SSL_CONF"; then
            sed -i 's|Include /etc/koha/apache-shared-opac.conf|Include /etc/koha/apache-shared-opac-plack.conf|g' "$SSL_CONF"
            sed -i 's|Include /etc/koha/apache-shared-intranet.conf|Include /etc/koha/apache-shared-intranet-plack.conf|g' "$SSL_CONF"
        fi
    fi

    # --- D. ModSecurity ---
    apt-get install -y libapache2-mod-security2
    a2enmod security2
    cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf
    
    if [ ! -d "/usr/share/modsecurity-crs" ]; then
        git clone https://github.com/coreruleset/coreruleset /usr/share/modsecurity-crs
        mv /usr/share/modsecurity-crs/crs-setup.conf.example /usr/share/modsecurity-crs/crs-setup.conf
    fi

    HARDENING_CONF="/etc/koha/security-hardening.conf"
    cat > "$HARDENING_CONF" <<EOF
<IfModule mod_rewrite.c>
    RewriteEngine on
    RewriteCond %{HTTP_USER_AGENT} (BLEXBot|PetalBot|Amazonbot|AliyunSecBot|bingbot|GPTBot|SemrushBot|AhrefsBot|OAI-SearchBot) [NC]
    RewriteRule ^ - [F,L]
</IfModule>
<IfModule security2_module>
    SecRuleEngine On
    SecRequestBodyAccess On
    SecResponseBodyAccess Off
    SecAuditEngine RelevantOnly
    SecAuditLog /var/log/apache2/modsec_audit.log
    SecAuditLogParts ABIFHZ
    IncludeOptional /usr/share/modsecurity-crs/crs-setup.conf
    IncludeOptional /usr/share/modsecurity-crs/rules/*.conf
</IfModule>
EOF

    apply_security_to_file() {
        local conf_file="$1"
        if [ -f "$conf_file" ]; then
            if ! grep -q "Include /etc/koha/security-hardening.conf" "$conf_file"; then
                sed -i "/<\/VirtualHost>/i \    Include /etc/koha/security-hardening.conf" "$conf_file"
            fi
        fi
    }
    apply_security_to_file "/etc/apache2/sites-available/$INSTANCE.conf"
    apply_security_to_file "/etc/apache2/sites-available/$INSTANCE-le-ssl.conf"

    systemctl daemon-reload
    systemctl restart mariadb
    systemctl restart memcached
    systemctl restart apache2
    systemctl restart koha-common
    
    set +x
    echo -e "${GREEN}>>> Phase 2 Completed.${NC}"
}

run_fixer() {
    echo -e "\n${GREEN}>>> [Emergency Fix] Repairing Plack & Warming Up...${NC}"
    set -x
    rm -rf /var/cache/koha/$INSTANCE/templates/*
    rm -rf /var/cache/koha/$INSTANCE/html/*
    
    killall -9 starman 2>/dev/null
    rm -f /var/run/koha/$INSTANCE/plack.pid
    koha-plack --start "$INSTANCE"
    
    chown -R "$INSTANCE-koha:$INSTANCE-koha" /var/run/koha/$INSTANCE
    chmod -R 775 /var/run/koha/$INSTANCE
    
    systemctl restart apache2
    
    curl -s -o /dev/null "http://localhost" -H "Host: $OPAC_DOMAIN"
    curl -s -o /dev/null "http://localhost/cgi-bin/koha/opac-search.pl?q=test" -H "Host: $OPAC_DOMAIN"
    
    set +x
    echo -e "\n${GREEN}>>> Emergency Fix Completed.${NC}"
}

# ==============================================================================
# EXECUTION LOGIC
# ==============================================================================

if [[ "$INSTALL_MODE" == "1" ]]; then
    run_phase_1
elif [[ "$INSTALL_MODE" == "2" ]]; then
    run_phase_2
elif [[ "$INSTALL_MODE" == "3" ]]; then
    run_phase_1
    run_phase_2
elif [[ "$INSTALL_MODE" == "4" ]]; then
    run_fixer
fi

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================
XML_PASS=$(xmlstarlet sel -t -v 'yazgfs/config/pass' /etc/koha/sites/$INSTANCE/koha-conf.xml 2>/dev/null)
XML_USER=$(xmlstarlet sel -t -v 'yazgfs/config/user' /etc/koha/sites/$INSTANCE/koha-conf.xml 2>/dev/null)

echo -e "\n${GREEN}=============================================${NC}"
echo -e "   Koha Master Process Completed!"
echo -e "${GREEN}=============================================${NC}"

if [[ "$INSTALL_MODE" != "2" && "$INSTALL_MODE" != "4" ]]; then
    echo -e "User:        $XML_USER"
    echo -e "Pass:        $XML_PASS"
fi
echo -e "${GREEN}=============================================${NC}"
echo -e "Log file: ${YELLOW}$LOG_FILE${NC}"
