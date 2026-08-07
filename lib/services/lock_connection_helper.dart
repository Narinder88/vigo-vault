import 'dart:async';

import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/providers/notification_manager_provider.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/ble_connection_monitor.dart';
import 'package:fitness_snack_lock/services/ble_debug_log.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/pairing_service.dart';
import 'package:fitness_snack_lock/services/saved_lock_storage.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class LockConnectionHelper {
  /// GATT connect + discovery budget for foreground tap-to-open.
  static const Duration _interactiveConnectTimeout = Duration(seconds: 12);
  /// AES handshake budget — starts only after GATT is ready.
  static const Duration _interactiveHandshakeTimeout = Duration(seconds: 5);
  /// Outer cap for the full foreground session (GATT + handshake).
  static Duration get _interactiveSessionTimeout =>
      _interactiveConnectTimeout + _interactiveHandshakeTimeout;

  static final Map<String, Future<bool>> _pendingConnectByDeviceId = {};

  static bool hasPendingConnect(String deviceId) =>
      _pendingConnectByDeviceId.containsKey(deviceId);

  static Future<bool>? pendingConnectFuture(String deviceId) =>
      _pendingConnectByDeviceId[deviceId];

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
  }) {
    final existing = _pendingConnectByDeviceId[deviceId];
    if (existing != null) {
      return existing;
    }

    final connectTask = _connectAndRestoreSessionImpl(
      deviceId: deviceId,
      bleNotifier: bleNotifier,
      locksNotifier: locksNotifier,
      notificationManager: notificationManager,
      switchConnection: switchConnection,
      background: background,
    );

    _pendingConnectByDeviceId[deviceId] = connectTask;
    return connectTask.whenComplete(() {
      if (_pendingConnectByDeviceId[deviceId] == connectTask) {
        _pendingConnectByDeviceId.remove(deviceId);
      }
    });
  }

  static Future<bool> _connectAndRestoreSessionImpl({
    required String deviceId,
    required BleProvider bleNotifier,
    SavedLocksNotifier? locksNotifier,
    NotificationManagerProvider? notificationManager,
    bool switchConnection = true,
    bool background = false,
  }) async {
    BleConnectionMonitor.stopMonitoring();
    BleDebugLog.ble(
      'Session connect start for $deviceId (background=$background'
      '${background ? ", no short timeout, autoConnect" : ""})',
    );
    bleNotifier.beginConnecting(deviceId);

    var sessionEstablished = false;

    try {
      if (!switchConnection && !await BleService.verifyConnection(deviceId)) {
        await BleService.prepareFreshConnection(deviceId);
      }

      final connectFuture = background
          ? BleService.connectForBackgroundWarmup(deviceId)
          : BleService.connectForUnlock(deviceId);

      final bool connected;
      if (background) {
        connected = await connectFuture;
      } else {
        connected = await connectFuture.timeout(
          _interactiveSessionTimeout,
          onTimeout: () {
            BleDebugLog.error(
              'Session connect timed out after '
              '${_interactiveSessionTimeout.inSeconds}s for $deviceId '
              '(GATT ${_interactiveConnectTimeout.inSeconds}s + '
              'handshake ${_interactiveHandshakeTimeout.inSeconds}s)',
            );
            return false;
          },
        );
      }
      if (!connected) {
        BleDebugLog.error('Session connect failed for $deviceId (timeout or GATT error)');
        if (!background) {
          bleNotifier.markConnectFailed();
        }
        return false;
      }

      final token = BleService.tokenForDevice(deviceId);
      if (!isValidToken(token)) {
        BleDebugLog.error('Session connect missing token for $deviceId');
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

      BleConnectionMonitor.startMonitoring(
        deviceId: deviceId,
        bleNotifier: bleNotifier,
      );

      BleDebugLog.ble(
        'Session connect success for $deviceId '
        '(gatt=${BleService.isDeviceConnected(deviceId)})',
      );

      return true;
    } catch (error) {
      BleDebugLog.error('Session connect exception for $deviceId: $error');
      if (!background) {
        bleNotifier.markConnectFailed();
      }
      return false;
    } finally {
      if (!sessionEstablished) {
        if (BleService.isDeviceConnected(deviceId)) {
          await BleService.releaseOnDemandConnection(deviceId);
        }
        if (!background) {
          bleNotifier.clearSession();
        }
        BleConnectionMonitor.stopMonitoring();
      }
      if (bleNotifier.value.isConnecting) {
        bleNotifier.endConnecting();
      }
    }
  }

  /// Waits for an in-flight dashboard connection before starting unlock.
  static Future<bool> awaitPendingConnect(String deviceId) async {
    final pending = _pendingConnectByDeviceId[deviceId];
    if (pending != null) {
      BleDebugLog.ble('Awaiting pending connect for $deviceId');
      return pending;
    }
    return false;
  }

  /// Apple Watch MethodChannel bridge only — uses tuned GATT unlock path.
  static Future<bool> triggerUnlock(String deviceId) async {
    final awaitedConnect = await awaitPendingConnect(deviceId);
    if (awaitedConnect) {
      BleDebugLog.tap('Pending connect finished for $deviceId — using live session');
    }
    await BleService.forceCleanDisconnectBeforeUnlock(deviceId);
    return BleService.unlockLock(deviceId);
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
