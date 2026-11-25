import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cron/cron.dart';
import 'package:fitness_snack_lock/utils/battery_level.dart';
import 'package:fitness_snack_lock/utils/lock_mac.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef NotificationManagerData = ({bool ready});

final notificationManagerProvider =
    StateNotifierProvider<NotificationManagerProvider, NotificationManagerData>(
  (ref) => NotificationManagerProvider(),
);

class NotificationManagerProvider
    extends StateNotifier<NotificationManagerData> {
  NotificationManagerProvider() : super((ready: true));

  final cron = Cron();

  static const _cooldown = Duration(hours: 24);
  static const _notifiedAtKeyPrefix = 'smart_lock_low_battery_notified_at_';

  /// Alerts only for a real 1%–20% reading, at most once per lock per day.
  ///
  /// `0` and `null` are unread or disconnected defaults and never notify.
  /// The cooldown timestamp and notification id are both keyed by lock id, so
  /// one low lock cannot suppress or replace another lock's alert.
  Future<void> createReachBatteryNotification({
    required String lockId,
    required String displayName,
    required int? level,
  }) async {
    final reading = persistableBatteryLevel(level);
    if (reading == null || reading > 20) return;

    final id = LockMac.normalize(lockId);
    if (id.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final cooldownKey = '$_notifiedAtKeyPrefix$id';
    final lastNotifiedMs = prefs.getInt(cooldownKey);
    if (lastNotifiedMs != null) {
      final lastNotified = DateTime.fromMillisecondsSinceEpoch(lastNotifiedMs);
      if (DateTime.now().difference(lastNotified) < _cooldown) return;
    }

    final name = displayName.trim().isEmpty ? 'Lock' : displayName.trim();
    await createBasePadlockNotification(
      _notificationIdForLock(id),
      'Low battery',
      '$name battery is low ($reading%). Please charge soon.',
      lockId: id,
      level: reading,
    );
    await prefs.setInt(cooldownKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Stable id in a dedicated band so locks do not share notification 20.
  static int _notificationIdForLock(String lockId) {
    const fnvOffset = 0x811c9dc5;
    const fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final unit in lockId.codeUnits) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0x7fffffff;
    }
    return 100000 + (hash % 900000);
  }

  Future<void> createBasePadlockNotification(
    int id,
    String title,
    String content, {
    String? lockId,
    int? level,
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'padlock_battery',
        title: title,
        body: content,
        wakeUpScreen: true,
        category: NotificationCategory.Reminder,
        payload: {
          if (lockId != null) 'lockId': lockId,
          'percent': '${level ?? ''}',
        },
        autoDismissible: false,
        notificationLayout: NotificationLayout.BigText,
      ),
    );
  }

  void getDataPerPeriod() {
    cron.schedule(Schedule.parse('0 0 * * *'), () async {
      syncDataPerPeriod();
    });
  }

  void syncDataPerPeriod() {
    // Per-lock cooldown timestamps expire on their own after 24 hours.
  }
}
