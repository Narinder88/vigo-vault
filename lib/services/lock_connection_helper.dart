import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/providers/notification_manager_provider.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/ble_connection_monitor.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/pairing_service.dart';
import 'package:fitness_snack_lock/services/saved_lock_storage.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class LockConnectionHelper {
  static bool isValidToken(String? token) {
    return token != null && token.isNotEmpty;
  }

  static bool isPreConnected(String deviceId) {
    return BleService.isDeviceConnected(deviceId);
  }

  static Future<({int? batteryLevel, int rssi})> readBatteryAndRssi({
    required BluetoothDevice device,
    required String deviceId,
    required String token,
  }) async {
    final batteryLevel = await BleService.getBatteryLevel(
      deviceId,
      ignoreConnect: true,
      token: token,
    );

    var rssi = -100;
    try {
      rssi = await device.readRssi();
    } catch (_) {}

    return (
      batteryLevel: batteryLevel >= 0 ? batteryLevel : null,
      rssi: rssi,
    );
  }

  static String defaultDisplayName(BluetoothDevice device) {
    if (device.advName.isNotEmpty) return device.advName;
    if (device.platformName.isNotEmpty) return device.platformName;
    return 'Smart Lock';
  }

  static String hardwareName(BluetoothDevice device) {
    if (device.advName.isNotEmpty) return device.advName;
    if (device.platformName.isNotEmpty) return device.platformName;
    return 'Smart Lock';
  }

  static Future<bool> connectAndRestoreSession({
    required String deviceId,
    required BleProvider bleNotifier,
    SavedLocksNotifier? locksNotifier,
    NotificationManagerProvider? notificationManager,
    bool switchConnection = true,
    bool background = false,
  }) async {
    BleConnectionMonitor.stopMonitoring();
    if (!background) {
      bleNotifier.beginConnecting(deviceId);
    }

    var sessionEstablished = false;

    try {
      if (!switchConnection && !await BleService.verifyConnection(deviceId)) {
        await BleService.prepareFreshConnection(deviceId);
      }

      final knownDeviceIds = locksNotifier?.allDeviceIds ?? const [];

      final connected = switchConnection
          ? await BleService.switchConnection(
              deviceId,
              knownDeviceIds: knownDeviceIds,
            )
          : await BleService.connect(deviceId);
      if (!connected) {
        if (!background) {
          bleNotifier.markConnectFailed();
        }
        return false;
      }

      final token = BleService.tokenForDevice(deviceId);
      if (!isValidToken(token)) {
        if (!background) {
          bleNotifier.markConnectFailed();
        }
        return false;
      }

      sessionEstablished = true;
      final device = BluetoothDevice.fromId(deviceId);
      final readings = await readBatteryAndRssi(
        device: device,
        deviceId: deviceId,
        token: token!,
      );

      final savedLock = locksNotifier?.lockById(deviceId);
      final displayName = savedLock?.displayName ?? defaultDisplayName(device);

      if (locksNotifier != null) {
        await locksNotifier.registerConnectedLock(
          deviceId: deviceId,
          displayName: displayName,
          hardwareName: hardwareName(device),
          batteryLevel: readings.batteryLevel,
          rssi: readings.rssi,
        );
      } else {
        await SavedLockStorage.setActiveLockId(deviceId);
      }

      if (readings.batteryLevel != null && notificationManager != null) {
        await notificationManager.createReachBatteryNotification(
          readings.batteryLevel!,
        );
      }

      bleNotifier.setConnected(
        device: device,
        token: token,
        batteryLevel: readings.batteryLevel,
        rssi: readings.rssi,
        customDeviceName: displayName,
      );

      return true;
    } catch (_) {
      if (!background) {
        bleNotifier.markConnectFailed();
      }
      return false;
    } finally {
      if (sessionEstablished || BleService.isDeviceConnected(deviceId)) {
        await BleService.releaseOnDemandConnection(deviceId);
      }
      BleConnectionMonitor.stopMonitoring();
      if (!background) {
        if (!sessionEstablished) {
          bleNotifier.clearSession();
        }
        if (bleNotifier.value.isConnecting) {
          bleNotifier.endConnecting();
        }
      }
    }
  }

  /// On-demand mode: the phone no longer keeps a background GATT session open.
  static Future<bool> connectPrimaryLockInBackground({
    required BleProvider bleNotifier,
    required SavedLocksNotifier locksNotifier,
    NotificationManagerProvider? notificationManager,
  }) async {
    BleConnectionMonitor.stopMonitoring();
    return false;
  }

  static Future<bool> unlockPreConnectedLock(
    String deviceId, {
    bool forceFresh = false,
  }) async {
    try {
      return await BleService.connectAndUnLock(deviceId);
    } on PairingRequiredException {
      return false;
    } on LockAuthenticationException {
      rethrow;
    }
  }

  static Future<bool> attemptAutoReconnect({
    required BleProvider bleNotifier,
    SavedLocksNotifier? locksNotifier,
    NotificationManagerProvider? notificationManager,
  }) async {
    if (locksNotifier != null) {
      return connectPrimaryLockInBackground(
        bleNotifier: bleNotifier,
        locksNotifier: locksNotifier,
        notificationManager: notificationManager,
      );
    }

    final savedDeviceId = await SavedLockStorage.getPrimaryLockId() ??
        await SavedLockStorage.getActiveLockId();
    if (savedDeviceId == null || savedDeviceId.isEmpty) return false;

    return connectAndRestoreSession(
      deviceId: savedDeviceId,
      bleNotifier: bleNotifier,
      background: true,
    );
  }
}
