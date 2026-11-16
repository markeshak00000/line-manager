import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
import '../../services/backup_service.dart';
import '../../services/notification_service.dart';
import '../../services/sync_service.dart';
import '../packages/packages_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ValueChanged<ThemeMode>? onThemeChanged;
  final ThemeMode currentMode;

  const SettingsScreen({
    super.key,
    this.onThemeChanged,
    this.currentMode = ThemeMode.system,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  NotificationSettings? _notificationSettings;
  String _collector = 'ماما';
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await NotificationService.loadSettings();
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notificationSettings = settings;
      _collector = preferences.getString('collector_name') ?? 'ماما';
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final sync = context.read<SyncService>();
    final backup = BackupService(db);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('الباقات', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            title: const Text('إدارة الباقات'),
            leading: const Icon(Icons.category),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PackagesScreen()),
            ),
          ),
          const Divider(),
          const ListTile(
            title: Text('التنبيهات', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (_notificationSettings != null)
            SwitchListTile(
              title: const Text('تفعيل التنبيهات'),
              value: _notificationSettings!.enabled,
              onChanged: (value) async {
                final current = _notificationSettings!;
                final updated = NotificationSettings(
                  enabled: value,
                  daysBefore: current.daysBefore,
                  hour: current.hour,
                  minute: current.minute,
                );
                await NotificationService.saveSettings(updated);
                await NotificationService.refreshAll(db);
                if (mounted) setState(() => _notificationSettings = updated);
              },
            ),
          ListTile(
            title: const Text('أيام ووقت التذكير'),
            subtitle: Text(
              _notificationSettings == null
                  ? 'جارٍ التحميل...'
                  : '${_notificationSettings!.daysBefore.join(' ، ')} أيام — الساعة ${_notificationSettings!.hour.toString().padLeft(2, '0')}:${_notificationSettings!.minute.toString().padLeft(2, '0')}',
            ),
            leading: const Icon(Icons.notifications),
            onTap: _notificationSettings == null ? null : _editNotifications,
          ),
          const Divider(),
          const ListTile(
            title: Text('التطبيق', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            title: const Text('الوضع الليلي / النهاري'),
            subtitle: Text(_themeLabel(widget.currentMode)),
            leading: const Icon(Icons.dark_mode),
            onTap: _chooseTheme,
          ),
          ListTile(
            title: const Text('اسم المحصّل الافتراضي'),
            subtitle: Text(_collector),
            leading: const Icon(Icons.person),
            onTap: _editCollector,
          ),
          const ListTile(
            title: Text('العملة'),
            subtitle: Text('الجنيه المصري (ج.م)'),
          ),
          const Divider(),
          const ListTile(
            title: Text('النسخ الاحتياطي', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          FutureBuilder<int>(
            future: sync.pendingCount(),
            builder: (context, snapshot) => ListTile(
              title: const Text('العمليات بانتظار المزامنة'),
              subtitle: Text('${snapshot.data ?? 0} عملية'),
            ),
          ),
          FutureBuilder<Map<String, int>>(
            future: sync.pendingByTable(),
            builder: (context, snapshot) {
              final counts = snapshot.data ?? const <String, int>{};
              return ListTile(
                title: const Text('تفاصيل المزامنة المعلقة'),
                subtitle: Text(
                  counts.isEmpty
                      ? 'لا توجد عمليات معلقة'
                      : counts.entries.map((e) => '${e.key}: ${e.value}').join(' • '),
                ),
              );
            },
          ),
          ListTile(
            enabled: !_working,
            title: const Text('مزامنة الآن (سحابي)'),
            subtitle: const Text('رفع التغييرات إلى النسخة السحابية عند توافر الإنترنت'),
            leading: const Icon(Icons.cloud_upload),
            onTap: _working ? null : () async {
              setState(() => _working = true);
              try {
                await sync.syncNow();
                if (mounted) _message('اكتملت محاولة المزامنة. راجع عدد العمليات المعلقة.');
              } catch (error) {
                if (mounted) _message('تعذرت المزامنة: $error');
              } finally {
                if (mounted) setState(() => _working = false);
              }
            },
          ),
          ListTile(
            enabled: !_working,
            title: const Text('تصدير نسخة JSON ومشاركتها خارج الجهاز'),
            leading: const Icon(Icons.backup),
            onTap: _working ? null : () async {
              setState(() => _working = true);
              try {
                await backup.shareBackup();
              } catch (error) {
                if (mounted) _message('تعذر إنشاء النسخة الاحتياطية: $error');
              } finally {
                if (mounted) setState(() => _working = false);
              }
            },
          ),
          ListTile(
            enabled: !_working,
            title: const Text('استيراد نسخة احتياطية من ملف JSON'),
            leading: const Icon(Icons.restore),
            onTap: _working ? null : () => _restore(backup, db),
          ),
          const Divider(),
          const ListTile(
            title: Text('حول التطبيق', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const ListTile(
            title: Text('ENG. Mark Eshak'),
            subtitle: Text(
              'المهندس مارك اسحق\nInfinity MEN2\nSoftware Engineer\nتطوير هندسة البرمجيات وأنظمة سطح المكتب المتكاملة لإدارة الأعمال.',
            ),
          ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'فاتح';
      case ThemeMode.dark:
        return 'داكن';
      case ThemeMode.system:
        return 'حسب إعدادات الجهاز';
    }
  }

  Future<void> _chooseTheme() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اختر مظهر التطبيق'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _themeOption(dialogContext, ThemeMode.light, 'فاتح'),
            _themeOption(dialogContext, ThemeMode.dark, 'داكن'),
            _themeOption(dialogContext, ThemeMode.system, 'حسب إعدادات الجهاز'),
          ],
        ),
      ),
    );
    if (selected != null) widget.onThemeChanged?.call(selected);
  }

  Widget _themeOption(BuildContext context, ThemeMode mode, String label) =>
      ListTile(
        title: Text(label),
        trailing: widget.currentMode == mode ? const Icon(Icons.check) : null,
        onTap: () => Navigator.pop(context, mode),
      );

  Future<void> _editCollector() async {
    final controller = TextEditingController(text: _collector);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اسم المحصّل الافتراضي'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final value = controller.text.trim().isEmpty ? 'ماما' : controller.text.trim();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('collector_name', value);
    if (mounted) setState(() => _collector = value);
  }

  Future<void> _editNotifications() async {
    final current = _notificationSettings;
    if (current == null) return;
    final daysController = TextEditingController(text: current.daysBefore.join(','));
    final hourController = TextEditingController(text: '${current.hour}');
    final minuteController = TextEditingController(text: '${current.minute}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعدادات التنبيهات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: daysController,
              decoration: const InputDecoration(
                labelText: 'أيام قبل الاستحقاق (مثال: 3,1,0)',
              ),
            ),
            TextField(
              controller: hourController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الساعة من 0 إلى 23'),
            ),
            TextField(
              controller: minuteController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الدقيقة من 0 إلى 59'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final days = daysController.text
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .where((value) => value >= 0 && value <= 31)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final updated = NotificationSettings(
      enabled: current.enabled,
      daysBefore: days,
      hour: (int.tryParse(hourController.text) ?? 9).clamp(0, 23).toInt(),
      minute: (int.tryParse(minuteController.text) ?? 0).clamp(0, 59).toInt(),
    );
    await NotificationService.saveSettings(updated);
    await NotificationService.refreshAll(context.read<AppDatabase>());
    if (mounted) setState(() => _notificationSettings = updated);
  }

  Future<void> _restore(BackupService backup, AppDatabase db) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية؟'),
        content: const Text(
          'سيتم استبدال البيانات الحالية بالكامل بالبيانات الموجودة في الملف. '
          'صدّر نسخة من بياناتك الحالية أولاً إذا كنت تحتاج إليها.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('اختيار ملف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      final count = await backup.importJsonFile();
      await NotificationService.refreshAll(db);
      if (mounted) _message(count == 0 ? 'لم يتم اختيار ملف' : 'تمت استعادة $count سجل');
    } catch (error) {
      if (mounted) _message('تعذرت استعادة النسخة: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
