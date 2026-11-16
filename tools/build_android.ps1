[CmdletBinding()]
param(
    [string]$SupabaseUrl = "",
    [string]$SupabaseAnonKey = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "الأمر '$Name' غير موجود. ثبّت Flutter/Dart وأضف مجلد flutter\bin إلى PATH ثم افتح PowerShell جديدًا."
    }
}

function Invoke-Step([string]$Name, [string[]]$Arguments) {
    Write-Host "`n============================================================" -ForegroundColor DarkCyan
    Write-Host "> $Name $($Arguments -join ' ')" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
    & $Name @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "فشلت الخطوة: $Name $($Arguments -join ' '). راجع رسالة الخطأ أعلاه ثم أصلح السبب وأعد تشغيل السكربت."
    }
}

Assert-Command 'flutter'
Assert-Command 'dart'

if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -xor [string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
    throw 'لإعداد المزامنة السحابية أدخل SUPABASE URL و ANON KEY معًا، أو اترك الاثنين فارغين للبناء المحلي.'
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ManifestTemplate = Join-Path $ProjectRoot 'build_support\AndroidManifest.xml'
if (-not (Test-Path $ManifestTemplate)) {
    throw "ملف AndroidManifest غير موجود: $ManifestTemplate"
}

Push-Location $ProjectRoot
$ScaffoldRoot = Join-Path $env:TEMP ("line_manager_android_" + [guid]::NewGuid().ToString('N'))
try {
    Write-Host 'إنشاء ملفات Android القياسية باستخدام نسخة Flutter المثبتة...' -ForegroundColor Yellow
    Invoke-Step 'flutter' @(
        'create',
        '--platforms=android',
        '--org', 'com.infinitymen2',
        '--project-name', 'line_manager',
        $ScaffoldRoot
    )

    $GeneratedAndroid = Join-Path $ScaffoldRoot 'android'
    if (-not (Test-Path $GeneratedAndroid)) {
        throw 'Flutter لم ينشئ مجلد Android المتوقع.'
    }

    $CurrentAndroid = Join-Path $ProjectRoot 'android'
    if (Test-Path $CurrentAndroid) {
        Remove-Item $CurrentAndroid -Recurse -Force
    }
    Copy-Item $GeneratedAndroid -Destination $ProjectRoot -Recurse -Force

    $GeneratedMetadata = Join-Path $ScaffoldRoot '.metadata'
    if (Test-Path $GeneratedMetadata) {
        Copy-Item $GeneratedMetadata (Join-Path $ProjectRoot '.metadata') -Force
    }

    $MainManifest = Join-Path $ProjectRoot 'android\app\src\main\AndroidManifest.xml'
    Copy-Item $ManifestTemplate $MainManifest -Force

    $RawResources = Join-Path $ProjectRoot 'android\app\src\main\res\raw'
    New-Item -ItemType Directory -Path $RawResources -Force | Out-Null
    Copy-Item (Join-Path $ProjectRoot 'build_support\keep.xml') (Join-Path $RawResources 'keep.xml') -Force

    Invoke-Step 'flutter' @('pub', 'get')
    Invoke-Step 'dart' @('run', 'build_runner', 'build', '--delete-conflicting-outputs')
    Invoke-Step 'dart' @('format', 'lib', 'test')
    Invoke-Step 'flutter' @('analyze')
    Invoke-Step 'flutter' @('test')

    $BuildArguments = @('build', 'apk', '--release')
    if (-not [string]::IsNullOrWhiteSpace($SupabaseUrl)) {
        $BuildArguments += "--dart-define=SUPABASE_URL=$SupabaseUrl"
        $BuildArguments += "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
    }
    Invoke-Step 'flutter' $BuildArguments

    $ApkPath = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path $ApkPath)) {
        throw "انتهى أمر البناء دون العثور على APK في المسار المتوقع: $ApkPath"
    }

    Write-Host "`nتم إنشاء APK بنجاح: $ApkPath" -ForegroundColor Green
    Write-Host 'اختبر التطبيق ببيانات تجريبية غير حقيقية، ثم أنشئ نسخة JSON احتياطية قبل إدخال بيانات العملاء الفعلية.' -ForegroundColor Yellow
}
finally {
    if (Test-Path $ScaffoldRoot) {
        Remove-Item $ScaffoldRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
