import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/legacy.dart';

typedef BleData = ({
  BluetoothDevice? device,
  int rssi,
  int batteryLevel,
  String? token,
  String? customDeviceName,
  bool isConnecting,
  String? connectingDeviceId,
});

final bleProvider = StateNotifierProvider<BleProvider, BleData>((ref) {
  return BleProvider();
});

class BleProvider extends StateNotifier<BleData> {
  BleProvider()
      : super((
          device: null,
          rssi: -100,
          batteryLevel: 0,
          token: null,
          customDeviceName: null,
          isConnecting: false,
          connectingDeviceId: null,
        ));

  static const deviceUnreachableMessage =
      'Device out of range or not found.';

  BleData get value => state;

  void setDevice(BluetoothDevice? device) {
    state = (
      device: device,
      rssi: state.rssi,
      batteryLevel: state.batteryLevel,
      token: state.token,
      customDeviceName: state.customDeviceName,
      isConnecting: state.isConnecting,
      connectingDeviceId: state.connectingDeviceId,
    );
  }

  void setRssi(int? rssi) {
    final newRssi = rssi ?? -100;
    state = (
      device: state.device,
      rssi: newRssi,
      batteryLevel: state.batteryLevel,
      token: state.token,
      customDeviceName: state.customDeviceName,
      isConnecting: state.isConnecting,
      connectingDeviceId: state.connectingDeviceId,
    );
  }

  void setBatteryLevel(int? batteryLevel) {
    if (batteryLevel == null || batteryLevel < 0) return;

    state = (
      device: state.device,
      rssi: state.rssi,
      batteryLevel: batteryLevel,
      token: state.token,
      customDeviceName: state.customDeviceName,
      isConnecting: state.isConnecting,
      connectingDeviceId: state.connectingDeviceId,
    );
  }

  void setToken(String? token) {
    state = (
      device: state.device,
      rssi: state.rssi,
      batteryLevel: state.batteryLevel,
      token: token,
      customDeviceName: state.customDeviceName,
      isConnecting: state.isConnecting,
      connectingDeviceId: state.connectingDeviceId,
    );
  }

  void setCustomDeviceName(String? name) {
    final trimmed = name?.trim();
    state = (
      device: state.device,
      rssi: state.rssi,
      batteryLevel: state.batteryLevel,
      token: state.token,
      customDeviceName:
          (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      isConnecting: state.isConnecting,
      connectingDeviceId: state.connectingDeviceId,
    );
  }

  void beginConnecting(String deviceId) {
    state = (
      device: state.device,
      rssi: state.rssi,
      batteryLevel: state.batteryLevel,
      token: state.token,
      customDeviceName: state.customDeviceName,
      isConnecting: true,
      connectingDeviceId: deviceId,
    );
  }

  void endConnecting() {
    state = (
      device: state.device,
      rssi: state.rssi,
      batteryLevel: state.batteryLevel,
      token: state.token,
      customDeviceName: state.customDeviceName,
      isConnecting: false,
      connectingDeviceId: null,
    );
  }

  void markConnectFailed() {
    state = (
      device: state.device,
      rssi: -100,
      batteryLevel: state.batteryLevel,
      token: null,
      customDeviceName: state.customDeviceName,
      isConnecting: false,
      connectingDeviceId: null,
    );
  }

  void setConnected({
    required BluetoothDevice device,
    required String token,
    int? batteryLevel,
    int? rssi,
    String? customDeviceName,
  }) {
    state = (
      device: device,
      rssi: rssi ?? state.rssi,
      batteryLevel: (batteryLevel != null && batteryLevel >= 0)
          ? batteryLevel
          : state.batteryLevel,
      token: token,
      customDeviceName: customDeviceName ?? state.customDeviceName,
      isConnecting: false,
      connectingDeviceId: null,
    );
  }

  void markDisconnected() {
    state = (
      device: state.device,
      rssi: -100,
      batteryLevel: state.batteryLevel,
      token: null,
      customDeviceName: state.customDeviceName,
      isConnecting: false,
      connectingDeviceId: null,
    );
  }

  void clearSession() {
    state = (
      device: null,
      rssi: -100,
      batteryLevel: 0,
      token: null,
      customDeviceName: state.customDeviceName,
      isConnecting: false,
      connectingDeviceId: null,
    );
  }

  void reset() {
    state = (
      device: null,
      rssi: -100,
      batteryLevel: 0,
      token: null,
      customDeviceName: state.customDeviceName,
      isConnecting: false,
      connectingDeviceId: null,
    );
  }
}
