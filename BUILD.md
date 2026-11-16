# بناء APK على Windows

## 1) تثبيت الأدوات
1. ثبّت Git for Windows.
2. ثبّت Flutter SDK stable وأضف `C:\src\flutter\bin` (أو مجلد Flutter الفعلي) إلى PATH.
3. ثبّت Android Studio، ثم من SDK Manager ثبّت Android SDK Platform 34 أو أحدث وAndroid SDK Command-line Tools وPlatform-Tools.
4. أغلق PowerShell وافتح نافذة جديدة.

تحقق من الأدوات:

```powershell
flutter --version
dart --version
flutter doctor -v
flutter doctor --android-licenses
```

اقبل تراخيص Android، وأعد تشغيل `flutter doctor -v` حتى لا تظهر مشكلة في Android toolchain.

## 2) فك ضغط المشروع
- فك `line_manager_repaired.zip` إلى مسار بسيط مثل `C:\LineManager`.
- لا تشغّل المشروع من داخل ملف ZIP.
- افتح PowerShell داخل المجلد `C:\LineManager\line_manager`، وهو المجلد الذي يحتوي على `pubspec.yaml`.

## 3) إنشاء APK محلي دون Supabase
شغّل:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\tools\build_android.ps1
```

السكربت يقوم تلقائيًا بـ:
- إنشاء مجلد Android حقيقي باستخدام Flutter SDK المحلي.
- وضع Manifest وصلاحيات الإشعارات وملف الحفاظ على أيقونة التنبيه.
- تنزيل الاعتماديات.
- توليد Drift code.
- تنسيق ملفات Dart.
- تشغيل `flutter analyze`.
- تشغيل `flutter test`.
- بناء APK بنمط Release.
- إيقاف العملية وإظهار الخطوة التي فشلت إذا ظهر خطأ.

الملف الناتج:

`build\app\outputs\flutter-apk\app-release.apk`

## 4) تثبيت APK على الهاتف
1. انقل `app-release.apk` إلى هاتف Android.
2. افتح الملف من مدير الملفات.
3. وافق على السماح لمدير الملفات بتثبيت التطبيقات عند طلب Android ذلك.
4. ثبّت التطبيق وافتحه.
5. جرّب أولًا بيانات اختبار غير حقيقية: باقة، عميل، خط، دفعة، إيصال، تقرير، وتصدير/استيراد JSON.

## 5) إعداد النسخ السحابي الاختياري
1. أنشئ مشروع Supabase.
2. فعّل Anonymous Sign-Ins في Authentication.
3. افتح SQL Editor ونفّذ `supabase/schema.sql`.
4. ابنِ التطبيق هكذا:

```powershell
.\tools\build_android.ps1 -SupabaseUrl "https://YOUR_PROJECT.supabase.co" -SupabaseAnonKey "YOUR_SUPABASE_ANON_KEY"
```

استخدم المفتاح العام فقط. ممنوع وضع service_role key داخل APK.

**حد معروف:** المزامنة الحالية ترفع البيانات إلى Supabase ولا تنفذ استعادة/تنزيلًا كاملًا من السحابة إلى تثبيت جديد. احتفظ بنسخة JSON خارج الهاتف ولا تعتبر السحابة مسار الاستعادة الوحيد.

## 6) في حالة ظهور خطأ
- لا تحذف ملفات أو تغيّر إصدارات المكتبات عشوائيًا.
- انسخ أول رسالة خطأ حقيقية كاملة من PowerShell، وليس آخر سطر فقط.
- أرسلها مع ناتج `flutter doctor -v`.
- لا تسجّل بيانات العملاء الفعلية قبل نجاح التحليل والاختبارات والبناء والاختبار اليدوي.
