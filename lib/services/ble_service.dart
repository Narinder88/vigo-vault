import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fitness_snack_lock/services/data_service.dart';
import 'package:fitness_snack_lock/services/lock_secret_storage.dart';
import 'package:fitness_snack_lock/services/pairing_service.dart';

class BleService {
  static String currentEncryptKey = DataRequestPattern.defaultEncryptKey;

  static String? _activeDeviceId;
  static final Map<String, String> _deviceTokens = {};
  static final Map<String, String> _deviceEncryptKeys = {};
  static final Map<String, StreamSubscription<List<int>>?>
      _handshakeNotifySubscriptions = {};

  static const int _maxHandshakeAttempts = 3;

  static String? get activeDeviceId => _activeDeviceId;

  static String? get lastConnectToken {
    final activeId = _activeDeviceId;
    if (activeId == null) return null;
    return _deviceTokens[activeId];
  }

  static String? tokenForDevice(String deviceId) => _deviceTokens[deviceId];

  static Future<void> _connectionChain = Future.value();

  /// Serializes BLE connect/disconnect/switch operations to avoid adapter lockups.
  static Future<T> runExclusive<T>(Future<T> Function() action) {
    final result = _connectionChain.then((_) => action());
    _connectionChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static const Duration _postDisconnectSettleDelay = Duration(milliseconds: 750);
  static const Duration _preConnectDelay = Duration(milliseconds: 1500);
  static const Duration _disconnectTimeout = Duration(seconds: 5);
  static const Duration _connectAttemptTimeout = Duration(seconds: 6);
  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _postAbortConnectDelay = Duration(milliseconds: 500);
  static const int _androidDisconnectDelayMs = 2000;
  static const Duration _scanPresenceTimeout = Duration(seconds: 4);
  static const int _maxConnectRetryCount = 5;
  static const List<Duration> _connectBackoffDelays = [
    Duration(milliseconds: 500),
    Duration(milliseconds: 1000),
    Duration(milliseconds: 2000),
  ];

  /// Stops scans and fully tears down every known/active device before connecting.
  static Future<void> releaseAdapterForNewConnection(
    String targetDeviceId, {
    Iterable<String> knownDeviceIds = const [],
  }) async {
    await _disconnectAllLocksBeforeConnect(
      targetDeviceId,
      knownDeviceIds: knownDeviceIds,
    );
    await _waitForGattSettle();
  }

  /// Fully releases every known device — use after failed switches to clear dangling GATT.
  static Future<void> releaseAllDevices(Iterable<String> deviceIds) {
    return runExclusive(() async {
      await _disconnectAllLocksBeforeConnect(
        deviceIds.isNotEmpty ? deviceIds.first : '',
        knownDeviceIds: deviceIds,
      );
      await _waitForGattSettle();
    });
  }

  /// Awaited stopScan — connecting while scanning is a known cause of GATT 133 on Android.
  static Future<void> _stopScanBeforeConnect() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  static Duration _connectBackoffForRetry(int failedRetryCount) {
    if (failedRetryCount < 0) {
      return _connectBackoffDelays.first;
    }
    if (failedRetryCount >= _connectBackoffDelays.length) {
      return _connectBackoffDelays.last;
    }
    return _connectBackoffDelays[failedRetryCount];
  }

  /// Disconnects every active/previous lock before a new interactive connection.
  static Future<void> _disconnectAllLocksBeforeConnect(
    String targetDeviceId, {
    Iterable<String> knownDeviceIds = const [],
  }) async {
    await _stopScanBeforeConnect();

    final idsToDisconnect = <String>{
      ...knownDeviceIds,
      if (_activeDeviceId != null) _activeDeviceId!,
      for (final connected in FlutterBluePlus.connectedDevices)
        connected.remoteId.str,
      if (targetDeviceId.isNotEmpty) targetDeviceId,
    };

    for (final deviceId in idsToDisconnect) {
      await _forceReleaseDevice(deviceId);
    }
  }

  /// Scan stop, full disconnect, and stack settle before the first connect attempt.
  static Future<void> _beginConnectSequence(String deviceId) async {
    await _stopScanBeforeConnect();
    await _ensureFullyDisconnected(deviceId);
    await _waitBeforeConnect();
  }

  /// Mandatory pause after disconnect so the OS and peripheral can reset GATT state.
  static Future<void> _waitForGattSettle() async {
    await Future<void>.delayed(_postDisconnectSettleDelay);
  }

  /// Unconditional delay before [BluetoothDevice.connect] so Android can release
  /// the previous GATT object (avoids Error 133 / rapid reconnect flooding).
  static Future<void> _waitBeforeConnect() async {
    await Future<void>.delayed(_preConnectDelay);
  }

  static bool _isConnectRetryableError(Object error) {
    return _isAndroidGatt133Error(error);
  }

  /// Force-aborts a pending native GATT connect when Dart times out before Android (30s).
  /// Always targets [device] — never skips because isDisconnected is false during connect.
  static Future<void> _abortPendingConnect(BluetoothDevice device) async {
    try {
      await device.disconnect(queue: false);
    } catch (_) {}

    await Future<void>.delayed(_postAbortConnectDelay);
  }

  /// Cancels a failed connect attempt and tears down any partial GATT session.
  static Future<void> _handleConnectFailure(String deviceId) async {
    _resetHandshakeState(deviceId);
    try {
      await _ensureFullyDisconnected(deviceId);
    } catch (_) {}
  }

  static const String deviceUnreachableMessage =
      'Device out of range or not found.';

  static bool _isAndroidGatt133Error(Object error) {
    if (error is FlutterBluePlusException) {
      if (error.code == 133) return true;
      final description = error.description?.toUpperCase() ?? '';
      if (description.contains('ANDROID_SPECIFIC_ERROR')) return true;
    }

    final message = error.toString().toUpperCase();
    return message.contains('ANDROID_SPECIFIC_ERROR') ||
        message.contains('GATT_ERROR') ||
        RegExp(r'\b133\b').hasMatch(message);
  }

  /// Async recursive connect with exponential backoff for Android GATT 133 (#532).
  ///
  /// [retryCount] resets to 0 at the start of each new connection cycle.
  static Future<BluetoothDevice> connectWithRetry(
    String deviceId, {
    int retryCount = 0,
  }) async {
    if (retryCount == 0) {
      await _beginConnectSequence(deviceId);
    } else {
      await _stopScanBeforeConnect();
    }

    final device = BluetoothDevice.fromId(deviceId);

    try {
      try {
        await device
            .connect(
              timeout: _connectAttemptTimeout,
              license: License.free,
              autoConnect: false,
            )
            .timeout(_connectAttemptTimeout);
      } on TimeoutException {
        await _abortPendingConnect(device);
        rethrow;
      }

      if (!device.isConnected) {
        throw StateError(
          'Connect finished but device ${device.remoteId.str} is not connected',
        );
      }

      try {
        await device.discoverServices().timeout(_connectAttemptTimeout);
      } on TimeoutException {
        await _safeDisconnect(device);
        rethrow;
      }

      return device;
    } on TimeoutException {
      await _handleConnectFailure(deviceId);
      rethrow;
    } catch (error) {
      await _safeDisconnect(device);

      if (!_isConnectRetryableError(error) ||
          retryCount >= _maxConnectRetryCount) {
        await _handleConnectFailure(deviceId);
        if (error is Exception) {
          rethrow;
        }
        throw Exception(error.toString());
      }

      return _retryConnectAfterBackoff(
        deviceId,
        retryCount: retryCount,
      );
    }
  }

  /// Schedules the next connect attempt after an async exponential backoff delay.
  static Future<BluetoothDevice> _retryConnectAfterBackoff(
    String deviceId, {
    required int retryCount,
  }) async {
    await Future<void>.delayed(_connectBackoffForRetry(retryCount));
    await _stopScanBeforeConnect();
    await _ensureFullyDisconnected(deviceId);

    return connectWithRetry(
      deviceId,
      retryCount: retryCount + 1,
    );
  }

  /// Drops tokens, tears down GATT, flushes cache, and waits before a fresh connect.
  static Future<void> _discardDeviceSession(String deviceId) async {
    await _forceReleaseDevice(deviceId);
    await _waitForGattSettle();
  }

  /// Explicitly awaits [device.disconnect] (with Android delay) and confirmed teardown.
  static Future<void> _awaitDisconnect(BluetoothDevice device) async {
    await device.disconnect(
      queue: false,
      androidDelay: _androidDisconnectDelayMs,
    );

    if (device.isConnected) {
      await device.connectionState
          .where((state) => state == BluetoothConnectionState.disconnected)
          .first
          .timeout(_disconnectTimeout);
    }
  }

  /// Ensures GATT is fully closed before any connect attempt.
  static Future<void> _ensureFullyDisconnected(String deviceId) async {
    final device = BluetoothDevice.fromId(deviceId);

    if (device.isConnected) {
      await _disableLockNotification(device);
    }

    await _awaitDisconnect(device);
    await _flushGattResources(device);
    await _waitForGattSettle();
  }

  /// Returns true when the lock is actively advertising during a short scan.
  static Future<bool> scanForDevice(String deviceId) {
    return runExclusive(() async {
      await _stopScanBeforeConnect();

      var found = false;
      final subscription = FlutterBluePlus.onScanResults.listen((results) {
        if (results.any((result) => result.device.remoteId.str == deviceId)) {
          found = true;
        }
      });

      try {
        await FlutterBluePlus.startScan(timeout: _scanPresenceTimeout);
        await Future<void>.delayed(_scanPresenceTimeout);
      } catch (_) {
      } finally {
        await subscription.cancel();
        await _stopScanBeforeConnect();
      }

      return found;
    });
  }

  static bool isDeviceConnected(String deviceId) {
    final device = BluetoothDevice.fromId(deviceId);
    return device.isConnected && _isValidToken(_deviceTokens[deviceId]);
  }

  static Future<void> disconnectDevice(String deviceId) async {
    await resetDeviceConnection(deviceId);
  }

  static Future<void> _resetDeviceConnectionInternal(String deviceId) async {
    await _forceReleaseDevice(deviceId);
  }

  /// Disables notifications, disconnects, waits for GATT teardown, and clears cache.
  static Future<void> _forceReleaseDevice(String deviceId) async {
    _resetHandshakeState(deviceId);

    final device = BluetoothDevice.fromId(deviceId);
    await _tearDownDeviceConnection(device);
  }

  /// Fully closes the GATT link: disable notifications, disconnect, confirm teardown, flush cache.
  static Future<void> _tearDownDeviceConnection(BluetoothDevice device) async {
    if (device.isConnected) {
      await _disableLockNotification(device);
    }

    await _awaitDisconnect(device);
    await _flushGattResources(device);
  }

  static Future<void> _flushGattResources(BluetoothDevice device) async {
    try {
      await device.clearGattCache();
    } catch (_) {}

    // Second cache clear after a brief pause helps Android release stale handles.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    try {
      await device.clearGattCache();
    } catch (_) {}
  }

  static Future<void> _disableLockNotification(BluetoothDevice device) async {
    try {
      final characteristic = await _findLockCharacteristic(device);
      if (characteristic == null || !characteristic.isNotifying) return;

      await characteristic
          .setNotifyValue(false)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  static Future<void> resetDeviceConnection(String deviceId) {
    return runExclusive(() => _resetDeviceConnectionInternal(deviceId));
  }

  static Future<bool> verifyConnection(String deviceId) async {
    if (!_isValidToken(_deviceTokens[deviceId])) {
      return false;
    }

    final device = BluetoothDevice.fromId(deviceId);
    return device.isConnected;
  }

  static Future<void> disconnectActiveDevice() async {
    final activeId = _activeDeviceId;
    if (activeId == null) return;
    await disconnectDevice(activeId);
  }

  static Future<bool> switchConnection(
    String deviceId, {
    Iterable<String> knownDeviceIds = const [],
  }) {
    return runExclusive(() async {
      if (_activeDeviceId == deviceId && await verifyConnection(deviceId)) {
        return true;
      }

      await releaseAdapterForNewConnection(
        deviceId,
        knownDeviceIds: knownDeviceIds,
      );
      return _connectImpl(deviceId);
    });
  }

  static void clearDeviceSession(String deviceId) {
    _resetHandshakeState(deviceId);
  }

  /// Clears cached token/session state for a lock before a fresh handshake.
  static void cacheDeviceEncryptKey(String deviceId, String encryptKey) {
    _deviceEncryptKeys[deviceId] = encryptKey.toLowerCase();
    currentEncryptKey = encryptKey.toLowerCase();
  }

  static void _resetHandshakeState(String deviceId) {
    _deviceTokens.remove(deviceId);
    _deviceEncryptKeys.remove(deviceId);
    if (_activeDeviceId == deviceId) {
      _activeDeviceId = null;
    }
    currentEncryptKey = DataRequestPattern.defaultEncryptKey;
    unawaited(_cancelHandshakeSubscriptions(deviceId));
  }

  static Future<void> _cancelHandshakeSubscriptions(String deviceId) async {
    final subscription = _handshakeNotifySubscriptions.remove(deviceId);
    await subscription?.cancel();
  }

  static Future<void> prepareFreshConnection(String deviceId) async {
    await resetDeviceConnection(deviceId);
  }
  static final Guid _batteryServiceUuid = Guid('180f');
  static final Guid _batteryLevelCharacteristicUuid = Guid('2a19');
  static final Guid _lockServiceUuid = Guid('fee7');
  static final Guid _lockWriteCharacteristicUuid = Guid('36f5');
  static final Guid _lockNotifyCharacteristicUuid = Guid('36f6');
  static const Duration _streamResponseTimeout = Duration(seconds: 2);
  static const Duration _handshakeTimeout = Duration(seconds: 3);
  static const Duration _handshakeNotifyTimeout = Duration(milliseconds: 2000);
  static const Duration _batteryReadTimeout = Duration(seconds: 3);
  static const List<int> _discreteBatteryLevels = [0, 20, 40, 60, 80, 100];

  static Future<String> _resolveEncryptKey(String deviceId) async {
    final cached = _deviceEncryptKeys[deviceId];
    if (cached != null && cached.isNotEmpty) {
      currentEncryptKey = cached;
      return cached;
    }

    final storedSecret = await LockSecretStorage.getSecretKey(deviceId);
    if (storedSecret != null && storedSecret.isNotEmpty) {
      cacheDeviceEncryptKey(deviceId, storedSecret);
      return storedSecret;
    }

    final defaultKey = DataRequestPattern.getDefaultEncryptKey(deviceId);
    currentEncryptKey = defaultKey;
    return defaultKey;
  }

  static BluetoothService? _findLockService(List<BluetoothService> services) {
    for (final service in services) {
      if (service.uuid == _lockServiceUuid) {
        return service;
      }
    }
    return null;
  }

  static BluetoothCharacteristic? _findCharacteristic(
    List<BluetoothService> services,
    Guid characteristicUuid, {
    bool write = false,
    bool notify = false,
  }) {
    final lockService = _findLockService(services);
    if (lockService == null) return null;

    for (final characteristic in lockService.characteristics) {
      if (characteristic.uuid != characteristicUuid) continue;
      if (write && !characteristic.properties.write) continue;
      if (notify &&
          !(characteristic.properties.notify ||
              characteristic.properties.read)) {
        continue;
      }
      return characteristic;
    }
    return null;
  }

  static BluetoothCharacteristic? _selectLockNotifyCharacteristic(
    List<BluetoothService> services,
  ) {
    return _findCharacteristic(
      services,
      _lockNotifyCharacteristicUuid,
      notify: true,
    );
  }

  static BluetoothCharacteristic? _selectTokenWriteCharacteristic(
    List<BluetoothService> services,
  ) {
    return _findCharacteristic(
      services,
      _lockWriteCharacteristicUuid,
      write: true,
    );
  }

  /// Always performs live GATT service discovery. Never returns [BluetoothDevice.servicesList]
  /// without calling [BluetoothDevice.discoverServices] — stale handles break Android reconnects.
  static Future<List<BluetoothService>> _discoverServices(
    BluetoothDevice device,
  ) async {
    return device.discoverServices();
  }

  /// Discovers services and resolves handshake characteristics for this connection session only.
  static Future<
      ({
        BluetoothCharacteristic? notify,
        BluetoothCharacteristic? write,
      })> _resolveHandshakeCharacteristics(BluetoothDevice device) async {
    final services =
        await _discoverServices(device).timeout(_handshakeTimeout);
    return (
      notify: _selectLockNotifyCharacteristic(services),
      write: _selectTokenWriteCharacteristic(services),
    );
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _normalizeBatteryLevel(int rawLevel) {
    if (rawLevel >= 0 && rawLevel < _discreteBatteryLevels.length) {
      return _discreteBatteryLevels[rawLevel];
    }
    return rawLevel.clamp(0, 100);
  }

  static bool _isInvalidToken(String? token) {
    return token == null || token == DataRequestPattern.defaultTokenHex;
  }

  static bool _isValidToken(String? token) {
    return !_isInvalidToken(token);
  }

  static Future<BluetoothCharacteristic?> _findLockCharacteristic(
    BluetoothDevice device,
  ) async {
    final services =
        await _discoverServices(device).timeout(_streamResponseTimeout);
    return _selectLockNotifyCharacteristic(services);
  }

  static Future<void> _writeEncryptedFrame(
    String deviceId,
    String frameHex, {
    required BluetoothCharacteristic writeCharacteristic,
    String? encryptKey,
    int writeTimeout = 3,
  }) async {
    final resolvedKey = encryptKey ?? await _resolveEncryptKey(deviceId);
    final encryptedData = DataService.encrypt(frameHex, resolvedKey);
    if (encryptedData == null) {
      throw LockAuthenticationException(
        deviceId,
        message: 'Failed to encrypt BLE command frame.',
      );
    }

    await writeCharacteristic
        .write(
          encryptedData,
          allowLongWrite: true,
          timeout: writeTimeout,
        )
        .timeout(Duration(seconds: writeTimeout));
  }

  static Future<void> _writeTokenChallenge(
    String deviceId,
    BluetoothCharacteristic writeCharacteristic,
  ) async {
    await _writeEncryptedFrame(
      deviceId,
      DataRequestPattern.getTokenRequestHex(),
      writeCharacteristic: writeCharacteristic,
      writeTimeout: _handshakeNotifyTimeout.inSeconds,
    );
  }

  /// Handshake: enable CCCD → settle → listen → write challenge → await notify.
  static Future<List<int>?> _readFreshTokenResponse(String deviceId) async {
    await _cancelHandshakeSubscriptions(deviceId);

    final device = BluetoothDevice.fromId(deviceId);
    final sessionCharacteristics = await _resolveHandshakeCharacteristics(device);
    final notifyCharacteristic = sessionCharacteristics.notify;
    if (notifyCharacteristic == null) {
      return readData(deviceId, timeout: _handshakeNotifyTimeout);
    }

    final writeCharacteristic = sessionCharacteristics.write;
    if (writeCharacteristic == null) {
      return null;
    }

    StreamSubscription<List<int>>? subscription;
    try {
      // 1. Enable notifications on the lock characteristic.
      await notifyCharacteristic.setNotifyValue(true).timeout(_handshakeTimeout);

      // 2. Let peripheral hardware finish processing the CCCD descriptor.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // 3. Listen for new notifications only (not cached lastValueStream replay).
      final completer = Completer<List<int>>();
      subscription = notifyCharacteristic.onValueReceived.listen((value) {
        if (value.isEmpty || completer.isCompleted) return;
        completer.complete(List<int>.from(value));
      });
      _handshakeNotifySubscriptions[deviceId] = subscription;

      // 4. Write command 06 01 to characteristic 36F5 (encrypted).
      await _writeTokenChallenge(deviceId, writeCharacteristic);

      // 5. Await the lock's response notification.
      final response = await completer.future.timeout(
        _handshakeNotifyTimeout,
        onTimeout: () => throw TimeoutException('Token handshake timed out'),
      );
      return response;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      await subscription?.cancel();
      _handshakeNotifySubscriptions.remove(deviceId);
    }
  }

  static Future<List<int>> _awaitLockCharacteristicValue(
    BluetoothCharacteristic characteristic,
    List<int> previousValue,
  ) async {
    return characteristic.lastValueStream
        .where(
          (value) => value.isNotEmpty && !_bytesEqual(value, previousValue),
        )
        .first
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => <int>[],
        );
  }

  static Future<List<int>> _readLockCharacteristic(
    BluetoothCharacteristic characteristic,
  ) async {
    return characteristic
        .read(timeout: _streamResponseTimeout.inSeconds)
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => <int>[],
        );
  }

  static Future<int?> _readGattBatteryLevel(BluetoothDevice device) async {
    try {
      final services = await _discoverServices(device).timeout(
        _batteryReadTimeout,
        onTimeout: () => <BluetoothService>[],
      );

      for (final service in services) {
        if (service.uuid != _batteryServiceUuid) continue;

        for (final characteristic in service.characteristics) {
          if (characteristic.uuid != _batteryLevelCharacteristicUuid) continue;
          if (!characteristic.properties.read) continue;

          try {
            final value = await characteristic
                .read(timeout: _batteryReadTimeout.inSeconds)
                .timeout(
                  _batteryReadTimeout,
                  onTimeout: () => <int>[],
                );

            if (value.isEmpty) return null;

            return _normalizeBatteryLevel(value.first);
          } catch (_) {
            return null;
          }
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static int? _parseBatteryFromLockResponse(
    List<int> response,
    String encryptKey,
  ) {
    if (response.isEmpty) return null;

    final hexResponse = DataService.bytesToHexString(response);
    if (hexResponse.length < 32) return null;

    final decryptedResponse = DataService.decrypt(
      hexResponse.substring(0, 32),
      encryptKey,
    );
    if (decryptedResponse == null || decryptedResponse.length < 4) {
      return null;
    }

    if (decryptedResponse[0] != 2 ||
        decryptedResponse[1] != 2 ||
        decryptedResponse[2] != 1) {
      return null;
    }

    return _normalizeBatteryLevel(decryptedResponse[3]);
  }

  static Future<int?> _readCustomBatteryLevel(
    String deviceId,
    String token,
  ) async {
    try {
      return await _readCustomBatteryLevelInternal(deviceId, token)
          .timeout(_batteryReadTimeout);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _readCustomBatteryLevelInternal(
    String deviceId,
    String token,
  ) async {
    final device = BluetoothDevice.fromId(deviceId);
    final encryptKey = await _resolveEncryptKey(deviceId);
    final characteristic = await _findLockCharacteristic(device);
    if (characteristic == null) return null;

    final previousValue = List<int>.from(characteristic.lastValue);

    await writeData(deviceId, DataRequestPattern.getPowerHex(token));

    List<int> response = <int>[];
    try {
      response = await _awaitLockCharacteristicValue(
        characteristic,
        previousValue,
      );
    } catch (_) {}

    if (response.isEmpty &&
        characteristic.uuid == _lockNotifyCharacteristicUuid) {
      try {
        response = await _readLockCharacteristic(characteristic);
      } catch (_) {}
    }

    if (response.isEmpty) return null;
    return _parseBatteryFromLockResponse(response, encryptKey);
  }

  static Future<void> writeData(
    String deviceId,
    String data, {
    bool ignoreEncryption = false,
    int writeTimeout = 3,
    String? encryptKeyOverride,
  }) async {
    try {
      await _writeDataInternal(
        deviceId,
        data,
        ignoreEncryption: ignoreEncryption,
        writeTimeout: writeTimeout,
        encryptKeyOverride: encryptKeyOverride,
      ).timeout(Duration(seconds: writeTimeout));
    } catch (_) {
      return;
    }
  }

  static Future<void> _writeDataInternal(
    String deviceId,
    String data, {
    required bool ignoreEncryption,
    required int writeTimeout,
    String? encryptKeyOverride,
  }) async {
    final device = BluetoothDevice.fromId(deviceId);
    final services = await _discoverServices(device).timeout(
      Duration(seconds: writeTimeout),
      onTimeout: () => <BluetoothService>[],
    );

    final writeCharacteristic = _selectTokenWriteCharacteristic(services);
    if (writeCharacteristic == null) return;

    if (ignoreEncryption) {
      final payload = DataService.hexStringToBytesList(data);
      await writeCharacteristic
          .write(
            payload,
            allowLongWrite: true,
            timeout: writeTimeout,
          )
          .timeout(Duration(seconds: writeTimeout));
      return;
    }

    await _writeEncryptedFrame(
      deviceId,
      data,
      writeCharacteristic: writeCharacteristic,
      encryptKey: encryptKeyOverride,
      writeTimeout: writeTimeout,
    );
  }

  static Future<List<int>?> readData(
    String deviceId, {
    Duration timeout = _handshakeTimeout,
  }) async {
    final device = BluetoothDevice.fromId(deviceId);

    try {
      final services = await _discoverServices(device).timeout(
        timeout,
        onTimeout: () => <BluetoothService>[],
      );
      final notifyCharacteristic = _selectLockNotifyCharacteristic(services);
      if (notifyCharacteristic == null) return null;

      return notifyCharacteristic
          .read(timeout: timeout.inSeconds)
          .timeout(
            timeout,
            onTimeout: () => <int>[],
          );
    } on TimeoutException {
      return null;
    } catch (_) {}

    return null;
  }

  static Future<String?> _parseTokenFromResponse(
    String deviceId,
    List<int> response,
  ) async {
    if (response.isEmpty) return null;

    final hexResponse = DataService.bytesToHexString(response);
    if (hexResponse.length < 32) return null;

    final encryptKey = await _resolveEncryptKey(deviceId);
    final decryptedResponse = DataService.decrypt(
      hexResponse.substring(0, 32),
      encryptKey,
    );
    if (decryptedResponse == null) return null;

    final token = DataRequestPattern.parseSessionToken(decryptedResponse);
    if (_isInvalidToken(token)) return null;
    return token;
  }

  static Future<String> getToken(
    String deviceId, {
    bool ignoreConnect = false,
    bool forceFresh = true,
  }) async {
    if (forceFresh) {
      _resetHandshakeState(deviceId);
    }

    for (var attempt = 0; attempt < _maxHandshakeAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      try {
        final token = await _getTokenInternal(
          deviceId,
          ignoreConnect: ignoreConnect,
        ).timeout(
          _handshakeTimeout,
          onTimeout: () => DataRequestPattern.defaultTokenHex,
        );

        if (_isValidToken(token)) {
          _deviceTokens[deviceId] = token;
          print('DEBUG: getToken completed: $token');
          return token;
        }
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }

    print('DEBUG: getToken completed: ${DataRequestPattern.defaultTokenHex}');
    return DataRequestPattern.defaultTokenHex;
  }

  static Future<String> _getTokenInternal(
    String deviceId, {
    bool ignoreConnect = false,
  }) async {
    if (!ignoreConnect) {
      final isConnected = await BleService.connect(deviceId);
      if (!isConnected) {
        return DataRequestPattern.defaultTokenHex;
      }
    }

    final response = await _readFreshTokenResponse(deviceId);
    if (response == null || response.isEmpty) {
      return DataRequestPattern.defaultTokenHex;
    }

    return await _parseTokenFromResponse(deviceId, response) ??
        DataRequestPattern.defaultTokenHex;
  }

  static Future<void> _safeDisconnect(BluetoothDevice device) async {
    if (device.isDisconnected) return;

    try {
      await _awaitDisconnect(device);
    } catch (_) {
      await _tearDownDeviceConnection(device);
    }
  }

  static Future<void> _setupConnectedDevice(
    BluetoothDevice device,
    bool Function() disconnectedDuringSetup,
    void Function() markReachedConnected,
  ) async {
    try {
      await device
          .requestConnectionPriority(
            connectionPriorityRequest: ConnectionPriority.high,
          )
          .timeout(_connectionTimeout);
    } catch (_) {}

    markReachedConnected();
    // Service discovery runs in [connectWithRetry] immediately after connect.
  }

  static Future<bool> connect(String deviceId) {
    return runExclusive(() => _connectImpl(deviceId));
  }

  static Future<bool> _connectImpl(String deviceId) async {
    final device = BluetoothDevice.fromId(deviceId);

    if (device.isConnected && _isValidToken(_deviceTokens[deviceId])) {
      final linkAlive = await verifyConnection(deviceId);
      if (linkAlive) {
        _activeDeviceId = deviceId;
        print('DEBUG: connect completed successfully');
        return true;
      }

      await _discardDeviceSession(deviceId);
    } else {
      _resetHandshakeState(deviceId);
    }

    return _attemptConnect(deviceId);
  }

  /// Starts a new connection cycle — [retryCount] is always reset to 0.
  static Future<BluetoothDevice?> _connectDeviceWithRetry(String deviceId) async {
    try {
      return await connectWithRetry(deviceId);
    } on TimeoutException {
      await _handleConnectFailure(deviceId);
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _attemptConnect(String deviceId) async {
    StreamSubscription<BluetoothConnectionState>? connectionSubscription;
    var reachedConnectedState = false;
    var disconnectedDuringSetup = false;
    var connected = false;
    BluetoothDevice? device;

    try {
      device = await _connectDeviceWithRetry(deviceId);
      if (device == null) {
        return false;
      }

      connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          reachedConnectedState = true;
        } else if (state == BluetoothConnectionState.disconnected &&
            reachedConnectedState) {
          disconnectedDuringSetup = true;
        }
      });

      if (device.isDisconnected || disconnectedDuringSetup) {
        await _safeDisconnect(device);
        return false;
      }

      await _setupConnectedDevice(
        device,
        () => disconnectedDuringSetup,
        () => reachedConnectedState = true,
      );

      if (!device.isConnected || disconnectedDuringSetup) {
        await _safeDisconnect(device);
        return false;
      }

      final token = await getToken(
        deviceId,
        ignoreConnect: true,
        forceFresh: true,
      );
      if (!_isValidToken(token)) {
        print('DEBUG: Handshake failed');
        await _safeDisconnect(device);
        return false;
      }

      _deviceTokens[deviceId] = token;
      _activeDeviceId = deviceId;
      connected = true;
      return true;
    } on TimeoutException {
      if (device != null) {
        await _safeDisconnect(device);
      }
      return false;
    } catch (_) {
      if (device != null) {
        await _safeDisconnect(device);
      }
      return false;
    } finally {
      await connectionSubscription?.cancel();
      connectionSubscription = null;
      if (!connected) {
        await _handleConnectFailure(deviceId);
      } else {
        print('DEBUG: connect completed successfully');
      }
    }
  }

  static Future<List<int>?> _decryptLockResponse(
    String deviceId,
    List<int> response, {
    String? encryptKey,
  }) async {
    if (response.isEmpty) return null;

    final hexResponse = DataService.bytesToHexString(response);
    if (hexResponse.length < 32) return null;

    final resolvedKey = encryptKey ?? await _resolveEncryptKey(deviceId);
    return DataService.decrypt(
      hexResponse.substring(0, 32),
      resolvedKey,
    );
  }

  static Future<bool> _isAuthFailureResponse(
    String deviceId,
    List<int> response, {
    String? encryptKey,
  }) async {
    final decrypted = await _decryptLockResponse(
      deviceId,
      response,
      encryptKey: encryptKey,
    );
    if (decrypted == null || decrypted.length < 4) {
      return true;
    }

    final status = decrypted[3];
    return status == 0x00 || status == 0xFF;
  }

  static Future<bool> _isUnlockAck(
    String deviceId,
    List<int> response, {
    String? encryptKey,
  }) async {
    final decrypted = await _decryptLockResponse(
      deviceId,
      response,
      encryptKey: encryptKey,
    );
    if (decrypted == null || decrypted.length < 4) {
      return false;
    }

    return decrypted[0] == 0x05 &&
        decrypted[1] == 0x01 &&
        decrypted[2] == 0x06 &&
        decrypted[3] != 0x00 &&
        decrypted[3] != 0xFF;
  }

  static Future<bool> _isProvisionAck(
    String deviceId,
    List<int> response, {
    String? encryptKey,
  }) async {
    final decrypted = await _decryptLockResponse(
      deviceId,
      response,
      encryptKey: encryptKey,
    );
    if (decrypted == null || decrypted.length < 3) {
      return false;
    }

    return decrypted[0] == 0x07 &&
        (decrypted[1] == 0x01 || decrypted[1] == 0x02) &&
        (decrypted.length < 4 ||
            (decrypted[3] != 0x00 && decrypted[3] != 0xFF));
  }

  static Future<List<int>> _sendLockCommandAndReadResponse(
    String deviceId,
    String payload, {
    String? encryptKeyOverride,
  }) async {
    final device = BluetoothDevice.fromId(deviceId);
    final characteristic = await _findLockCharacteristic(device);
    if (characteristic == null) {
      throw LockAuthenticationException(
        deviceId,
        message: 'Lock notify characteristic unavailable.',
      );
    }

    final previousValue = List<int>.from(characteristic.lastValue);
    await writeData(
      deviceId,
      payload,
      encryptKeyOverride: encryptKeyOverride,
    );

    var response = await _awaitLockCharacteristicValue(
      characteristic,
      previousValue,
    );

    if (response.isEmpty) {
      response = await _readLockCharacteristic(characteristic);
    }

    return response;
  }

  static Future<void> provisionSecretKey({
    required String deviceId,
    required String secretKey,
    required String token,
  }) async {
    if (_isInvalidToken(token)) {
      throw LockAuthenticationException(
        deviceId,
        message: 'Invalid session token for provisioning.',
      );
    }

    final defaultKey = DataRequestPattern.getDefaultEncryptKey(deviceId);
    final payloads = DataRequestPattern.getSecretKeyProvisioningPayloads(
      secretKey,
    );

    for (final payload in [payloads.$1, payloads.$2]) {
      final response = await _sendLockCommandAndReadResponse(
        deviceId,
        payload,
        encryptKeyOverride: defaultKey,
      );
      if (await _isAuthFailureResponse(
            deviceId,
            response,
            encryptKey: defaultKey,
          ) ||
          !await _isProvisionAck(
            deviceId,
            response,
            encryptKey: defaultKey,
          )) {
        throw LockAuthenticationException(
          deviceId,
          message: 'Failed to provision ownership secret to the lock.',
        );
      }
    }

    cacheDeviceEncryptKey(deviceId, secretKey);
  }

  static Future<bool> requestToUnlock(String deviceId) async {
    await PairingService.ensurePairedForUnlock(deviceId);

    final secretKey = await LockSecretStorage.getSecretKey(deviceId);
    if (secretKey == null || secretKey.isEmpty) {
      throw LockAuthenticationException(
        deviceId,
        message: 'No ownership secret found for this lock.',
      );
    }

    cacheDeviceEncryptKey(deviceId, secretKey);

    final token = _deviceTokens[deviceId] ??
        await BleService.getToken(deviceId, ignoreConnect: true);

    if (_isInvalidToken(token)) {
      throw LockAuthenticationException(
        deviceId,
        message: 'Invalid session token for unlock.',
      );
    }

    await Future.delayed(const Duration(seconds: 1));
    final response = await _sendLockCommandAndReadResponse(
      deviceId,
      DataRequestPattern.getUnlockHex(token),
      encryptKeyOverride: secretKey,
    );

    if (await _isAuthFailureResponse(
          deviceId,
          response,
          encryptKey: secretKey,
        ) ||
        !await _isUnlockAck(
          deviceId,
          response,
          encryptKey: secretKey,
        )) {
      throw LockAuthenticationException(deviceId);
    }

    return true;
  }

  static Future<bool> connectAndUnLock(String deviceId) async {
    final isConnected = await BleService.connect(deviceId);
    if (!isConnected) throw Exception('Cannot connect to the Smart Lock');

    return BleService.requestToUnlock(deviceId);
  }

  static Future<int> _fetchBatteryLevel(String deviceId, String token) async {
    final device = BluetoothDevice.fromId(deviceId);

    int? gattBatteryLevel;
    try {
      gattBatteryLevel = await _readGattBatteryLevel(device).timeout(
        _batteryReadTimeout,
        onTimeout: () => null,
      );
    } on TimeoutException {
      gattBatteryLevel = null;
    } catch (_) {
      gattBatteryLevel = null;
    }

    if (gattBatteryLevel != null) {
      return gattBatteryLevel;
    }

    int? customBatteryLevel;
    try {
      customBatteryLevel = await _readCustomBatteryLevel(deviceId, token)
          .timeout(
        _batteryReadTimeout,
        onTimeout: () => null,
      );
    } on TimeoutException {
      customBatteryLevel = null;
    } catch (_) {
      customBatteryLevel = null;
    }

    return customBatteryLevel ?? -1;
  }

  static Future<int> getBatteryLevel(
    String deviceId, {
    bool ignoreConnect = false,
    String? token,
  }) async {
    try {
      if (!ignoreConnect) {
        final isConnected = await BleService.connect(deviceId);
        if (!isConnected) {
          print('DEBUG: getBatteryLevel failed/timed out');
          return -1;
        }
      }

      final activeToken = token ?? _deviceTokens[deviceId];
      if (_isInvalidToken(activeToken)) {
        return -1;
      }

      final result = await _fetchBatteryLevel(deviceId, activeToken!)
          .timeout(_batteryReadTimeout);

      if (result >= 0) {
        print('DEBUG: getBatteryLevel completed with $result');
        return result;
      }

      print('DEBUG: getBatteryLevel failed/timed out');
      return -1;
    } on TimeoutException {
      print('DEBUG: getBatteryLevel failed/timed out');
      return -1;
    } catch (_) {
      print('DEBUG: getBatteryLevel failed/timed out');
      return -1;
    }
  }
}
