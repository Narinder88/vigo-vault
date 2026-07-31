import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cron/cron.dart';
import 'package:flutter_riverpod/legacy.dart';

typedef NotificationManagerData = ({bool ready});

final notificationManagerProvider =
    StateNotifierProvider<NotificationManagerProvider, NotificationManagerData>(
  (ref) => NotificationManagerProvider(),
);

class NotificationManagerProvider
    extends StateNotifier<NotificationManagerData> {
  NotificationManagerProvider() : super((ready: true));

  final cron = Cron();
  Map<String, int> showBatteryNotificationCount = {
    '0': 0,
    '20': 0,
  };

  void resetShowBatteryNotificationCount() {
    showBatteryNotificationCount = {
      '0': 0,
      '20': 0,
    };
  }

  Future<void> createReachBatteryNotification(int level) async {
    if (level < 0) return;

    if (level <= 20) {
      if (showBatteryNotificationCount['20'] == 0) {
        final title = level == 0
            ? '🔴 Battery Critically Low – Charge Immediately'
            : '🔔 Battery Low – Please Charge Your Lock';
        final body = level == 0
            ? 'Your padlock battery is at 0%. Charge now to ensure continued access and prevent a complete shutdown.'
            : 'Your padlock is at $level%. Charge it soon to avoid being locked out.';

        await createBasePadlockNotification(20, title, body);
        showBatteryNotificationCount['20'] = 1;
      }
    }
  }

  Future<void> createBasePadlockNotification(
    int id,
    String title,
    String content,
  ) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'padlock_battery',
        title: title,
        body: content,
        wakeUpScreen: true,
        category: NotificationCategory.Reminder,
        payload: {'percent': '100'},
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
    resetShowBatteryNotificationCount();
  }
}
