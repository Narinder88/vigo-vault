import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/providers/notification_manager_provider.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/ble_connection_monitor.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/lock_connection_helper.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps the active lock BLE session healthy by refreshing token, battery, and RSSI.
class LockTelemetrySync {
  static Future<void> refresh(WidgetRef ref) async {
    final bleState = ref.read(bleProvider);
    final device = bleState.device;
    if (device == null) return;

    final deviceId = device.remoteId.str;

    try {
      if (!await BleService.verifyConnection(deviceId)) {
        await _handleSessionLost(ref, deviceId);
        final restored = await LockConnectionHelper.connectAndRestoreSession(
          deviceId: deviceId,
          bleNotifier: ref.read(bleProvider.notifier),
          locksNotifier: ref.read(savedLocksProvider.notifier),
          notificationManager: ref.read(notificationManagerProvider.notifier),
          switchConnection: false,
        );
        if (!restored) {
          await _handleSessionLost(ref, deviceId);
        }
        return;
      }

      var token = BleService.tokenForDevice(deviceId) ?? bleState.token;
      if (!LockConnectionHelper.isValidToken(token)) {
        token = await BleService.getToken(
          deviceId,
          ignoreConnect: true,
          forceFresh: true,
        );
        if (LockConnectionHelper.isValidToken(token)) {
          ref.read(bleProvider.notifier).setToken(token);
        }
      }

      if (LockConnectionHelper.isValidToken(token)) {
        final batteryLevel = await BleService.getBatteryLevel(
          deviceId,
          ignoreConnect: true,
          token: token,
        );
        if (batteryLevel >= 0) {
          ref.read(bleProvider.notifier).setBatteryLevel(batteryLevel);
          await ref
              .read(notificationManagerProvider.notifier)
              .createReachBatteryNotification(batteryLevel);
        }
      }

      try {
        final connectedDevice = BluetoothDevice.fromId(deviceId);
        final rssi = await connectedDevice.readRssi();
        ref.read(bleProvider.notifier).setRssi(rssi);
        await ref.read(savedLocksProvider.notifier).updateTelemetry(
              lockId: deviceId,
              rssi: rssi,
            );
      } catch (_) {
        if (await BleService.verifyConnection(deviceId)) {
          ref.read(bleProvider.notifier).markDisconnected();
        } else {
          await _handleSessionLost(ref, deviceId);
        }
      }
    } catch (_) {
      await _handleSessionLost(ref, deviceId);
    }
  }

  static Future<void> _handleSessionLost(
    WidgetRef ref,
    String deviceId,
  ) async {
    BleConnectionMonitor.stopMonitoring();
    await BleService.resetDeviceConnection(deviceId);
    ref.read(bleProvider.notifier).clearSession();
  }
}
