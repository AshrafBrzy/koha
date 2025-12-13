Koha Golden Installer - The Comprehensive Solution (v28.0)

🇬🇧 English Section

About This Project

This script is the culmination of 24 years of experience in Information Systems.

It is not just an installer; it is a production-grade orchestration tool designed to deploy the Koha Integrated Library System (ILS) on Ubuntu 24.04 LTS with enterprise-level stability, security, and performance.

It addresses the most complex challenges faced by librarians and system administrators, including character encoding issues, WAF configuration, and resource optimization.

Key Features

1. Intelligent Auto-Tuning

Automatically detects CPU cores and RAM size.

Calculates and applies optimal settings for MariaDB (InnoDB Buffer) and Apache (MaxRequestWorkers) based on available hardware.

2. Advanced Security Shield (WAF)

Installs and configures ModSecurity with OWASP Core Rule Set (CRS).

Includes a custom "Smart Whitelist" to prevent False Positives (Error 500) on static files (CSS/JS) and internal Koha operations.

Blocks malicious bots and scrapers automatically.

3. Advanced Arabic Search Engine (Zebra ICU Optimization)

Intelligent Normalization: Unifies various forms of Alef (أ, إ, آ -> ا), Yeh (ى -> ي), and Ta Marbuta (ة -> ه) to ensure accurate retrieval regardless of spelling variations.

Smart Prefix Removal: Strips definite articles (Al-) and conjunctions (Wal-, Fal-, Kal-, Bal-, Lil-) while preserving the root word for better indexing.

Root Protection Mechanism: Includes a comprehensive exclusion list (over 50+ rules) to protect words where "Al" is part of the root (e.g., Allah, Alwan, Elias) from being incorrectly stripped.

Synonym Mapping: Enhances search recall by mapping common variations (e.g., Jawal = Mobile = Phone, Laptop = Computer) to unified terms.

4. Complete Arabic Language Support

Solves the notorious "missing CSS/JS" issue in RTL interfaces.

Configures Perl locales/encoding environments correctly.

Includes a Fail-Safe mechanism to generate fallback CSS files if the translation build fails.

5. Production Ready

Automated Let's Encrypt SSL/HTTPS setup.

Fixes permission issues between Apache (www-data) and Koha users.

Cleans up conflicting configurations and legacy instances.

Prerequisites

A fresh installation of Ubuntu 24.04 LTS.

Root access (sudo).

A valid Domain Name.

CRITICAL: Create valid DNS 'A' records for your OPAC and Staff subdomains pointing to the server IP before running the script.

Installation Steps

1. Download the script:

wget --no-check-certificate [https://raw.githubusercontent.com/AshrafBrzy/koha/main/koha_installer_27.sh](https://raw.githubusercontent.com/AshrafBrzy/koha/main/koha_installer_27.sh)


2. Edit configuration (Domain & Email):

nano koha_installer_27.sh


3. Make executable:

chmod +x koha_installer_27.sh


4. Run installer:

sudo bash koha_installer_27.sh


5. Finalize:

Follow the on-screen prompts. The system will be ready in minutes.

Developer Information

Ashraf Brzy

Senior Information Systems Expert (24+ Years Experience)

Email: ashraf@adrle.com

Mobile: +20 121 115 9150

License: Creative Commons (CC BY-SA 4.0)

🇪🇬 القسم العربي

مثبت نظام كوها الذهبي - الحل الشامل (الإصدار 28.0)

نبذة عن المشروع

هذا السكريبت هو نتاج 24 عاماً من الخبرة العميقة في مجال نظم المعلومات.

هو ليس مجرد أداة تثبيت عادية، بل هو نظام متكامل لإعداد وتشغيل نظام إدارة المكتبات "كوها" (Koha) على خوادم Ubuntu 24.04 LTS بمعايير المؤسسات الكبرى.

تم تصميم هذا العمل لحل المشاكل التقنية المعقدة التي تواجه مديري الأنظمة، مثل مشاكل الترميز العربي، تعارض جدران الحماية، وضبط الأداء.

أهم المميزات والخصائص

1. محرك بحث عربي ذكي (Zebra ICU Optimization)

التوحيد القياسي (Normalization): توحيد أشكال الألف (أ، إ، آ) والياء والتاء المربوطة لضمان دقة النتائج بغض النظر عن طريقة الكتابة.

المعالجة الذكية للسوابق: إزالة "ال" التعريف ومشتقاتها (والـ، فالـ، كالـ، بالـ، للـ) للوصول إلى جذور الكلمات بدقة.

نظام حماية الجذور: قائمة استثناءات ضخمة لمنع حذف "ال" من الكلمات الأصلية (مثل: الله، ألوان، إلياس، ألم) لضمان عدم تشوه المعنى.

معالجة المترادفات: ربط المصطلحات المختلفة (جوال = محمول، حاسوب = كمبيوتر) لضمان استرجاع شامل للموضوعات.

2. الضبط الذكي للأداء (Auto-Tuning)

يقوم السكريبت بفحص عتاد الخادم (الذاكرة والمعالج) تلقائياً.

يقوم بحساب وتطبيق الإعدادات المثالية لقاعدة البيانات (MariaDB) وخادم الويب (Apache) لضمان أقصى سرعة واستغلال للموارد.

3. درع الحماية المتقدم (Security)

تفعيل جدار الحماية ModSecurity مع قواعد OWASP العالمية.

يتضمن "قائمة استثناءات ذكية" تمنع حظر ملفات النظام (خطأ 500 الشهير) وتسمح بمرور ملفات التصميم بسلام.

حظر الروبوتات الضارة (Bots) التي تستهلك موارد السيرفر.

4. دعم كامل للواجهة العربية

حل جذري لمشكلة اختفاء التنسيق (CSS) في الواجهة العربية.

ضبط بيئة الترميز (Perl Locales) لضمان ظهور النصوص العربية بشكل صحيح.

نظام "شبكة أمان" يقوم بإنشاء ملفات بديلة في حال فشل توليد ملفات اللغة.

5. جاهزية فورية للعمل (Production Ready)

تفعيل شهادات الأمان (SSL/HTTPS) تلقائياً عبر Let's Encrypt.

إصلاح شامل لصلاحيات المستخدمين والملفات.

تنظيف أي نسخ قديمة أو ملفات متعارضة.

متطلبات التشغيل

خادم جديد بنظام Ubuntu 24.04 LTS.

صلاحيات الجذر (Root/Sudo).

اسم نطاق (Domain Name) فعال.

هام جداً: يجب إنشاء سجلات DNS (من نوع A Record) للدومينات الفرعية (للموظفين والجمهور) وتوجيهها لعنوان IP الخادم قبل البدء.

خطوات التثبيت

1. تحميل السكريبت:

wget --no-check-certificate [https://raw.githubusercontent.com/AshrafBrzy/koha/main/koha_installer_27.sh](https://raw.githubusercontent.com/AshrafBrzy/koha/main/koha_installer_27.sh)


2. تعديل البيانات (الدومين والإيميل):

nano koha_installer_27.sh


3. تشغيل المثبت مباشرة:

sudo bash koha_installer_27.sh


4. الانتهاء:

انتظر بضع دقائق حتى تظهر لك بيانات الدخول النهائية.

عن المطور

أشرف برزي

خبير نظم معلومات (خبرة أكثر من 24 عاماً)

البريد الإلكتروني: ashraf@adrle.com

هاتف: 00201211159150

الرخصة: المشاع الإبداعي (CC BY-SA 4.0)
