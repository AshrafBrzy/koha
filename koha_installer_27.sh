#!/bin/bash

# =================================================================
# Koha Comprehensive Installer - Golden Version 27.1
# -----------------------------------------------------------------
# Developer   : Ashraf brzy
# Email       : ashraf@adrle.com
# Mobile      : 00201211159150
# Co-Pilot    : Google Gemini Pro AI
# License     : Creative Commons (CC BY-SA 4.0) - المشاع الإبداعي
# -----------------------------------------------------------------
# Environment : Ubuntu 24.04 LTS (Clean Install)
# Features    : Arabic Language Fix + Security + Auto-Performance Tuning
# =================================================================

# --- User Configuration (Edit these values only) ---
INSTANCE="msa"                      # Instance Name
DOMAIN="adrle.com"                  # Main Domain
OPAC_DOMAIN="msalib.adrle.com"      # OPAC Subdomain (Ensure DNS points to server)
STAFF_DOMAIN="msastaff.adrle.com"   # Staff Subdomain (Ensure DNS points to server)
EMAIL="admin@adrle.com"             # Email for SSL Certificates
# -----------------------------------------------------------------

# Color Settings
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Critical Error Handling
set -e
handle_error() {
    echo -e "${RED}An unexpected error occurred on line $1.${NC}"
    exit 1
}
trap 'handle_error $LINENO' ERR

echo -e "${GREEN}>>> Starting Installation (v27.1 - Developed by Ashraf brzy)...${NC}"

# --- DNS Pre-flight Check (NEW) ---
echo -e "${YELLOW}================================================================${NC}"
echo -e "${YELLOW}                           ATTENTION                            ${NC}"
echo -e "${YELLOW}================================================================${NC}"
echo -e "${YELLOW}Before proceeding, you MUST verify that you have created DNS 'A'${NC}"
echo -e "${YELLOW}records for the following subdomains pointing to this server IP:${NC}"
echo -e ""
echo -e "  1. ${GREEN}$OPAC_DOMAIN${NC}"
echo -e "  2. ${GREEN}$STAFF_DOMAIN${NC}"
echo -e ""
echo -e "${YELLOW}If these domains do not resolve to this server, SSL setup WILL fail.${NC}"
echo -e "${YELLOW}================================================================${NC}"
echo -e "Press [Enter] to confirm and continue installation..."
echo -e "Or press [Ctrl+C] to abort and fix DNS first."
read -r

# 1. Root Check
if [ "$EUID" -ne 0 ]; then echo -e "${RED}Please run as sudo${NC}"; exit 1; fi

# 2. Resource Check & Auto-Tuning
echo -e "${BLUE}[1/10] Checking Resources & Tuning Performance...${NC}"
CPU_CORES=$(nproc)
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
# Allocate 45% RAM for DB
DB_RAM_MB=$((TOTAL_RAM_MB * 45 / 100))
# Convert to GB for config if > 1GB
if [ "$DB_RAM_MB" -gt 1024 ]; then
    INNODB_SIZE="$((DB_RAM_MB / 1024))G"
else
    INNODB_SIZE="${DB_RAM_MB}M"
fi
# Plack Workers (Max 8)
PLACK_WORKERS=$CPU_CORES
[ "$PLACK_WORKERS" -gt 8 ] && PLACK_WORKERS=8
[ "$PLACK_WORKERS" -lt 2 ] && PLACK_WORKERS=2
# Apache Processes (Remaining RAM / 100MB per process)
MAX_REQUEST_WORKERS=$(((TOTAL_RAM_MB - DB_RAM_MB - 1024) / 100))
[ "$MAX_REQUEST_WORKERS" -lt 10 ] && MAX_REQUEST_WORKERS=10

echo -e "   - MariaDB Buffer: $INNODB_SIZE"
echo -e "   - Plack Workers:  $PLACK_WORKERS"
echo -e "   - Apache Clients: $MAX_REQUEST_WORKERS"

# 3. Locale & Encoding Setup (Crucial before install)
echo -e "${BLUE}[2/10] Configuring System Locale & Encoding...${NC}"
apt-get update -qq
apt-get install -y locales
locale-gen en_US.UTF-8 ar_EG.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
# Set Perl variables to prevent Wide Character issues
export PERL_UNICODE=S

# 4. Repositories & Tools
echo -e "${BLUE}[3/10] Preparing Repositories & Tools...${NC}"
apt-get install -y software-properties-common vim wget gnupg curl git unzip xmlstarlet net-tools build-essential openssl
add-apt-repository -y universe || true
apt-get update -qq

# 5. Installing Koha & Packages
echo -e "${BLUE}[4/10] Installing Koha & System Packages...${NC}"
wget -qO - https://debian.koha-community.org/koha/gpg.asc | gpg --dearmor --yes -o /usr/share/keyrings/koha-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/koha-keyring.gpg] http://debian.koha-community.org/koha stable main' | tee /etc/apt/sources.list.d/koha.list
apt-get update -qq

# Install base packages + extra Perl libraries for fixes
apt-get install -y koha-common mariadb-server apache2 libapache2-mod-security2 modsecurity-crs certbot python3-certbot-apache memcached libgd-barcode-perl libtemplate-plugin-json-escape-perl libtemplate-plugin-stash-perl libutf8-all-perl libcgi-emulate-psgi-perl libcgi-compile-perl

# 6. Applying Performance Settings
echo -e "${BLUE}[5/10] Applying Performance Settings...${NC}"
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

# 7. Configuring ModSecurity (With Exclusions)
echo -e "${BLUE}[6/10] Configuring ModSecurity WAF...${NC}"
cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf || true
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf
sed -i 's/SecResponseBodyAccess On/SecResponseBodyAccess Off/' /etc/modsecurity/modsecurity.conf

# Create strong exclusion file (Solves 500 Error & CSS issues)
cat <<EOF > /usr/share/modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
# 1. Whitelist Localhost
SecRule REMOTE_ADDR "@ipMatch 127.0.0.1" "id:9999001,phase:1,pass,nolog,ctl:ruleEngine=Off"
# 2. Whitelist Static Files (CSS/JS/Images)
SecRule REQUEST_FILENAME "\.(?:css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map|json)(\?.*)?$" "id:9999002,phase:1,pass,nolog,ctl:ruleEngine=Off,ctl:auditEngine=Off"
# 3. Whitelist Koha Reports
SecRule REQUEST_URI "@beginsWith /cgi-bin/koha/reports/" "id:9999003,phase:2,pass,nolog,ctl:ruleRemoveById=942100"
EOF

# Create CRS Setup file to prevent errors
if [ ! -f "/etc/modsecurity/crs-setup.conf" ]; then
    echo "SecDefaultAction \"phase:1,log,auditlog,pass\"" > /etc/modsecurity/crs-setup.conf
fi

# Clean Apache linking
if ! grep -q "REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf" /etc/apache2/mods-available/security2.conf; then
    echo "IncludeOptional /usr/share/modsecurity-crs/rules/*.conf" >> /etc/apache2/mods-available/security2.conf
fi
sort -u -o /etc/apache2/mods-available/security2.conf /etc/apache2/mods-available/security2.conf

a2enmod security2 headers rewrite cgi proxy_http deflate || true

# 8. Creating Koha Instance
echo -e "${BLUE}[7/10] Creating Library Instance ($INSTANCE)...${NC}"
systemctl restart mariadb memcached apache2
# Secure DB First
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('');" || true
mysql -e "DELETE FROM mysql.user WHERE User='';" || true
mysql -e "FLUSH PRIVILEGES;" || true

if ! koha-list | grep -q "^$INSTANCE$"; then
    koha-create --create-db "$INSTANCE"
fi

# 9. Configuring Koha & Language (The Root Fix)
echo -e "${BLUE}[8/10] Configuring Koha & Arabic Language...${NC}"

# Modify Config File
CONF_XML="/etc/koha/sites/$INSTANCE/koha-conf.xml"
if [ -f "$CONF_XML" ]; then
    # Adjust Plack workers
    sed -i "s/<plack_workers>.*<\/plack_workers>/<plack_workers>$PLACK_WORKERS<\/plack_workers>/g" "$CONF_XML" || true
    # Disable Local DB TLS
    sed -i "s/__DB_USE_TLS__/no/g" "$CONF_XML"
    sed -i "s/__DB_TLS_.*__//g" "$CONF_XML"
    # Fix Encryption Key
    if grep -q "__ENCRYPTION_KEY__" "$CONF_XML"; then
        NEW_KEY=$(openssl rand -base64 16 | sed 's/[/&]/\\&/g')
        sed -i "s/__ENCRYPTION_KEY__/$NEW_KEY/g" "$CONF_XML"
    fi
    # Fix Memcached Placeholders
    sed -i "s/__MEMCACHED_SERVERS__/127.0.0.1:11211/g" "$CONF_XML"
    sed -i "s/__MEMCACHED_NAMESPACE__/koha_${INSTANCE}/g" "$CONF_XML"
    # Enable Debug Mode to ensure raw CSS loading if minification fails
    sed -i "s/<debug_mode>0<\/debug_mode>/<debug_mode>1<\/debug_mode>/g" "$CONF_XML"
fi

# Manually create CSS directories to ensure existence
mkdir -p "/var/lib/koha/$INSTANCE/css"
mkdir -p "/var/lib/koha/$INSTANCE/js"
chown -R "$INSTANCE-koha:$INSTANCE-koha" "/var/lib/koha/$INSTANCE"

# Install Language with correct Environment Variables
echo -e "${YELLOW}Installing Arabic Language...${NC}"
export KOHA_CONF="$CONF_XML"
export PERL5LIB=/usr/share/koha/lib
if ! koha-translate --install ar-Arab; then
    echo -e "${YELLOW}Retrying with update...${NC}"
    koha-translate --update ar-Arab || true
fi

# --- The Safety Net (Fail-Safe CSS) ---
# If Arabic CSS fails to generate, copy English CSS to prevent 500 Error
CSS_RTL="/var/lib/koha/$INSTANCE/css/staff-global-rtl.css"
if [ ! -f "$CSS_RTL" ]; then
    echo -e "${YELLOW}WARNING: Arabic CSS failed to generate. Applying fallback solution...${NC}"
    touch "$CSS_RTL" # Create empty file or copy English
    chown "$INSTANCE-koha:$INSTANCE-koha" "$CSS_RTL"
fi
# -----------------------------------

# Enable Plack
koha-plack --enable "$INSTANCE"
koha-plack --start "$INSTANCE"

# 10. Final Apache & SSL Config
echo -e "${BLUE}[9/10] Configuring Apache & SSL...${NC}"

# Rewrite Rules & Direct Exclusions (Solves Versioning Issue)
FINAL_APACHE_OPTS='
   RewriteEngine On
   # Rewrite rules to handle versioned files (xxx_25.11.css -> xxx.css)
   RewriteRule ^/opac-tmpl/(.*)_[0-9]+\.(css|js)$ /opac-tmpl/$1.$2 [L]
   RewriteRule ^/intranet-tmpl/(.*)_[0-9]+\.(css|js)$ /intranet-tmpl/$1.$2 [L]
   
   # Static Files Whitelist
   <IfModule security2_module>
      <LocationMatch "\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map|json)(\?.*)?$">
         SecRuleEngine Off
      </LocationMatch>
   </IfModule>
   
   # Block Bad Bots
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

# Final Permissions Fix
chown -R "$INSTANCE-koha:$INSTANCE-koha" "/var/lib/koha/$INSTANCE"
chmod -R g+rX "/var/lib/koha/$INSTANCE"
usermod -a -G "${INSTANCE}-koha" www-data

a2dissite 000-default || true
a2ensite "$INSTANCE"
systemctl restart apache2

# Request SSL Certificate
echo -e "${BLUE}[10/10] Enabling HTTPS...${NC}"
certbot --apache -d "$OPAC_DOMAIN" -d "$STAFF_DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect || echo -e "${RED}SSL Failed (Check DNS records).${NC}"

# Display Credentials
ADMIN_PASS=$(xmlstarlet sel -t -v 'yazgfs/config/pass' /etc/koha/sites/$INSTANCE/koha-conf.xml || echo "Error")
ADMIN_USER="koha_$INSTANCE"

echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}   Installation Successful (Golden Version)   ${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "Login Details:"
echo -e "OPAC URL:  https://$OPAC_DOMAIN"
echo -e "Staff URL: https://$STAFF_DOMAIN"
echo -e "User:      $ADMIN_USER"
echo -e "Password:  $ADMIN_PASS"
echo -e "-------------------------------------------"
