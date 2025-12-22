#!/bin/bash

# 1. تعريف المسارات (تأكد من اسم النسخة)
INSTANCE="mpl"
CSS_PATH="/usr/share/koha/intranet/htdocs/intranet-tmpl/prog/css"

echo "--- Installing Prerequisites ---"
apt install -y npm
npm install -g rtlcss

echo "--- Generating RTL CSS Files ---"
cd $CSS_PATH

# توليد الملفات العربية من الإنجليزية
if [ -f "staff-global.css" ]; then
    rtlcss staff-global.css staff-global-rtl.css
    echo "Generated: staff-global-rtl.css"
fi

if [ -f "mainpage.css" ]; then
    rtlcss mainpage.css mainpage-rtl.css
    echo "Generated: mainpage-rtl.css"
fi

# ضبط الصلاحيات
chown root:root *-rtl.css
chmod 644 *-rtl.css

echo "--- Restarting Services ---"
service memcached restart
koha-plack --restart $INSTANCE

echo "--- DONE! Arabic Interface Fixed ---"
