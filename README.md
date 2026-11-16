# إدارة خطوط العملاء — Line Manager

تطبيق Flutter لأندرويد لإدارة عملاء وخطوط Orange والباقات والاستحقاقات الشهرية والمدفوعات والإيصالات.

## المطور
**ENG. Mark Eshak — المهندس مارك اسحق — Infinity MEN2**  
Software Engineer — تطوير هندسة البرمجيات وأنظمة سطح المكتب المتكاملة لإدارة الأعمال.

## المتطلبات
- Flutter stable 3.22 أو أحدث (يفضّل أحدث إصدار مستقر).
- Android Studio مع Android SDK وCommand-line Tools.
- Java/JDK المتوافق مع إصدار Android Gradle Plugin الذي ينشئه Flutter.
- Windows PowerShell 5.1 أو PowerShell 7.

## إنشاء نسخة Android
يحتوي المشروع على سكربت Windows يقوم بتوليد ملفات Android القياسية بواسطة Flutter المثبّت، ثم ينسخ إعدادات التطبيق ويشغّل التوليد والتحليل والاختبارات والبناء:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\tools\build_android.ps1
```

الناتج المتوقع بعد نجاح كل الخطوات:
`build\app\outputs\flutter-apk\app-release.apk`

لا يعتبر APK صالحًا للتسليم إلا إذا انتهت خطوات `flutter analyze` و`flutter test` و`flutter build apk --release` دون أخطاء.

## الإعداد السحابي الاختياري
1. أنشئ مشروعًا في Supabase.
2. فعّل Anonymous Sign-Ins في إعدادات Authentication.
3. نفّذ `supabase/schema.sql` في SQL Editor.
4. ابنِ التطبيق بالقيمتين العامتين الخاصتين بالمشروع:

```powershell
.\tools\build_android.ps1 -SupabaseUrl "https://YOUR_PROJECT.supabase.co" -SupabaseAnonKey "YOUR_SUPABASE_ANON_KEY"
```

استخدم المفتاح العام anon/publishable فقط، ولا تستخدم `service_role` داخل تطبيق الهاتف.

**تنبيه مهم عن الاستعادة:** المزامنة الحالية ترفع التغييرات المحلية إلى Supabase (نسخة سحابية مرآتية)، لكنها لا تنزّل قاعدة البيانات تلقائيًا إلى تثبيت جديد. كما أن تسجيل الدخول المجهول مرتبط بالتثبيت الحالي. لذلك صدّر ملف JSON بانتظام واحتفظ به خارج الهاتف؛ استيراد JSON هو مسار الاستعادة المتاح حاليًا. لا تعتمد على المزامنة السحابية وحدها لاستعادة البيانات بعد حذف التطبيق أو تغيير الهاتف.

## القواعد المالية
- كل المبالغ تُخزَّن كأعداد صحيحة بالقرش؛ 1 جنيه = 100 قرش.
- كل خط له سجل مالي مستقل، وكل شهر له استحقاق مستقل مع لقطة للسعر واسم الباقة.
- تغيير سعر الباقة يسري من الشهر المحدد على الاستحقاقات غير المسددة، ولا يغيّر الإيصالات أو الدفعات التاريخية.
- الدفع الجزئي والدفع المقدم للشهور المختارة مدعومان. عند اختيار شهر مستقبلي بعيد، ينشئ النظام الدورات الشهرية الوسيطة المفقودة حتى لا تختفي استحقاقات الشهور الواقعة بينها.
- أي زيادة خارج قيمة الشهور المختارة تسجّل كرصد مقدم غير موزع على الخط؛ يظهر الرصيد في تفاصيل الخط والإيصال، لكنه لا يُخصم تلقائيًا من استحقاق لاحق في هذه النسخة، ولا يُعد أرباحًا.
- إلغاء دفعة يحتفظ بالسجل ويعيد المبالغ الموزعة إلى الاستحقاقات.
- لا تُحذف سجلات العميل أو الخط أو المدفوعات حذفًا متسلسلًا.

## واتساب
يُنشأ الإيصال كصورة PNG مستقلة ويُفتح Android Sharesheet لمشاركة الصورة. يجب على ماما اختيار WhatsApp والمحادثة ثم الضغط على إرسال؛ التطبيق لا يرسل رسائل تلقائيًا ولا يستطيع ضمان فتح محادثة بعينها على كل إصدار من WhatsApp.

## النسخ الاحتياطي المحلي
من الإعدادات استخدم «تصدير نسخة JSON ومشاركتها خارج الجهاز»، واحفظ الملف في مكان آمن خارج الهاتف. عند الاستعادة اختر «استيراد نسخة احتياطية من ملف JSON». عملية الاستيراد تستبدل بيانات التطبيق الحالية، لذلك لا تنفذها إلا بعد التأكد من اختيار النسخة الصحيحة.

## الحالة الفنية
تم إجراء مراجعة وإصلاحات ثابتة على ملفات المصدر، لكن لم يتوفر Flutter/Dart SDK في بيئة إعداد هذه الحزمة؛ لذلك لم يتم تشغيل `pub get` أو `build_runner` أو `analyze` أو الاختبارات أو بناء APK هنا. يجب تنفيذ سكربت البناء على جهاز Windows مجهز، ثم معالجة أي خطأ يظهر قبل استخدام بيانات حقيقية.

## Build APK automatically with GitHub Actions

This repository includes `.github/workflows/build-apk.yml`. After the source is pushed to the `main` or `master` branch, GitHub Actions prepares the Android Gradle project, generates Drift code, runs tests and analysis, builds the release APK, and uploads it as an Actions artifact. You can also start the workflow manually from the **Actions** tab using **Build Line Manager APK** → **Run workflow**.

When the workflow succeeds, open its run, scroll to **Artifacts**, and download `line-manager-android-apk`. The APK inside is `app-release.apk`.

The workflow builds without Supabase configuration, so the app uses its local database. Do not add a Supabase service-role key to GitHub or to the APK. Configure cloud sync separately only after its schema, access policies, and restore flow have been validated.
