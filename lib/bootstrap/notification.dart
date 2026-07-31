import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

Future<void> setupNotification() async {
  final awesomeNotifications = AwesomeNotifications();
  await awesomeNotifications.initialize(
    null,
    [
      NotificationChannel(
        channelGroupKey: 'foreground_channel_group',
        channelKey: 'foreground_channel',
        channelName: 'Foreground Channel',
        channelDescription: 'Channel for notice about foreground mode',
        ledColor: Colors.white,
      ),
      NotificationChannel(
        channelGroupKey: 'scheduled_goal_group',
        channelKey: 'scheduled_goal',
        channelName: 'Scheduled Goal',
        channelDescription: 'Channel for notice about goal resetting',
        ledColor: Colors.white,
      ),
      NotificationChannel(
        channelGroupKey: 'cronjob_reset_group',
        channelKey: 'cronjob_reset',
        channelName: 'Cronjob reset',
        channelDescription: 'Channel for notice about data resetting',
        ledColor: Colors.white,
      ),
      NotificationChannel(
        channelGroupKey: 'daily_progress_group',
        channelKey: 'daily_progress',
        channelName: 'Daily Progress',
        channelDescription: 'Channel for notice about daily progress',
        ledColor: Colors.white,
      ),
      NotificationChannel(
        channelGroupKey: 'padlock_battery_group',
        channelKey: 'padlock_battery',
        channelName: 'Lock Battery',
        channelDescription: 'Low battery reminders for your smart lock',
        ledColor: Colors.white,
      ),
    ],
    channelGroups: [
      NotificationChannelGroup(
        channelGroupKey: 'foreground_channel_group',
        channelGroupName: 'Foreground channel Group',
      ),
      NotificationChannelGroup(
        channelGroupKey: 'cronjob_reset_group',
        channelGroupName: 'Cronjob reset Group',
      ),
      NotificationChannelGroup(
        channelGroupKey: 'scheduled_goal_group',
        channelGroupName: 'Scheduled Goal Group',
      ),
      NotificationChannelGroup(
        channelGroupKey: 'daily_progress_group',
        channelGroupName: 'Daily Progress Group',
      ),
      NotificationChannelGroup(
        channelGroupKey: 'padlock_battery_group',
        channelGroupName: 'Lock Battery Group',
      ),
    ],
    debug: true,
  );

  await awesomeNotifications.isNotificationAllowed().then((isAllowed) {
    if (!isAllowed) {
      awesomeNotifications.requestPermissionToSendNotifications(permissions: [
        NotificationPermission.Alert,
        NotificationPermission.Sound,
        NotificationPermission.Badge,
        NotificationPermission.Vibration,
        NotificationPermission.Light,
        NotificationPermission.PreciseAlarms,
      ]);
    }
  });

  // CANCEL SYNC NOTIFICATION PER MIN
  awesomeNotifications.cancel(11);
}
