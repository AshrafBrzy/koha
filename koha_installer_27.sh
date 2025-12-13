#!/bin/bash

# =================================================================
# سكربت تثبيت كوها (Koha) الشامل - النسخة الذهبية 29.0
# المميزات: تثبيت تفاعلي + حفظ الإعدادات + دعم عربي متقدم + حماية
# =================================================================

# ملف حفظ الإعدادات (Log/Config)
CONFIG_FILE="koha_installer.conf"

# إعداد الألوان
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# تفعيل التوقف عند الأخطاء الحرجة
set -e
handle_error() {
    echo -e "${RED}حدث خطأ غير متوقع في السطر $1.${NC}"
    exit 1
}
trap 'handle_error $LINENO' ERR

# --- دالة التكوين التفاعلي (Interactive Config) ---
setup_config() {
    echo -e "${GREEN}>>> جاري تحميل الإعدادات...${NC}"
    
    # 1. التحقق من وجود ملف إعدادات سابق
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${YELLOW}--------------------------------------------------${NC}"
        echo -e "${YELLOW}⚠️  تم العثور على إعدادات محفوظة مسبقاً:${NC}"
        echo -e "   1. اسم المكتبة (Instance): ${GREEN}$INSTANCE${NC}"
        echo -e "   2. الدومين الرئيسي:        ${GREEN}$DOMAIN${NC}"
        echo -e "   3. دومين الجمهور (OPAC):   ${GREEN}$OPAC_DOMAIN${NC}"
        echo -e "   4. دومين الموظفين (Staff): ${GREEN}$STAFF_DOMAIN${NC}"
        echo -e "   5. البريد الإلكتروني:      ${GREEN}$EMAIL${NC}"
        echo -e "${YELLOW}--------------------------------------------------${NC}"
        
        read -p "هل تريد الاستمرار باستخدام هذه الإعدادات؟ (y/n) [y]: " USE_EXISTING
        USE_EXISTING=${USE_EXISTING:-y}
        
        if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}تم اعتماد الإعدادات المحفوظة.${NC}"
            return
        fi
    fi

    # 2. طلب البيانات من المستخدم في حال عدم وجودها أو طلب التغيير
    echo -e "\n${BLUE}>>> فضلاً، أدخل بيانات التثبيت الجديدة:${NC}"
    
    # اسم المكتبة
    read -p "أدخل اسم المكتبة المختصر (مثال: msa) [${INSTANCE:-library}]: " INPUT_INSTANCE
    INSTANCE=${INPUT_INSTANCE:-${INSTANCE:-library}}
    
    # الدومين الرئيسي
    read -p "أدخل الدومين الرئيسي (مثال: example.com) [${DOMAIN}]: " INPUT_DOMAIN
    DOMAIN=${INPUT_DOMAIN:-$DOMAIN}
    
    # دومين الجمهور (نقترح قيمة افتراضية ذكية)
    DEFAULT_OPAC="lib.$DOMAIN"
    if [ ! -z "$OPAC_DOMAIN" ]; then DEFAULT_OPAC="$OPAC_DOMAIN"; fi
    read -p "أدخل دومين الجمهور (OPAC) [$DEFAULT_OPAC]: " INPUT_OPAC
    OPAC_DOMAIN=${INPUT_OPAC:-$DEFAULT_OPAC}
    
    # دومين الموظفين
    DEFAULT_STAFF="staff.$DOMAIN"
    if [ ! -z "$STAFF_DOMAIN" ]; then DEFAULT_STAFF="$STAFF_DOMAIN"; fi
    read -p "أدخل دومين الموظفين (Staff) [$DEFAULT_STAFF]: " INPUT_STAFF
    STAFF_DOMAIN=${INPUT_STAFF:-$DEFAULT_STAFF}
    
    # الإيميل
    read -p "أدخل البريد الإلكتروني (لإشعارات SSL) [${EMAIL}]: " INPUT_EMAIL
    EMAIL=${INPUT_EMAIL:-$EMAIL}

    # التحقق من القيم الفارغة
    if [[ -z "$INSTANCE" || -z "$DOMAIN" || -z "$OPAC_DOMAIN" || -z "$STAFF_DOMAIN" || -z "$EMAIL" ]]; then
        echo -e "${RED}خطأ: جميع البيانات مطلوبة للاستمرار!${NC}"
        exit 1
    fi

    # 3. حفظ الإعدادات في الملف للعودة إليها لاحقاً
    echo -e "# Koha Installer Configuration - Last saved: $(date)" > "$CONFIG_FILE"
    echo "INSTANCE=\"$INSTANCE\"" >> "$CONFIG_FILE"
    echo "DOMAIN=\"$DOMAIN\"" >> "$CONFIG_FILE"
    echo "OPAC_DOMAIN=\"$OPAC_DOMAIN\"" >> "$CONFIG_FILE"
    echo "STAFF_DOMAIN=\"$STAFF_DOMAIN\"" >> "$CONFIG_FILE"
    echo "EMAIL=\"$EMAIL\"" >> "$CONFIG_FILE"
    
    echo -e "${GREEN}تم حفظ الإعدادات في ملف '$CONFIG_FILE' لاستخدامها مستقبلاً.${NC}"
}

# --- بداية التنفيذ الفعلي ---

echo -e "${GREEN}>>> تشغيل معالج التثبيت (النسخة 29.0 - التفاعلية)...${NC}"

# 1. التحقق من الروت
if [ "$EUID" -ne 0 ]; then echo -e "${RED}يجب التشغيل بصلاحيات sudo${NC}"; exit 1; fi

# 2. استدعاء دالة الإعدادات (هنا يحدث السحر!)
setup_config

# روابط ملفات إعدادات البحث العربي (ثابتة)
ICU_URL="https://raw.githubusercontent.com/AshrafBrzy/koha/main/words-icu.xml"
IDX_URL="https://raw.githubusercontent.com/AshrafBrzy/koha/main/default.idx"

# 3. فحص الموارد وضبط المتغيرات (Auto-Tuning)
echo -e "${BLUE}[1/11] فحص الموارد وضبط الأداء...${NC}"
CPU_CORES=$(nproc)
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
# تخصيص 45% من الرام للقاعدة
DB_RAM_MB=$((TOTAL_RAM_MB * 45 / 100))
if [ "$DB_RAM_MB" -gt 1024 ]; then
    INNODB_SIZE="$((DB_RAM_MB / 1024))G"
else
    INNODB_SIZE="${DB_RAM_MB}M"
fi
# عمال Plack
PLACK_WORKERS=$CPU_CORES
[ "$PLACK_WORKERS" -gt 8 ] && PLACK_WORKERS=8
[ "$PLACK_WORKERS" -lt 2 ] && PLACK_WORKERS=2
# عمليات أباتشي
MAX_REQUEST_WORKERS=$(((TOTAL_RAM_MB - DB_RAM_MB - 1024) / 100))
[ "$MAX_REQUEST_WORKERS" -lt 10 ] && MAX_REQUEST_WORKERS=10

echo -e "   - MariaDB Buffer: $INNODB_SIZE"
echo -e "   - Plack Workers:  $PLACK_WORKERS"
echo -e "   - Apache Clients: $MAX_REQUEST_WORKERS"

# 4. ضبط اللغة والترميز
echo -e "${BLUE}[2/11] ضبط اللغة والترميز...${NC}"
apt-get update -qq
apt-get install -y locales
locale-gen en_US.UTF-8 ar_EG.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PERL_UNICODE=S

# 5. إعداد المستودعات والأدوات
echo -e "${BLUE}[3/11] تجهيز المستودعات والأدوات...${NC}"
apt-get install -y software-properties-common vim wget gnupg curl git unzip xmlstarlet net-tools build-essential openssl
add-apt-repository -y universe || true
apt-get update -qq

# 6. تثبيت كوها والحزم
echo -e "${BLUE}[4/11] تثبيت الحزم...${NC}"
wget -qO - https://debian.koha-community.org/koha/gpg.asc | gpg --dearmor --yes -o /usr/share/keyrings/koha-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/koha-keyring.gpg] http://debian.koha-community.org/koha stable main' | tee /etc/apt/sources.list.d/koha.list
apt-get update -qq

# تثبيت الحزم الأساسية + مكتبات Perl إضافية
apt-get install -y koha-common mariadb-server apache2 libapache2-mod-security2 modsecurity-crs certbot python3-certbot-apache memcached libgd-barcode-perl libtemplate-plugin-json-escape-perl libtemplate-plugin-stash-perl libutf8-all-perl libcgi-emulate-psgi-perl libcgi-compile-perl

# 7. تطبيق إعدادات الأداء
echo -e "${BLUE}[5/11] تطبيق إعدادات الأداء...${NC}"
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

# 8. إعداد ModSecurity (مع القواعد المستثناة)
echo -e "${BLUE}[6/11] إعداد الحماية (ModSecurity)...${NC}"
cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf || true
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf
sed -i 's/SecResponseBodyAccess On/SecResponseBodyAccess Off/' /etc/modsecurity/modsecurity.conf

# إنشاء ملف استثناءات قوي
cat <<EOF > /usr/share/modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
SecRule REMOTE_ADDR "@ipMatch 127.0.0.1" "id:9999001,phase:1,pass,nolog,ctl:ruleEngine=Off"
SecRule REQUEST_FILENAME "\.(?:css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map|json)(\?.*)?$" "id:9999002,phase:1,pass,nolog,ctl:ruleEngine=Off,ctl:auditEngine=Off"
SecRule REQUEST_URI "@beginsWith /cgi-bin/koha/reports/" "id:9999003,phase:2,pass,nolog,ctl:ruleRemoveById=942100"
EOF

# إنشاء ملف CRS Setup
if [ ! -f "/etc/modsecurity/crs-setup.conf" ]; then
    echo "SecDefaultAction \"phase:1,log,auditlog,pass\"" > /etc/modsecurity/crs-setup.conf
fi

# ربط القواعد في Apache
if ! grep -q "REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf" /etc/apache2/mods-available/security2.conf; then
    echo "IncludeOptional /usr/share/modsecurity-crs/rules/*.conf" >> /etc/apache2/mods-available/security2.conf
fi
sort -u -o /etc/apache2/mods-available/security2.conf /etc/apache2/mods-available/security2.conf

a2enmod security2 headers rewrite cgi proxy_http deflate || true

# 9. إنشاء كوها
echo -e "${BLUE}[7/11] إنشاء المكتبة ($INSTANCE)...${NC}"
systemctl restart mariadb memcached apache2
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('');" || true
mysql -e "DELETE FROM mysql.user WHERE User='';" || true
mysql -e "FLUSH PRIVILEGES;" || true

if ! koha-list | grep -q "^$INSTANCE$"; then
    koha-create --create-db "$INSTANCE"
fi

# 10. تحسين البحث العربي (Zebra ICU Optimization)
echo -e "${BLUE}[8/11] تحسين محرك البحث للغة العربية...${NC}"
ZEBRA_CONF_DIR="/etc/koha/zebradb"

echo -e "${YELLOW}تحميل words-icu.xml...${NC}"
wget --no-check-certificate -O "$ZEBRA_CONF_DIR/etc/words-icu.xml" "$ICU_URL" || echo -e "${RED}فشل تحميل ملف ICU.${NC}"

echo -e "${YELLOW}تحميل default.idx وتفعيله...${NC}"
wget --no-check-certificate -O "$ZEBRA_CONF_DIR/etc/default.idx" "$IDX_URL" || echo -e "${RED}فشل تحميل ملف default.idx.${NC}"

# 11. إعداد كوها واللغة
echo -e "${BLUE}[9/11] تهيئة كوها واللغة العربية...${NC}"
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

echo -e "${YELLOW}تثبيت اللغة العربية...${NC}"
export KOHA_CONF="$CONF_XML"
export PERL5LIB=/usr/share/koha/lib
if ! koha-translate --install ar-Arab; then
    echo -e "${YELLOW}إعادة المحاولة مع التحديث...${NC}"
    koha-translate --update ar-Arab || true
fi

CSS_RTL="/var/lib/koha/$INSTANCE/css/staff-global-rtl.css"
if [ ! -f "$CSS_RTL" ]; then
    echo -e "${YELLOW}تطبيق الحل البديل لملف CSS...${NC}"
    touch "$CSS_RTL"
    chown "$INSTANCE-koha:$INSTANCE-koha" "$CSS_RTL"
fi

echo -e "${YELLOW}إعادة بناء فهارس البحث (Zebra Reindex)...${NC}"
koha-rebuild-zebra -v -f "$INSTANCE"

koha-plack --enable "$INSTANCE"
koha-plack --start "$INSTANCE"

# 12. ضبط Apache النهائي و SSL
echo -e "${BLUE}[10/11] ضبط Apache و SSL...${NC}"
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

chown -R "$INSTANCE-koha:$INSTANCE-koha" "/var/lib/koha/$INSTANCE"
chmod -R g+rX "/var/lib/koha/$INSTANCE"
usermod -a -G "${INSTANCE}-koha" www-data

a2dissite 000-default || true
a2ensite "$INSTANCE"
systemctl restart apache2

# 13. تفعيل HTTPS
echo -e "${BLUE}[11/11] تفعيل HTTPS...${NC}"
# التأكد من صحة الإيميل قبل الطلب
if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
    echo -e "${YELLOW}تحذير: الإيميل المدخل غير صالح، سيتم طلب الشهادة بدون إيميل.${NC}"
    CERT_CMD="certbot --apache -d $OPAC_DOMAIN -d $STAFF_DOMAIN --register-unsafely-without-email --agree-tos --redirect"
else
    CERT_CMD="certbot --apache -d $OPAC_DOMAIN -d $STAFF_DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect"
fi

$CERT_CMD || echo -e "${RED}فشل SSL (تأكد من DNS).${NC}"

ADMIN_PASS=$(xmlstarlet sel -t -v 'yazgfs/config/pass' /etc/koha/sites/$INSTANCE/koha-conf.xml || echo "Error")
ADMIN_USER="koha_$INSTANCE"

echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}   تم التثبيت بنجاح (النسخة الذهبية 29.0)   ${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "بيانات الدخول:"
echo -e "رابط الجمهور:  https://$OPAC_DOMAIN"
echo -e "رابط الموظفين: https://$STAFF_DOMAIN"
echo -e "المستخدم:      $ADMIN_USER"
echo -e "كلمة المرور:   $ADMIN_PASS"
echo -e "-------------------------------------------"
