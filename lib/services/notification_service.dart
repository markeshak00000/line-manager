import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/money.dart';
import '../core/year_month.dart';
import '../data/database.dart';
import '../data/repositories.dart';

class NotificationSettings {
  final bool enabled;
  final List<int> daysBefore;
  final int hour;
  final int minute;

  const NotificationSettings({
    required this.enabled,
    required this.daysBefore,
    required this.hour,
    required this.minute,
  });
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const String _enabledKey = 'notif_enabled';
  static const String _daysKey = 'notif_days';
  static const String _hourKey = 'notif_hour';
  static const String _minuteKey = 'notif_minute';

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    } catch (_) {
      // The system timezone remains the fallback if the timezone database
      // cannot resolve the requested region.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await androidPlugin?.requestNotificationsPermission();
    } catch (_) {}
    try {
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'line_manager_reminders',
          'تذكيرات الاشتراكات',
          description: 'تنبيهات مواعيد اشتراكات الخطوط',
          importance: Importance.high,
        ),
      );
    } catch (_) {}
  }

  static Future<NotificationSettings> loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final days = (preferences.getString(_daysKey) ?? '3,1,0')
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .where((value) => value >= 0 && value <= 31)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return NotificationSettings(
      enabled: preferences.getBool(_enabledKey) ?? true,
      daysBefore: days,
      hour: (preferences.getInt(_hourKey) ?? 9).clamp(0, 23).toInt(),
      minute: (preferences.getInt(_minuteKey) ?? 0).clamp(0, 59).toInt(),
    );
  }

  static Future<void> saveSettings(NotificationSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, settings.enabled);
    await preferences.setString(
      _daysKey,
      settings.daysBefore
          .where((day) => day >= 0 && day <= 31)
          .toSet()
          .join(','),
    );
    await preferences.setInt(_hourKey, settings.hour.clamp(0, 23).toInt());
    await preferences.setInt(_minuteKey, settings.minute.clamp(0, 59).toInt());
    if (!settings.enabled) await cancelAll();
  }

  /// Rebuilds the upcoming monthly reminders from the current local database.
  /// Each active line receives reminders for the first day of next month.
  static Future<void> refreshAll(AppDatabase db) async {
    await cancelAll();
    final settings = await loadSettings();
    if (!settings.enabled || settings.daysBefore.isEmpty) return;

    final now = YearMonth.nowCairo();
    final firstFutureMonth = now.next();
    final lines = await (db.select(db.lines)
          ..where((line) =>
              line.status.equals('active') & line.deletedAt.isNull()))
        .get();
    final repos = Repos(db);

    for (final line in lines) {
      final customer = await (db.select(db.customers)
            ..where((item) => item.id.equals(line.customerId)))
          .getSingleOrNull();
      if (customer == null) continue;

      final cycles = await repos.cyclesForLine(line.id);
      final futureCycles = cycles
          .where((cycle) =>
              YearMonth(cycle.year, cycle.month).compareTo(firstFutureMonth) >= 0)
          .toList()
        ..sort((a, b) => YearMonth(a.year, a.month)
            .compareTo(YearMonth(b.year, b.month)));
      BillingCycle? nextUnpaid;
      for (final cycle in futureCycles) {
        if (cycle.paidPiasters < cycle.pricePiasters) {
          nextUnpaid = cycle;
          break;
        }
      }

      final dueMonth = nextUnpaid == null
          ? (futureCycles.isEmpty
              ? firstFutureMonth
              : YearMonth(futureCycles.last.year, futureCycles.last.month).next())
          : YearMonth(nextUnpaid.year, nextUnpaid.month);
      final remaining = nextUnpaid == null
          ? await repos.priceForMonth(line.packageId, dueMonth)
          : (nextUnpaid.pricePiasters - nextUnpaid.paidPiasters)
              .clamp(0, 1 << 62)
              .toInt();
      if (remaining <= 0) continue;

      await scheduleForDue(
        baseId: _stableNotificationId(line.id),
        customer: customer.name,
        lineNumber: line.number,
        amountPiasters: remaining,
        dueDate: DateTime(dueMonth.year, dueMonth.month, 1),
      );
    }
  }

  static Future<void> scheduleForDue({
    required int baseId,
    required String customer,
    required String lineNumber,
    required int amountPiasters,
    required DateTime dueDate,
  }) async {
    final settings = await loadSettings();
    if (!settings.enabled) return;
    final amount = Money.format(amountPiasters);
    final days = settings.daysBefore.toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    for (var index = 0; index < days.length; index++) {
      final daysBefore = days[index];
      final scheduled = DateTime(
        dueDate.year,
        dueDate.month,
        dueDate.day,
        settings.hour,
        settings.minute,
      ).subtract(Duration(days: daysBefore));
      if (!scheduled.isAfter(DateTime.now())) continue;

      final title = daysBefore == 0
          ? 'موعد الاستحقاق اليوم'
          : 'تذكير قبل الاستحقاق بـ $daysBefore يوم';
      await _plugin.zonedSchedule(
        baseId * 10 + index,
        title,
        'اشتراك $customer على الخط $lineNumber يستحق $amount',
        tz.TZDateTime.from(scheduled, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'line_manager_reminders',
            'تذكيرات الاشتراكات',
            channelDescription: 'تنبيهات مواعيد اشتراكات الخطوط',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  static int _stableNotificationId(String id) {
    // Stable FNV-1a hash, unlike String.hashCode which may vary by runtime.
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash % 100000000;
  }

  static Future<void> cancelForLine(int baseId) async {
    for (var index = 0; index < 10; index++) {
      await _plugin.cancel(baseId * 10 + index);
    }
  }

  static Future<void> cancel(int id) => _plugin.cancel(id);
  static Future<void> cancelAll() => _plugin.cancelAll();
}
