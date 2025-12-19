#!/bin/bash

# =================================================================
# Koha Phased Installer - v34.0 (Two-Phase Deployment)
# المطور: أشرف برزي | License: CC BY-SA 4.0
# فكرة العمل: سكريبت واحد ينفذ التثبيت على مرحلتين منفصلتين حسب الطلب
# =================================================================

# --- System Constants ---
LOG_FILE="/var/log/koha_install.log"
CONFIG_FILE="koha_installer.conf"
ICU_URL="https://raw.githubusercontent.com/AshrafBrzy/koha/main/words-icu.xml"
IDX_URL="https://raw.githubusercontent.com/AshrafBrzy/koha/main/default.idx"

# روابط افتراضية (يمكن تركها فارغة)
DEFAULT_DB_URL=""

# --- Visual Settings ---
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'

# --- Prevent Apt Hangs ---
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
APT_OPTS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# --- Error Handling ---
set -e
handle_error() {
    echo -e "${RED}Error on line $1${NC}"
    exit 1
}
trap 'handle_error $LINENO' ERR

# --- Progress Bar Helper ---
draw_progress() {
    local width=40
    local percent=$1
    local filled=$((width * percent / 100))
    local empty=$((width - filled))
    printf -v bar "%*s" "$filled" ""; bar=${bar// /#}
    printf -v space "%*s" "$empty" ""; space=${space// /.}
    echo -ne "\r${CYAN}[${bar}${space}] ${percent}%${NC}"
}

# --- Configuration Wizard ---
setup_config() {
    clear
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}   Koha Phased Installer v34.0 (2-Stages)      ${NC}"
    echo -e "${GREEN}===============================================${NC}"

    # Load existing config
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${YELLOW}Existing Config Found:${NC}"
        echo -e "   Instance: ${GREEN}$INSTANCE${NC} | Domain: ${GREEN}$DOMAIN${NC}"
        echo -e "   DB URL: ${GREEN}${DB_URL:-None}${NC}"
        echo -e "${YELLOW}-------------------------------------------${NC}"
    fi

    # Phase Selection
    echo -e "\n${BLUE}Select Installation Phase:${NC}"
    echo -e "   ${GREEN}1)${NC} Phase 1: Basic Install + DB Restore + HTTP (Test Mode)"
    echo -e "   ${GREEN}2)${NC} Phase 2: Security (WAF) + Performance + SSL (Production Mode)"
    echo -e "   ${GREEN}0)${NC} Exit"
    read -p "Select [1/2/0]: " PHASE_CHOICE

    case $PHASE_CHOICE in
        1) INSTALL_PHASE=1 ;;
        2) INSTALL_PHASE=2 ;;
        *) exit 0 ;;
    esac

    # If Phase 1 (or config missing), ask for details
    if [ "$INSTALL_PHASE" -eq 1 ] || [ ! -f "$CONFIG_FILE" ]; then
        if [ "$INSTALL_PHASE" -eq 2 ]; then
            echo -e "${RED}Warning: Config file missing. Please re-enter details for Phase 2.${NC}"
        fi
        
        echo -e "\n${YELLOW}>>> Configuration Setup${NC}"
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

        # DB Import Question (Phase 1 Only)
        if [ "$INSTALL_PHASE" -eq 1 ]; then
            echo -e "\n${YELLOW}>>> Database Import${NC}"
            if [ ! -z "$DEFAULT_DB_URL" ]; then
                echo "Default: $DEFAULT_DB_URL"
                read -p "Use Default? (y/n/custom) [y]: " USE_DB
                if [[ "$USE_DB" =~ ^[Nn]$ ]]; then DB_URL=""; elif [[ "$USE_DB" =~ ^[Yy]$ || -z "$USE_DB" ]]; then DB_URL="$DEFAULT_DB_URL"; else DB_URL="$USE_DB"; fi
            else
                read -p "DB Dump URL (Empty for fresh install): " DB_URL
            fi
        fi

        # Save Config
        echo "INSTANCE=\"$INSTANCE\"" > "$CONFIG_FILE"
        echo "DOMAIN=\"$DOMAIN\"" >> "$CONFIG_FILE"
        echo "OPAC_DOMAIN=\"$OPAC_DOMAIN\"" >> "$CONFIG_FILE"
        echo "STAFF_DOMAIN=\"$STAFF_DOMAIN\"" >> "$CONFIG_FILE"
        echo "EMAIL=\"$EMAIL\"" >> "$CONFIG_FILE"
        echo "DB_URL=\"$DB_URL\"" >> "$CONFIG_FILE"
    fi
    
    # Export vars
    export INSTANCE DOMAIN OPAC_DOMAIN STAFF_DOMAIN EMAIL DB_URL
}

# =================================================================
# PHASE 1 FUNCTIONS: Basic Install & DB
# =================================================================

p1_system_prep() {
    echo ">> [P1] Prepping System..."
    # Anti-freeze logic
    killall apt apt-get 2>/dev/null || true
    rm /var/lib/apt/lists/lock 2>/dev/null || true
    dpkg --configure -a || true
    if [ -f /etc/needrestart/needrestart.conf ]; then
        sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
    fi
    
    # Basic locales
    apt-get update -qq
    apt-get install $APT_OPTS locales software-properties-common vim wget gnupg curl git unzip xmlstarlet net-tools build-essential openssl
    locale-gen en_US.UTF-8 ar_EG.UTF-8
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
}

p1_install_koha() {
    echo ">> [P1] Installing Koha Packages..."
    wget -qO - https://debian.koha-community.org/koha/gpg.asc | gpg --dearmor --yes -o /usr/share/keyrings/koha-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/koha-keyring.gpg] http://debian.koha-community.org/koha stable main' | tee /etc/apt/sources.list.d/koha.list
    apt-get update -qq
    # Note: Installing ModSecurity packages here but NOT enabling them yet
    apt-get install $APT_OPTS koha-common mariadb-server apache2 libapache2-mod-security2 modsecurity-crs certbot python3-certbot-apache memcached libgd-barcode-perl libtemplate-plugin-json-escape-perl libtemplate-plugin-stash-perl libutf8-all-perl libcgi-emulate-psgi-perl libcgi-compile-perl
}

p1_create_instance() {
    echo ">> [P1] Creating Instance ($INSTANCE)..."
    systemctl restart mariadb memcached apache2
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('');" || true
    mysql -e "DELETE FROM mysql.user WHERE User='';" || true
    mysql -e "FLUSH PRIVILEGES;" || true

    if ! koha-list | grep -q "^$INSTANCE$"; then
        koha-create --create-db "$INSTANCE"
    fi
}

p1_import_db() {
    echo ">> [P1] Database Import & Upgrade..."
    if [ ! -z "$DB_URL" ]; then
        TEMP_FILE="/tmp/koha_import.sql"
        if wget --no-check-certificate -O "$TEMP_FILE" "$DB_URL"; then
            if [[ "$TEMP_FILE" == *.gz ]]; then
                mv "$TEMP_FILE" "$TEMP_FILE.gz"
                gunzip -f "$TEMP_FILE.gz"
                TEMP_FILE="/tmp/koha_import.sql"
            fi
            
            echo "   - Restoring SQL..."
            koha-mysql "$INSTANCE" < "$TEMP_FILE"
            
            echo "   - Upgrading Schema..."
            koha-upgrade-schema "$INSTANCE"
            
            echo "   - Updating URLs..."
            koha-mysql "$INSTANCE" -e "UPDATE systempreferences SET value='http://$STAFF_DOMAIN' WHERE variable='staffClientBaseURL';"
            koha-mysql "$INSTANCE" -e "UPDATE systempreferences SET value='http://$OPAC_DOMAIN' WHERE variable='OPACBaseURL';"
            # Disable forced HTTPS redirect in DB if it exists from backup
            koha-mysql "$INSTANCE" -e "UPDATE systempreferences SET value='0' WHERE variable='OPACBaseURL';" 
        fi
    fi
}

p1_basic_config() {
    echo ">> [P1] Basic Configuration (HTTP Mode)..."
    
    # 1. Enable Plack
    sed -i "s/<plack_workers>.*<\/plack_workers>/<plack_workers>2<\/plack_workers>/g" "/etc/koha/sites/$INSTANCE/koha-conf.xml"
    koha-plack --enable "$INSTANCE" >/dev/null 2>&1
    koha-plack --start "$INSTANCE" || koha-plack --restart "$INSTANCE"

    # 2. Apache HTTP Config (No SSL, No ModSec)
    cat <<EOF > /etc/apache2/sites-available/$INSTANCE.conf
<VirtualHost *:80>
   ServerName $OPAC_DOMAIN
   Include /etc/koha/apache-shared.conf
   Include /etc/koha/apache-shared-opac-plack.conf
   SetEnv KOHA_CONF "/etc/koha/sites/$INSTANCE/koha-conf.xml"
   AssignUserID $INSTANCE-koha $INSTANCE-koha
   ErrorLog /var/log/koha/$INSTANCE/opac-error.log
</VirtualHost>

<VirtualHost *:80>
   ServerName $STAFF_DOMAIN
   Include /etc/koha/apache-shared.conf
   Include /etc/koha/apache-shared-intranet-plack.conf
   SetEnv KOHA_CONF "/etc/koha/sites/$INSTANCE/koha-conf.xml"
   AssignUserID $INSTANCE-koha $INSTANCE-koha
   ErrorLog /var/log/koha/$INSTANCE/intranet-error.log
</VirtualHost>
EOF

    # 3. Permissions
    chown -R "$INSTANCE-koha:$INSTANCE-koha" "/var/lib/koha/$INSTANCE"
    chmod -R g+rX "/var/lib/koha/$INSTANCE"
    usermod -a -G "${INSTANCE}-koha" www-data

    # 4. Activate
    a2enmod rewrite headers proxy_http cgi deflate
    a2dissite 000-default || true
    a2ensite "$INSTANCE"
    systemctl restart apache2
}

# =================================================================
# PHASE 2 FUNCTIONS: Hardening, Tuning, SSL
# =================================================================

p2_auto_tuning() {
    echo ">> [P2] Hardware Analysis & Tuning..."
    # Calculate Resources
    CPU_CORES=$(nproc)
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    DB_RAM_MB=$((TOTAL_RAM_MB * 45 / 100))
    if [ "$DB_RAM_MB" -gt 1024 ]; then INNODB_SIZE="$((DB_RAM_MB / 1024))G"; else INNODB_SIZE="${DB_RAM_MB}M"; fi
    PLACK_WORKERS=$CPU_CORES
    [ "$PLACK_WORKERS" -gt 8 ] && PLACK_WORKERS=8
    [ "$PLACK_WORKERS" -lt 2 ] && PLACK_WORKERS=2
    MAX_REQUEST_WORKERS=$(((TOTAL_RAM_MB - DB_RAM_MB - 1024) / 100))
    [ "$MAX_REQUEST_WORKERS" -lt 10 ] && MAX_REQUEST_WORKERS=10

    # Apply MariaDB
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

    # Apply Apache MPM
    cat <<EOF > /etc/apache2/mods-available/mpm_prefork.conf
<IfModule mpm_prefork_module>
    StartServers             5
    MinSpareServers          5
    MaxSpareServers          10
    MaxRequestWorkers        $MAX_REQUEST_WORKERS
    MaxConnectionsPerChild   0
</IfModule>
EOF

    # Update Plack Workers in Koha Config
    sed -i "s/<plack_workers>.*<\/plack_workers>/<plack_workers>$PLACK_WORKERS<\/plack_workers>/g" "/etc/koha/sites/$INSTANCE/koha-conf.xml"
    
    systemctl restart mariadb
}

p2_security_waf() {
    echo ">> [P2] Enabling ModSecurity WAF..."
    # Config files
    cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf || true
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf
    sed -i 's/SecResponseBodyAccess On/SecResponseBodyAccess Off/' /etc/modsecurity/modsecurity.conf

    # Whitelist
    cat <<EOF > /usr/share/modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
SecRule REMOTE_ADDR "@ipMatch 127.0.0.1" "id:9999001,phase:1,pass,nolog,ctl:ruleEngine=Off"
SecRule REQUEST_FILENAME "\.(?:css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map|json)(\?.*)?$" "id:9999002,phase:1,pass,nolog,ctl:ruleEngine=Off,ctl:auditEngine=Off"
SecRule REQUEST_URI "@beginsWith /cgi-bin/koha/reports/" "id:9999003,phase:2,pass,nolog,ctl:ruleRemoveById=942100"
SecRule REQUEST_URI "@beginsWith /.well-known/acme-challenge/" "id:9999004,phase:1,pass,nolog,ctl:ruleEngine=Off"
EOF

    # Setup CRS
    if [ ! -f "/etc/modsecurity/crs-setup.conf" ]; then
        echo "SecDefaultAction \"phase:1,log,auditlog,pass\"" > /etc/modsecurity/crs-setup.conf
    fi

    # Fix Apache Includes
    if ! grep -q "REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf" /etc/apache2/mods-available/security2.conf; then
        echo "IncludeOptional /usr/share/modsecurity-crs/rules/*.conf" >> /etc/apache2/mods-available/security2.conf
    fi
    sort -u -o /etc/apache2/mods-available/security2.conf /etc/apache2/mods-available/security2.conf

    a2enmod security2
}

p2_arabic_optimization() {
    echo ">> [P2] Applying Arabic Search & Fixes..."
    
    # Zebra ICU
    ZEBRA_CONF_DIR="/etc/koha/zebradb"
    wget --no-check-certificate -O "$ZEBRA_CONF_DIR/etc/words-icu.xml" "$ICU_URL"
    wget --no-check-certificate -O "$ZEBRA_CONF_DIR/etc/default.idx" "$IDX_URL"

    # Fix Perl Environment
    export PERL_UNICODE=S
    
    # Fix CSS (Fail Safe)
    mkdir -p "/var/lib/koha/$INSTANCE/css" "/var/lib/koha/$INSTANCE/js"
    chown -R "$INSTANCE-koha:$INSTANCE-koha" "/var/lib/koha/$INSTANCE"
    
    koha-translate --install ar-Arab || koha-translate --update ar-Arab
    
    CSS_RTL="/var/lib/koha/$INSTANCE/css/staff-global-rtl.css"
    if [ ! -f "$CSS_RTL" ]; then touch "$CSS_RTL"; chown "$INSTANCE-koha:$INSTANCE-koha" "$CSS_RTL"; fi
    
    # Reindex
    echo "   - Re-indexing Zebra..."
    koha-rebuild-zebra -v -f "$INSTANCE"
}

p2_ssl_final() {
    echo ">> [P2] Enabling SSL & Finalizing..."
    
    # Final Apache Config (With Rewrite Rules & ModSec Exceptions)
    FINAL_APACHE_OPTS='
       RewriteEngine On
       RewriteRule ^/opac-tmpl/(.*)_[0-9]+\.(css|js)$ /opac-tmpl/$1.$2 [L]
       RewriteRule ^/intranet-tmpl/(.*)_[0-9]+\.(css|js)$ /intranet-tmpl/$1.$2 [L]
       <IfModule security2_module>
          <LocationMatch "\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map|json)(\?.*)?$">
             SecRuleEngine Off
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

    systemctl restart apache2
    
    # Update DB URLs to HTTPS
    koha-mysql "$INSTANCE" -e "UPDATE systempreferences SET value='https://$STAFF_DOMAIN' WHERE variable='staffClientBaseURL';"
    koha-mysql "$INSTANCE" -e "UPDATE systempreferences SET value='https://$OPAC_DOMAIN' WHERE variable='OPACBaseURL';"

    # Certbot
    if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
        certbot --apache -d "$OPAC_DOMAIN" -d "$STAFF_DOMAIN" --register-unsafely-without-email --agree-tos --redirect --non-interactive
    else
        certbot --apache -d "$OPAC_DOMAIN" -d "$STAFF_DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
    fi
    
    # Final Restart
    koha-plack --restart "$INSTANCE"
    systemctl restart apache2 memcached
}


# =================================================================
# MAIN EXECUTION
# =================================================================

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Please run as sudo${NC}"; exit 1; fi

setup_config

# Initialize Log
if [ ! -f "$LOG_FILE" ]; then echo "--- Log Started ---" > "$LOG_FILE"; fi

if [ "$INSTALL_PHASE" -eq 1 ]; then
    echo -e "${CYAN}Starting Phase 1 (Basic Install)...${NC}"
    # Steps for Phase 1
    p1_system_prep >> "$LOG_FILE" 2>&1
    draw_progress 20
    p1_install_koha >> "$LOG_FILE" 2>&1
    draw_progress 40
    p1_create_instance >> "$LOG_FILE" 2>&1
    draw_progress 60
    p1_import_db >> "$LOG_FILE" 2>&1
    draw_progress 80
    p1_basic_config >> "$LOG_FILE" 2>&1
    draw_progress 100
    
    ADMIN_PASS=$(xmlstarlet sel -t -v 'yazgfs/config/pass' /etc/koha/sites/$INSTANCE/koha-conf.xml 2>/dev/null || echo "See Log")
    echo -e "\n${GREEN}Phase 1 Complete!${NC}"
    echo -e "Access your system via HTTP to verify data."
    echo -e "Staff URL: http://$STAFF_DOMAIN"
    echo -e "User: koha_$INSTANCE | Pass: $ADMIN_PASS"
    echo -e "${YELLOW}When ready, run the script again and select Phase 2.${NC}"

elif [ "$INSTALL_PHASE" -eq 2 ]; then
    echo -e "${CYAN}Starting Phase 2 (Security & Optimization)...${NC}"
    # Steps for Phase 2
    p2_auto_tuning >> "$LOG_FILE" 2>&1
    draw_progress 25
    p2_security_waf >> "$LOG_FILE" 2>&1
    draw_progress 50
    p2_arabic_optimization >> "$LOG_FILE" 2>&1
    draw_progress 75
    p2_ssl_final >> "$LOG_FILE" 2>&1
    draw_progress 100
    
    echo -e "\n${GREEN}Phase 2 Complete! System is fully secured.${NC}"
    echo -e "Staff URL: https://$STAFF_DOMAIN"
fi
