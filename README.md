<!-- ENGLISH SECTION -->
<div dir="ltr">
Koha Golden Installer - The Comprehensive Solution (v27.1)
About This Project
This script is the culmination of 24 years of experience in Information Systems. It is not just an installer; it is a production-grade orchestration tool designed to deploy the Koha Integrated Library System (ILS) on Ubuntu 24.04 LTS with enterprise-level stability, security, and performance.
It addresses the most complex challenges faced by librarians and system administrators, including character encoding issues, WAF configuration, and resource optimization.
Key Features
1. Intelligent Auto-Tuning:
    • Automatically detects CPU cores and RAM size.
    • Calculates and applies optimal settings for MariaDB (InnoDB Buffer) and Apache (MaxRequestWorkers) based on available hardware.
2. Advanced Security Shield (WAF):
    • Installs and configures ModSecurity with OWASP Core Rule Set (CRS).
    • Includes a custom "Smart Whitelist" to prevent False Positives (Error 500) on static files (CSS/JS) and internal Koha operations.
    • Blocks malicious bots and scrapers automatically.
3. Complete Arabic Language Support:
    • Solves the notorious "missing CSS/JS" issue in RTL interfaces.
    • Configures Perl locales/encoding environments correctly.
    • Includes a Fail-Safe mechanism to generate fallback CSS files if the translation build fails.
4. Production Ready:
    • Automated Let's Encrypt SSL/HTTPS setup.
    • Fixes permission issues between Apache (www-data) and Koha users.
    • Cleans up conflicting configurations and legacy instances.
Prerequisites
    • A fresh installation of Ubuntu 24.04 LTS.
    • Root access (sudo).
    • A valid Domain Name.
    • CRITICAL: Create valid DNS 'A' records for your OPAC and Staff subdomains pointing to the server IP before running the script.
Installation Steps
1. Download the script to your server:
wget [https://raw.githubusercontent.com/AshrafBrzy/koha/main/koha_installer_fixed.sh](https://raw.githubusercontent.com/AshrafBrzy/koha/main/koha_installer_fixed.sh)
2. Open the file and edit the top variables (Domain, Instance Name, Email):
nano koha_installer_fixed.sh
3. Make the script executable:
chmod +x koha_installer_fixed.sh
4. Run the installer:
sudo ./koha_installer_fixed.sh
5. Finalize:
Follow the on-screen prompts. The system will be ready in minutes.
Developer Information
Ashraf Brzy
    • Senior Information Systems Expert (24+ Years Experience)
    • Email: ashraf@adrle.com
    • Mobile: +20 121 115 9150
    • License: Creative Commons (CC BY-SA 4.0)
</div>
<!-- ARABIC SECTION -->
<div dir="rtl">
مثبت نظام كوها الذهبي - الحل الشامل (الإصدار 27.1)
نبذة عن المشروع
هذا السكريبت هو نتاج 24 عاماً من الخبرة العميقة في مجال نظم المعلومات. هو ليس مجرد أداة تثبيت عادية، بل هو نظام متكامل لإعداد وتشغيل نظام إدارة المكتبات "كوها" (Koha) على خوادم Ubuntu 24.04 LTS بمعايير المؤسسات الكبرى.
تم تصميم هذا العمل لحل المشاكل التقنية المعقدة التي تواجه مديري الأنظمة، مثل مشاكل الترميز العربي، تعارض جدران الحماية، وضبط الأداء.
أهم المميزات والخصائص
1. الضبط الذكي للأداء (Auto-Tuning):
    • يقوم السكريبت بفحص عتاد الخادم (الذاكرة والمعالج) تلقائياً.
    • يقوم بحساب وتطبيق الإعدادات المثالية لقاعدة البيانات (MariaDB) وخادم الويب (Apache) لضمان أقصى سرعة واستغلال للموارد.
2. درع الحماية المتقدم (Security):
    • تفعيل جدار الحماية ModSecurity مع قواعد OWASP العالمية.
    • يتضمن "قائمة استثناءات ذكية" تمنع حظر ملفات النظام (خطأ 500 الشهير) وتسمح بمرور ملفات التصميم بسلام.
    • حظر الروبوتات الضارة (Bots) التي تستهلك موارد السيرفر.
3. دعم كامل للغة العربية:
    • حل جذري لمشكلة اختفاء التنسيق (CSS) في الواجهة العربية.
    • ضبط بيئة الترميز (Perl Locales) لضمان ظهور النصوص العربية بشكل صحيح.
    • نظام "شبكة أمان" يقوم بإنشاء ملفات بديلة في حال فشل توليد ملفات اللغة.
4. جاهزية فورية للعمل (Production Ready):
    • تفعيل شهادات الأمان (SSL/HTTPS) تلقائياً عبر Let's Encrypt.
    • إصلاح شامل لصلاحيات المستخدمين والملفات.
    • تنظيف أي نسخ قديمة أو ملفات متعارضة.
متطلبات التشغيل
    • خادم جديد بنظام Ubuntu 24.04 LTS.
    • صلاحيات الجذر (Root/Sudo).
    • اسم نطاق (Domain Name) فعال.
    • هام جداً: يجب إنشاء سجلات DNS (من نوع A Record) للدومينات الفرعية (للموظفين والجمهور) وتوجيهها لعنوان IP الخادم قبل البدء.
خطوات التثبيت
1. قم بتحميل السكريبت على الخادم:
wget [https://raw.githubusercontent.com/AshrafBrzy/koha/main/koha_installer_fixed.sh](https://raw.githubusercontent.com/AshrafBrzy/koha/main/koha_installer_fixed.sh)
2. افتح الملف لتعديل البيانات الأساسية (اسم الدومين، الإيميل، اسم المكتبة):
nano koha_installer_fixed.sh
3. أعطِ السكريبت صلاحية التنفيذ:
chmod +x koha_installer_fixed.sh
4. شغل السكريبت:
sudo ./koha_installer_fixed.sh
5. الانتهاء:
انتظر بضع دقائق حتى تظهر لك بيانات الدخول النهائية.
عن المطور
أشرف برزي
    • خبير نظم معلومات (خبرة أكثر من 24 عاماً)
    • البريد الإلكتروني: ashraf@adrle.com
    • هاتف: 00201211159150
    • الرخصة: المشاع الإبداعي (CC BY-SA 4.0)
</div>
