import 'dart:async';

import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Listens for unexpected BLE disconnects and clears stale session state.
class BleConnectionMonitor {
  BleConnectionMonitor._();

  static StreamSubscription<BluetoothConnectionState>? _subscription;
  static String? _monitoredDeviceId;

  static void startMonitoring({
    required String deviceId,
    required BleProvider bleNotifier,
    SavedLocksNotifier? locksNotifier,
  }) {
    if (_monitoredDeviceId == deviceId && _subscription != null) {
      return;
    }

    stopMonitoring();
    _monitoredDeviceId = deviceId;

    final device = BluetoothDevice.fromId(deviceId);
    _subscription = device.connectionState.listen((state) {
      if (state != BluetoothConnectionState.disconnected) return;
      unawaited(
        _handleUnexpectedDisconnect(
          deviceId: deviceId,
          bleNotifier: bleNotifier,
        ),
      );
    });
  }

  static void stopMonitoring() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _monitoredDeviceId = null;
  }

  static Future<void> _handleUnexpectedDisconnect({
    required String deviceId,
    required BleProvider bleNotifier,
  }) async {
    if (_monitoredDeviceId != deviceId) return;

    stopMonitoring();
    await BleService.resetDeviceConnection(deviceId);
    if (bleNotifier.value.isConnecting) {
      bleNotifier.endConnecting();
    }
    bleNotifier.clearSession();
  }
}
