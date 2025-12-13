#!/bin/bash

# =================================================================
# Koha Platinum Installer - v33.2 (Reordered Logic: Install First, Tune Later)
# الترتيب الجديد: التثبيت الأساسي > تحليل العتاد > الأداء > الحماية > SSL
# =================================================================

# --- System Constants ---
LOG_FILE="/var/log/koha_install.log"
CONFIG_FILE="koha_installer.conf"
ICU_URL="https://raw.githubusercontent.com/AshrafBrzy/koha/main/words-icu.xml"
IDX_URL="https://raw.githubusercontent.com/AshrafBrzy/koha/main/default.idx"
TOTAL_STEPS=12
CURRENT_STEP=0

# --- Visual Settings ---
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'

# --- 1. Interactive Configuration Wizard ---
setup_config() {
    clear
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}   Koha Platinum Installer v33.2 (Reordered)   ${NC}"
    echo -e "${GREEN}===============================================${NC}"
    
    echo -e "${YELLOW}ATTENTION: Ensure DNS 'A' records are set!${NC}"

    # Check for existing config
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${YELLOW}Found saved configuration:${NC}"
        echo -e "   1. Instance:      ${GREEN}$INSTANCE${NC}"
        echo -e "   2. Main Domain:   ${GREEN}$DOMAIN${NC}"
        echo -e "   3. OPAC Domain:   ${GREEN}$OPAC_DOMAIN${NC}"
        echo -e "   4. Staff Domain:  ${GREEN}$STAFF_DOMAIN${NC}"
        echo -e "   5. Email:         ${GREEN}$EMAIL${NC}"
        echo -e "   6. DB URL:        ${GREEN}${DB_URL:-(New Install)}${NC}"
        echo -e "${YELLOW}--------------------------------------------------${NC}"
        
        read -p "Use these settings? (y/n) [y]: " USE_EXISTING
        USE_EXISTING=${USE_EXISTING:-y}
        
        if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
            export INSTANCE DOMAIN OPAC_DOMAIN STAFF_DOMAIN EMAIL DB_URL
            return
        fi
    fi

    # Prompt for new settings
    echo -e "\n${BLUE}Enter Installation Details:${NC}"
    
    read -p "Library Name (short) [library]: " INPUT_INSTANCE
    INSTANCE=${INPUT_INSTANCE:-library}
    
    read -p "Main Domain: " INPUT_DOMAIN
    DOMAIN=${INPUT_DOMAIN}
    
    DEFAULT_OPAC="lib.$DOMAIN"
    read -p "OPAC Subdomain [$DEFAULT_OPAC]: " INPUT_OPAC
    OPAC_DOMAIN=${INPUT_OPAC:-$DEFAULT_OPAC}
    
    DEFAULT_STAFF="staff.$DOMAIN"
    read -p "Staff Subdomain [$DEFAULT_STAFF]: " INPUT_STAFF
    STAFF_DOMAIN=${INPUT_STAFF:-$DEFAULT_STAFF}
    
    read -p "Admin Email: " INPUT_EMAIL
    EMAIL=${INPUT_EMAIL}
    
    echo -e "\n${YELLOW}>>> Database Restoration (Optional)${NC}"
    echo "If you have a backup (e.g., .sql.gz), paste the direct link here."
    read -p "DB Backup URL (Leave empty for fresh install): " INPUT_DB_URL
    DB_URL=${INPUT_DB_URL}

    if [[ -z "$INSTANCE" || -z "$DOMAIN" || -z "$OPAC_DOMAIN" || -z "$STAFF_DOMAIN" || -z "$EMAIL" ]]; then
        echo -e "${RED}Error: Basic fields are required!${NC}"
        exit 1
    fi

    # Save Config
    echo "# Koha Installer Config" > "$CONFIG_FILE"
    echo "INSTANCE=\"$INSTANCE\"" >> "$CONFIG_FILE"
    echo "DOMAIN=\"$DOMAIN\"" >> "$CONFIG_FILE"
    echo "OPAC_DOMAIN=\"$OPAC_DOMAIN\"" >> "$CONFIG_FILE"
    echo "STAFF_DOMAIN=\"$STAFF_DOMAIN\"" >> "$CONFIG_FILE"
    echo "EMAIL=\"$EMAIL\"" >> "$CONFIG_FILE"
    echo "DB_URL=\"$DB_URL\"" >> "$CONFIG_FILE"
    
    export INSTANCE DOMAIN OPAC_DOMAIN STAFF_DOMAIN EMAIL DB_URL
    echo -e "${GREEN}Settings saved.${NC}"
    sleep 1
}

# --- Helper Functions ---

format_time() {
    local seconds=$1
    if (( seconds < 60 )); then echo "${seconds}s"; else echo "$((seconds / 60))m $((seconds % 60))s"; fi
}

draw_progress_bar() {
    local width=40
    local percent=$1
    local filled=$((width * percent / 100))
    local empty=$((width - filled))
    printf -v bar "%*s" "$filled" ""; bar=${bar// /#}
    printf -v space "%*s" "$empty" ""; space=${space// /.}
    echo -ne "\r${CYAN}[${bar}${space}] ${percent}%${NC}"
}

run_step() {
    local description="$1"
    local command_func="$2"
    
    ((CURRENT_STEP++))
    local percent=$(( 100 * CURRENT_STEP / TOTAL_STEPS ))
    local step_start=$(date +%s)
    
    echo -ne "\n${BLUE}[Step ${CURRENT_STEP}/${TOTAL_STEPS}]${NC} ${description}..."
    
    $command_func >> "$LOG_FILE" 2>&1 &
    local pid=$!
    
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    
    wait $pid
    local exit_code=$?
    local step_end=$(date +%s)
    local duration=$((step_end - step_start))
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN} [DONE]${NC} ${PURPLE}($(format_time $duration))${NC}"
        draw_progress_bar $percent
    else
        echo -e "${RED} [FAILED]${NC}"
        echo -e "\n${RED}Check log: ${YELLOW}$LOG_FILE${NC}"
        tail -n 10 "$LOG_FILE"
        exit 1
    fi
}

# --- Step Implementation ---

step_1_resources() {
    echo " Analyzing Hardware..."
    CPU_CORES=$(nproc)
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    DB_RAM_MB=$((TOTAL_RAM_MB * 45 / 100))
    if [ "$DB_RAM_MB" -gt 1024 ]; then INNODB_SIZE="$((DB_RAM_MB / 1024))G"; else INNODB_SIZE="${DB_RAM_MB}M"; fi
    PLACK_WORKERS=$CPU_CORES
    [ "$PLACK_WORKERS" -gt 8 ] && PLACK_WORKERS=8
    [ "$PLACK_WORKERS" -lt 2 ] && PLACK_WORKERS=2
    MAX_REQUEST_WORKERS=$(((TOTAL_RAM_MB - DB_RAM_MB - 1024) / 100))
    [ "$MAX_REQUEST_WORKERS" -lt 10 ] && MAX_REQUEST_WORKERS=10
    
    echo "INNODB_SIZE=\"$INNODB_SIZE\"" >> "$CONFIG_FILE"
    echo "PLACK_WORKERS=\"$PLACK_WORKERS\"" >> "$CONFIG_FILE"
    echo "MAX_REQUEST_WORKERS=\"$MAX_REQUEST_WORKERS\"" >> "$CONFIG_FILE"
}

step_2_locale() {
    echo ">> Setting up Locales..."
    apt-get update -qq
    apt-get install -y locales
    locale-gen en_US.UTF-8 ar_EG.UTF-8
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
}

step_3_repos() {
    echo ">> Preparing Repos..."
    apt-get install -y software-properties-common vim wget gnupg curl git unzip xmlstarlet net-tools build-essential openssl
    add-apt-repository -y universe || true
    apt-get update -qq
}

step_4_install() {
    echo ">> Installing Koha Stack..."
    wget -qO - https://debian.koha-community.org/koha/gpg.asc | gpg --dearmor --yes -o /usr/share/keyrings/koha-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/koha-keyring.gpg] http://debian.koha-community.org/koha stable main' | tee /etc/apt/sources.list.d/koha.list
    apt-get update -qq
    apt-get install -y koha-common mariadb-server apache2 libapache2-mod-security2 modsecurity-crs certbot python3-certbot-apache memcached libgd-barcode-perl libtemplate-plugin-json-escape-perl libtemplate-plugin-stash-perl libutf8-all-perl libcgi-emulate-psgi-perl libcgi-compile-perl
}

step_5_tuning() {
    echo ">> Configuring Performance (Applying Hardware Analysis)..."
    source "$CONFIG_FILE"
    cat <<EOF > /etc/mysql/mariadb.conf.d/99-koha-perf.cnf
[mysqld]
innodb_buffer_pool_size = $INNODB_SIZE
innodb_log_file_size = 512M
innodb_log_buffer_size = 64M
innodb_file_per_table = 1
innodb_flush_log_at_trx_commit = 2
max_connections = 500
query_cache_type = 0
query_cache_size = 0
EOF
    cat <<EOF > /etc/apache2/mods-available/mpm_prefork.conf
<IfModule mpm_prefork_module>
    StartServers             5
    MinSpareServers          5
    MaxSpareServers          10
    MaxRequestWorkers        $MAX_REQUEST_WORKERS
    MaxConnectionsPerChild   0
</IfModule>
EOF
    # Restart services to apply tuning immediately
    systemctl restart mariadb apache2
}

step_6_security() {
    echo ">> Configuring WAF & Exclusions..."
    cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf || true
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf
    sed -i 's/SecResponseBodyAccess On/SecResponseBodyAccess Off/' /etc/modsecurity/modsecurity.conf

    cat <<EOF > /usr/share/modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
SecRule REMOTE_ADDR "@ipMatch 127.0.0.1" "id:9999001,phase:1,pass,nolog,ctl:ruleEngine=Off"
SecRule REQUEST_FILENAME "\.(?:css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map|json)(\?.*)?$" "id:9999002,phase:1,pass,nolog,ctl:ruleEngine=Off,ctl:auditEngine=Off"
SecRule REQUEST_URI "@beginsWith /cgi-bin/koha/reports/" "id:9999003,phase:2,pass,nolog,ctl:ruleRemoveById=942100"
SecRule REQUEST_URI "@beginsWith /.well-known/acme-challenge/" "id:9999004,phase:1,pass,nolog,ctl:ruleEngine=Off"
EOF

    if [ ! -f "/etc/modsecurity/crs-setup.conf" ]; then
        echo "SecDefaultAction \"phase:1,log,auditlog,pass\"" > /etc/modsecurity/crs-setup.conf
    fi
    
    if ! grep -q "REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf" /etc/apache2/mods-available/security2.conf; then
        echo "IncludeOptional /usr/share/modsecurity-crs/rules/*.conf" >> /etc/apache2/mods-available/security2.conf
    fi
    sort -u -o /etc/apache2/mods-available/security2.conf /etc/apache2/mods-available/security2.conf

    a2enmod security2 headers rewrite cgi proxy_http deflate || true
}

step_7_create() {
    echo ">> Initializing DB..."
    systemctl restart mariadb memcached apache2
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('');" || true
    mysql -e "DELETE FROM mysql.user WHERE User='';" || true
    mysql -e "FLUSH PRIVILEGES;" || true

    if ! koha-list | grep -q "^$INSTANCE$"; then
        koha-create --create-db "$INSTANCE"
    fi
}

step_8_import_db() {
    echo ">> Database Seeding & Upgrade..."
    source "$CONFIG_FILE"
    
    if [ ! -z "$DB_URL" ]; then
        echo "Downloading SQL Dump..."
        FILENAME=$(basename "$DB_URL")
        TEMP_FILE="/tmp/$FILENAME"
        
        # Download
        if wget -O "$TEMP_FILE" "$DB_URL"; then
            echo "Processing DB File..."
            
            # Decompress if needed
            if [[ "$TEMP_FILE" == *.gz ]]; then
                echo "Decompressing GZIP..."
                gunzip -f "$TEMP_FILE"
                TEMP_FILE="${TEMP_FILE%.gz}"
            fi
            
            echo "Restoring Database to $INSTANCE..."
            koha-mysql "$INSTANCE" < "$TEMP_FILE"
            
            echo "Upgrading Database Schema..."
            koha-upgrade-schema "$INSTANCE"
            
            echo "Updating System Preferences..."
            koha-mysql "$INSTANCE" -e "UPDATE systempreferences SET value='https://$STAFF_DOMAIN' WHERE variable='staffClientBaseURL';"
            koha-mysql "$INSTANCE" -e "UPDATE systempreferences SET value='https://$OPAC_DOMAIN' WHERE variable='OPACBaseURL';"
            
            export DB_IMPORTED=true
            echo "DB_IMPORTED=true" >> "$CONFIG_FILE"
        else
            echo "Failed to download DB. Skipping."
        fi
    else
        echo "No DB URL provided. Fresh install mode."
    fi
}

step_9_arabic_search() {
    echo ">> Optimizing Zebra (Arabic)..."
    ZEBRA_CONF_DIR="/etc/koha/zebradb"
    wget --no-check-certificate -O "$ZEBRA_CONF_DIR/etc/words-icu.xml" "$ICU_URL"
    wget --no-check-certificate -O "$ZEBRA_CONF_DIR/etc/default.idx" "$IDX_URL"
}

step_10_config_lang() {
    echo ">> Setting up Language & Plack..."
    source "$CONFIG_FILE"

    CONF_XML="/etc/koha/sites/$INSTANCE/koha-conf.xml"
    if [ -f "$CONF_XML" ]; then
        sed -i "s/<plack_workers>.*<\/plack_workers>/<plack_workers>$PLACK_WORKERS<\/plack_workers>/g" "$CONF_XML" || true
        sed -i "s/__DB_USE_TLS__/no/g" "$CONF_XML"
        sed -i "s/__DB_TLS_.*__//g" "$CONF_XML"
        if grep -q "__ENCRYPTION_KEY__" "$CONF_XML"; then
            sed -i "s/__ENCRYPTION_KEY__/$(openssl rand -base64 16 | sed 's/[/&]/\\&/g')/g" "$CONF_XML"
        fi
        sed -i "s/__MEMCACHED_SERVERS__/127.0.0.1:11211/g" "$CONF_XML"
        sed -i "s/__MEMCACHED_NAMESPACE__/koha_${INSTANCE}/g" "$CONF_XML"
        sed -i "s/<debug_mode>0<\/debug_mode>/<debug_mode>1<\/debug_mode>/g" "$CONF_XML"
    fi

    mkdir -p "/var/lib/koha/$INSTANCE/css" "/var/lib/koha/$INSTANCE/js"
    chown -R "$INSTANCE-koha:$INSTANCE-koha" "/var/lib/koha/$INSTANCE"

    export KOHA_CONF="$CONF_XML"
    export PERL5LIB=/usr/share/koha/lib
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export PERL_UNICODE=S

    if ! koha-translate --install ar-Arab; then
        koha-translate --update ar-Arab || true
    fi

    CSS_RTL="/var/lib/koha/$INSTANCE/css/staff-global-rtl.css"
    if [ ! -f "$CSS_RTL" ]; then
        touch "$CSS_RTL"
        chown "$INSTANCE-koha:$INSTANCE-koha" "$CSS_RTL"
    fi

    # Logic: Only Reindex if DB was imported in this run
    if [ "$DB_IMPORTED" = true ]; then
        echo "Database restored, running full reindex..."
        koha-rebuild-zebra -v -f "$INSTANCE"
    fi
    
    koha-plack --enable "$INSTANCE" >/dev/null 2>&1
    koha-plack --restart "$INSTANCE" || koha-plack --start "$INSTANCE"
}

step_11_apache_ssl() {
    echo ">> Finalizing Apache Config..."
    
    FINAL_APACHE_OPTS='
       RewriteEngine On
       RewriteRule ^/opac-tmpl/(.*)_[0-9]+\.(css|js)$ /opac-tmpl/$1.$2 [L]
       RewriteRule ^/intranet-tmpl/(.*)_[0-9]+\.(css|js)$ /intranet-tmpl/$1.$2 [L]
       <IfModule security2_module>
          <LocationMatch "\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map|json)(\?.*)?$">
             SecRuleEngine Off
          </LocationMatch>
          <LocationMatch "^/\.well-known/acme-challenge/">
             SecRuleEngine Off
             SecAuditEngine Off
          </LocationMatch>
       </IfModule>
       RewriteCond %{HTTP_USER_AGENT} (BLEXBot|PetalBot|Amazonbot|AliyunSecBot|bingbot|GPTBot|SemrushBot|AhrefsBot) [NC]
       RewriteRule ^ - [F,L]
    '

    cat <<EOF > /etc/apache2/sites-available/$INSTANCE.conf
<VirtualHost *:80>
   ServerName $OPAC_DOMAIN
   $FINAL_APACHE_OPTS
   Include /etc/koha/apache-shared.conf
   Include /etc/koha/apache-shared-opac-plack.conf
   SetEnv KOHA_CONF "/etc/koha/sites/$INSTANCE/koha-conf.xml"
   AssignUserID $INSTANCE-koha $INSTANCE-koha
   ErrorLog /var/log/koha/$INSTANCE/opac-error.log
</VirtualHost>
<VirtualHost *:80>
   ServerName $STAFF_DOMAIN
   $FINAL_APACHE_OPTS
   Include /etc/koha/apache-shared.conf
   Include /etc/koha/apache-shared-intranet-plack.conf
   SetEnv KOHA_CONF "/etc/koha/sites/$INSTANCE/koha-conf.xml"
   AssignUserID $INSTANCE-koha $INSTANCE-koha
   ErrorLog /var/log/koha/$INSTANCE/intranet-error.log
</VirtualHost>
EOF

    chown -R "$INSTANCE-koha:$INSTANCE-koha" "/var/lib/koha/$INSTANCE"
    chmod -R g+rX "/var/lib/koha/$INSTANCE"
    usermod -a -G "${INSTANCE}-koha" www-data

    a2dissite 000-default || true
    a2ensite "$INSTANCE"
    systemctl restart apache2
}

step_12_certbot() {
    echo ">> Requesting SSL..."
    if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
        certbot --apache -d "$OPAC_DOMAIN" -d "$STAFF_DOMAIN" --register-unsafely-without-email --agree-tos --redirect --non-interactive
    else
        certbot --apache -d "$OPAC_DOMAIN" -d "$STAFF_DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
    fi
}

# --- Start ---

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Please run as sudo${NC}"; exit 1; fi

# Run Wizard
setup_config

# Start Logging
SCRIPT_START_TIME=$(date +%s)
echo "--- Installation Started: $(date) ---" > "$LOG_FILE"
echo -e "${YELLOW}Logs are saved to: $LOG_FILE${NC}"
echo -e "${CYAN}Starting Installation...${NC}"

# Run Steps (REORDERED)
run_step "Configuring Locale" step_2_locale
run_step "Preparing Repos" step_3_repos
run_step "Installing Packages" step_4_install
run_step "Creating Instance" step_7_create
run_step "Importing Database" step_8_import_db
run_step "Analyzing Hardware" step_1_resources
run_step "Applying Performance Tuning" step_5_tuning
run_step "Optimizing Search" step_9_arabic_search
run_step "Configuring Security" step_6_security
run_step "Configuring Koha & Lang" step_10_config_lang
run_step "Finalizing Web Server" step_11_apache_ssl
run_step "Enabling SSL" step_12_certbot

# --- Finish ---
SCRIPT_END_TIME=$(date +%s)
TOTAL_DURATION=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
FORMATTED_TOTAL=$(format_time $TOTAL_DURATION)

echo -e "\n${GREEN}===============================================${NC}"
echo -e "${GREEN}      INSTALLATION COMPLETED SUCCESSFULLY      ${NC}"
echo -e "${GREEN}===============================================${NC}"
echo -e "${PURPLE}Total Execution Time: $FORMATTED_TOTAL${NC}"

ADMIN_PASS=$(xmlstarlet sel -t -v 'yazgfs/config/pass' /etc/koha/sites/$INSTANCE/koha-conf.xml 2>/dev/null || echo "See Log")
ADMIN_USER="koha_$INSTANCE"

if [ -z "$DB_URL" ]; then
    echo -e "${YELLOW}FRESH INSTALL:${NC} Login using the credentials below and complete the Web Setup."
else
    echo -e "${GREEN}RESTORED INSTALL:${NC} Login using the admin account from your backup file."
fi

echo -e " >> OPAC URL:  https://$OPAC_DOMAIN"
echo -e " >> Staff URL: https://$STAFF_DOMAIN"
echo -e " >> DB User:   $ADMIN_USER"
echo -e " >> DB Pass:   $ADMIN_PASS"
echo -e "-------------------------------------------"
