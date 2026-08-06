import 'dart:async';

import 'package:fitness_snack_lock/services/data_service.dart';
import 'package:fitness_snack_lock/services/pairing_service.dart';
import 'package:fitness_snack_lock/services/paired_lock_storage.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static String currentEncryptKey = DataRequestPattern.defaultEncryptKey;

  static String? _activeDeviceId;
  static final Map<String, String> _deviceTokens = {};
  static final Map<String, String> _deviceEncryptKeys = {};
  static final Map<String, bool> _deviceUnlockedThisSession = {};
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

  static bool requiresClaiming(String deviceId) => false;

  static void clearRequiresClaiming(String deviceId) {}

  static void _logHandshake(String message) {
    print('BLE Handshake: $message');
  }

  static void _logUnlock(String message) {
    print('BLE Unlock: $message');
  }

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

  /// Tears down the GATT link after a short-lived connect/unlock operation.
  static Future<void> releaseOnDemandConnection(String deviceId) {
    return runExclusive(() => _releaseOnDemandConnectionInternal(deviceId));
  }

  static Future<void> _releaseOnDemandConnectionInternal(String deviceId) async {
    await _explicitlyCloseGattConnection(deviceId);
  }

  /// Fully closes the GATT link after on-demand connect/unlock (ST17H65 pattern).
  static Future<void> _explicitlyCloseGattConnection(String deviceId) async {
    _logUnlock('Explicitly closing GATT connection for $deviceId');
    _resetHandshakeState(deviceId);
    if (_activeDeviceId == deviceId) {
      _activeDeviceId = null;
    }

    final device = BluetoothDevice.fromId(deviceId);
    try {
      if (device.isConnected) {
        await _disableLockNotification(device);
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
    } catch (error) {
      _logUnlock('GATT disconnect warning for $deviceId: $error');
    }

    await _flushGattResources(device);
    await _waitForGattSettle();
  }

  /// Disconnects every active lock when the app backgrounds or resets BLE state.
  static Future<void> releaseAllActiveConnections({
    Iterable<String> knownDeviceIds = const [],
  }) {
    return runExclusive(() async {
      _activeDeviceId = null;
      await _disconnectAllLocksBeforeConnect(
        '',
        knownDeviceIds: knownDeviceIds,
      );
      await _waitForGattSettle();
    });
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
    _deviceUnlockedThisSession.remove(deviceId);
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
  static const Duration _handshakeNotifyTimeout = Duration(seconds: 3);
  static const Duration _unlockConnectTimeout = Duration(seconds: 5);
  static const Duration _unlockWriteTimeout = Duration(seconds: 5);
  static const Duration _batteryReadTimeout = Duration(seconds: 3);
  static const List<int> _discreteBatteryLevels = [0, 20, 40, 60, 80, 100];

  static String _handshakeEncryptKey(String deviceId) {
    final cached = _deviceEncryptKeys[deviceId];
    if (cached != null && cached.isNotEmpty) {
      return cached.toLowerCase();
    }
    return DataRequestPattern.defaultEncryptKey.toLowerCase();
  }

  /// Loads the AES master key from secure storage before any handshake/unlock.
  static Future<String> _loadCredentialsForUnlock(String deviceId) async {
    await PairingService.ensurePairedForUnlock(deviceId);

    final encryptKey = await PairedLockStorage.ensureSecretKey(deviceId);
    if (encryptKey.isEmpty) {
      _logHandshake('ERROR: AES master key unavailable for $deviceId');
      throw LockAuthenticationException(
        deviceId,
        message:
            'Lock encryption key is missing. Remove the lock and add it again.',
      );
    }

    cacheDeviceEncryptKey(deviceId, encryptKey);
    _logHandshake(
      'Loaded AES master key for $deviceId (${encryptKey.substring(0, 8)}...)',
    );
    return encryptKey;
  }

  static const String _handshakeKeyLabel = 'Default';

  static Future<String> _resolveEncryptKey(String deviceId) async {
    final cached = _deviceEncryptKeys[deviceId];
    if (cached != null && cached.isNotEmpty) {
      currentEncryptKey = cached;
      return cached;
    }

    final key = _handshakeEncryptKey(deviceId);
    currentEncryptKey = key;
    return key;
  }

  static Future<void> _flushStaleNotifyBuffer(
    BluetoothCharacteristic notifyCharacteristic,
  ) async {
    try {
      await notifyCharacteristic
          .setNotifyValue(false)
          .timeout(_handshakeTimeout);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await notifyCharacteristic.setNotifyValue(true).timeout(_handshakeTimeout);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } catch (error) {
      _logHandshake('36F6 notify flush warning: $error');
    }
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
    return token == null || token.isEmpty;
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
    String? debugLabel,
  }) async {
    final resolvedKey = encryptKey ?? await _resolveEncryptKey(deviceId);
    final encryptedData = DataService.encrypt(frameHex, resolvedKey);
    if (encryptedData == null) {
      throw LockAuthenticationException(
        deviceId,
        message: 'Failed to encrypt BLE command frame.',
      );
    }

    if (debugLabel != null) {
      _logUnlock(
        '36F5 write [$debugLabel] plaintext=$frameHex '
        'encryptKey=${resolvedKey.substring(0, 8)}... '
        'encrypted=[${encryptedData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]',
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
    BluetoothCharacteristic writeCharacteristic, {
    required String encryptKey,
    required String encryptKeyLabel,
  }) async {
    _logHandshake(
      'Writing 06 01 to 36F5 encrypted with $encryptKeyLabel key '
      '(${encryptKey.substring(0, 8)}...)',
    );
    await _writeEncryptedFrame(
      deviceId,
      DataRequestPattern.getTokenRequestHex(),
      writeCharacteristic: writeCharacteristic,
      encryptKey: encryptKey,
      writeTimeout: _handshakeTimeout.inSeconds,
    );
  }

  static Future<List<int>?> _readFreshTokenResponse(
    String deviceId, {
    required String encryptKey,
    required String encryptKeyLabel,
  }) async {
    try {
      return await _readFreshTokenResponseInternal(
        deviceId,
        encryptKey: encryptKey,
        encryptKeyLabel: encryptKeyLabel,
      ).timeout(
        _handshakeTimeout,
        onTimeout: () {
          throw TimeoutException('Token handshake timed out');
        },
      );
    } on TimeoutException {
      _logHandshake('Timed out waiting for 36F6 response ($encryptKeyLabel write key)');
      await _cancelHandshakeSubscriptions(deviceId);
      return null;
    } catch (error) {
      _logHandshake(
        'Handshake read failed ($encryptKeyLabel write key): $error',
      );
      await _cancelHandshakeSubscriptions(deviceId);
      return null;
    }
  }

  /// Handshake: enable CCCD → settle → listen → write challenge → await notify.
  static Future<List<int>?> _readFreshTokenResponseInternal(
    String deviceId, {
    required String encryptKey,
    required String encryptKeyLabel,
  }) async {
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
      await notifyCharacteristic.setNotifyValue(true).timeout(_handshakeTimeout);
      await _flushStaleNotifyBuffer(notifyCharacteristic);

      final completer = Completer<List<int>>();
      var acceptNotifications = false;
      subscription = notifyCharacteristic.onValueReceived.listen((value) {
        if (value.isEmpty || completer.isCompleted || !acceptNotifications) {
          return;
        }
        completer.complete(List<int>.from(value));
      });
      _handshakeNotifySubscriptions[deviceId] = subscription;

      await _writeTokenChallenge(
        deviceId,
        writeCharacteristic,
        encryptKey: encryptKey,
        encryptKeyLabel: encryptKeyLabel,
      );
      acceptNotifications = true;
      _logHandshake(
        '36F6 listening for first post-write notify ($encryptKeyLabel write key)',
      );

      final response = await completer.future.timeout(
        _handshakeNotifyTimeout,
        onTimeout: () => throw TimeoutException('Token handshake timed out'),
      );

      final rawHex = DataService.bytesToHexString(response);
      _logHandshake(
        '36F6 raw response (${response.length} bytes, $encryptKeyLabel write key): '
        '$rawHex',
      );
      return response;
    } finally {
      await subscription?.cancel();
      _handshakeNotifySubscriptions.remove(deviceId);
    }
  }

  static ({String? token, String decryptKeyLabel, bool usedDefaultKey})?
      _parseTokenWithKey(
    List<int> response,
    String encryptKey,
    String decryptKeyLabel,
  ) {
    if (response.isEmpty) return null;

    if (DataService.isFramedSuffixNotify(response)) {
      _logHandshake(
        '$decryptKeyLabel key: framed notify layout '
        '${DataService.describeFramedNotify(response)}',
      );
    }

    final sliceCandidates = DataService.aesCiphertextBlockCandidates(response);

    for (final candidate in sliceCandidates) {
      final block = candidate.block;
      final ciphertextHex = DataService.bytesListToHexString(block);

      _logHandshake(
        '$decryptKeyLabel key: trying AES candidate ${candidate.label} '
        'block=$ciphertextHex from ${response.length}-byte notify '
        '(raw=${DataService.bytesToHexString(response)})',
      );

      final decryptedResponse = DataService.decrypt(ciphertextHex, encryptKey);
      if (decryptedResponse == null) {
        _logHandshake(
          '$decryptKeyLabel key: AES decrypt failed for $ciphertextHex',
        );
        continue;
      }

      final decryptedHex = DataService.bytesListToHexString(decryptedResponse);
      _logHandshake(
        '$decryptKeyLabel key: decrypted frame = $decryptedHex',
      );

      if (decryptedResponse.length >= 3 &&
          decryptedResponse[0] == 0x06 &&
          decryptedResponse[1] == 0x02 &&
          !DataRequestPattern.verifyTokenResponseChecksum(decryptedResponse)) {
        final expected =
            (decryptedResponse[0] + decryptedResponse[1]) & 0xFF;
        _logHandshake(
          '$decryptKeyLabel key: checksum advisory mismatch '
          '(got 0x${decryptedResponse[2].toRadixString(16).padLeft(2, '0')}, '
          'expected 0x${expected.toRadixString(16).padLeft(2, '0')}) — '
          'accepting 06 02 token anyway',
        );
      }

      final token = DataRequestPattern.parseSessionToken(decryptedResponse);
      if (_isInvalidToken(token)) {
        _logHandshake(
          '$decryptKeyLabel key: invalid or missing 06 02 token in decrypted frame',
        );
        continue;
      }

      _logHandshake(
        '$decryptKeyLabel key: token parsed successfully ($token)',
      );
      return (
        token: token,
        decryptKeyLabel: decryptKeyLabel,
        usedDefaultKey: decryptKeyLabel == 'Default',
      );
    }

    return null;
  }

  /// Requests a session token using command 06 01 with timeout and retry.
  static Future<String?> requestToken(
    String deviceId, {
    bool ignoreConnect = false,
  }) async {
    if (!ignoreConnect) {
      final connected = await BleService.connect(deviceId);
      if (!connected) {
        return null;
      }
    }

    final encryptKey = _handshakeEncryptKey(deviceId);
    const keyLabel = _handshakeKeyLabel;
    _logHandshake(
      'Starting token request for $deviceId with $keyLabel key '
      '(${encryptKey.substring(0, 8)}...)',
    );

    for (var attempt = 0; attempt < _maxHandshakeAttempts; attempt++) {
      if (attempt > 0) {
        _logHandshake(
          'Retry ${attempt + 1}/$_maxHandshakeAttempts ($keyLabel key)',
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      try {
        final response = await _readFreshTokenResponse(
          deviceId,
          encryptKey: encryptKey,
          encryptKeyLabel: keyLabel,
        );
        if (response == null || response.isEmpty) {
          continue;
        }

        final parsed = _parseTokenWithKey(response, encryptKey, keyLabel);
        if (_isValidToken(parsed?.token)) {
          cacheDeviceEncryptKey(deviceId, encryptKey);
          _deviceTokens[deviceId] = parsed!.token!;
          _logHandshake(
            'Token handshake succeeded for $deviceId — token=${parsed.token}',
          );
          return parsed.token;
        }
      } on TimeoutException {
        continue;
      } catch (error) {
        _logHandshake('Attempt failed ($keyLabel key): $error');
        continue;
      }
    }

    _logHandshake('Token request failed after $_maxHandshakeAttempts attempts');
    return null;
  }

  static Future<String> getToken(
    String deviceId, {
    bool ignoreConnect = false,
    bool forceFresh = true,
  }) async {
    if (forceFresh) {
      _resetHandshakeState(deviceId);
    }

    try {
      final token = await requestToken(
        deviceId,
        ignoreConnect: ignoreConnect,
      ).timeout(_handshakeTimeout, onTimeout: () => null);

      if (_isValidToken(token)) {
        return token!;
      }
    } on TimeoutException {
      // Fall through to invalid token handling below.
    } catch (_) {
      // Fall through to invalid token handling below.
    }

    return '';
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

    final resolvedKey = encryptKey.toLowerCase();
    final decryptedResponse = DataService.decryptNotifyBlock(
      response,
      resolvedKey,
      isValidFrame: (decrypted) =>
          decrypted.length >= 4 &&
          decrypted[0] == 2 &&
          decrypted[1] == 2 &&
          decrypted[2] == 1,
    );
    if (decryptedResponse == null) {
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
    String? debugLabel,
  }) async {
    try {
      await _writeDataInternal(
        deviceId,
        data,
        ignoreEncryption: ignoreEncryption,
        writeTimeout: writeTimeout,
        encryptKeyOverride: encryptKeyOverride,
        debugLabel: debugLabel,
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
    String? debugLabel,
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
      debugLabel: debugLabel,
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
        _logHandshake('Connect handshake failed — no valid token obtained');
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
    bool Function(List<int> decrypted)? isValidFrame,
  }) async {
    if (response.isEmpty) return null;

    final resolvedKey = (encryptKey ?? await _resolveEncryptKey(deviceId))
        .toLowerCase();
    return DataService.tryDecryptNotifyCandidates(
      response,
      [resolvedKey],
      isValidFrame: isValidFrame,
    );
  }

  static bool _isPasswordCommandAck(List<int>? decrypted) {
    if (decrypted == null || decrypted.length < 3) return false;

    // Manufacturer auth/unlock ack to 05 01 06 command: 05 02 01 RET (RET 0x00 = success).
    if (decrypted[0] == 0x05 &&
        decrypted[1] == 0x02 &&
        decrypted[2] == 0x01 &&
        decrypted.length >= 4) {
      return decrypted[3] == 0x00;
    }

    // Legacy/direct echo ack: 05 01 06 with non-error status byte.
    if (decrypted[0] == 0x05 &&
        decrypted[1] == 0x01 &&
        decrypted[2] == 0x06 &&
        decrypted.length >= 4) {
      return decrypted[3] != 0x00 && decrypted[3] != 0xFF;
    }

    return false;
  }

  static Future<bool> _isAuthFailureResponse(
    String deviceId,
    List<int> response, {
    String? encryptKey,
  }) async {
    final resolvedKey = (encryptKey ?? await _resolveEncryptKey(deviceId))
        .toLowerCase();

    for (final candidate in DataService.aesCiphertextBlockCandidates(response)) {
      final decrypted = DataService.decrypt(
        DataService.bytesListToHexString(candidate.block),
        resolvedKey,
      );
      if (decrypted == null || decrypted.length < 3) {
        continue;
      }

      if (_isPasswordCommandAck(decrypted)) {
        return false;
      }

      if (decrypted.length >= 4 && decrypted[3] == 0xFF) {
        return true;
      }

      return true;
    }

    return true;
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
      isValidFrame: _isPasswordCommandAck,
    );
    return _isPasswordCommandAck(decrypted);
  }

  static void _logLockResponse(
    String debugLabel,
    List<int> response,
    String decryptKey,
  ) {
    if (response.isEmpty) {
      _logUnlock('$debugLabel: no 36F6 notify received (timeout)');
      return;
    }

    final rawHex = DataService.bytesToHexString(response);
    _logUnlock(
      '$debugLabel: 36F6 raw response (${response.length} bytes): $rawHex',
    );

    if (DataService.isFramedSuffixNotify(response)) {
      _logUnlock(
        '$debugLabel: framed notify layout '
        '${DataService.describeFramedNotify(response)}',
      );
    }

    final sliceCandidates = DataService.aesCiphertextBlockCandidates(response);
    for (final candidate in sliceCandidates) {
      _logUnlock(
        '$debugLabel: AES candidate ${candidate.label} = '
        '${DataService.bytesListToHexString(candidate.block)}',
      );
    }

    final decrypted = DataService.tryDecryptNotifyCandidates(
      response,
      [decryptKey],
    );
    if (decrypted != null) {
      _logUnlock(
        '$debugLabel: decrypted frame = '
        '${DataService.bytesListToHexString(decrypted)}',
      );
    }
  }

  static Future<List<int>> _readPostWriteLockResponse(
    String deviceId, {
    required String payload,
    String? encryptKeyOverride,
    String? debugLabel,
    Duration timeout = _handshakeNotifyTimeout,
  }) async {
    final device = BluetoothDevice.fromId(deviceId);
    final sessionCharacteristics = await _resolveHandshakeCharacteristics(device);
    final notifyCharacteristic = sessionCharacteristics.notify;
    final writeCharacteristic = sessionCharacteristics.write;

    if (notifyCharacteristic == null || writeCharacteristic == null) {
      _logUnlock('${debugLabel ?? 'command'}: missing 36F5/36F6 characteristics');
      return <int>[];
    }

    final resolvedEncryptKey =
        encryptKeyOverride ?? await _resolveEncryptKey(deviceId);
    StreamSubscription<List<int>>? subscription;
    try {
      await notifyCharacteristic.setNotifyValue(true).timeout(_handshakeTimeout);
      await _flushStaleNotifyBuffer(notifyCharacteristic);
      final previousValue = List<int>.from(notifyCharacteristic.lastValue);

      final completer = Completer<List<int>>();
      var acceptNotifications = false;
      subscription = notifyCharacteristic.onValueReceived.listen((value) {
        if (value.isEmpty || completer.isCompleted || !acceptNotifications) {
          return;
        }
        completer.complete(List<int>.from(value));
      });

      await _writeEncryptedFrame(
        deviceId,
        payload,
        writeCharacteristic: writeCharacteristic,
        encryptKey: encryptKeyOverride,
        writeTimeout: timeout.inSeconds.clamp(1, 30),
        debugLabel: debugLabel,
      );
      acceptNotifications = true;
      _logUnlock(
        '${debugLabel ?? 'command'}: 36F6 listening for first post-write notify',
      );

      var response = await completer.future.timeout(
        timeout,
        onTimeout: () => <int>[],
      );

      if (response.isEmpty) {
        _logUnlock(
          '${debugLabel ?? 'command'}: no 36F6 notify — trying read/lastValue fallback',
        );
        try {
          response = await _awaitLockCharacteristicValue(
            notifyCharacteristic,
            previousValue,
          );
        } catch (_) {}

        if (response.isEmpty) {
          try {
            response = await _readLockCharacteristic(notifyCharacteristic);
          } catch (_) {}
        }

        if (response.isEmpty) {
          _logUnlock(
            '${debugLabel ?? 'command'}: no 36F6 notify or read response (timeout)',
          );
          return response;
        }

        _logUnlock(
          '${debugLabel ?? 'command'}: got 36F6 response via read/lastValue fallback',
        );
      }

      _logLockResponse(
        debugLabel ?? 'command',
        response,
        resolvedEncryptKey,
      );

      return response;
    } finally {
      await subscription?.cancel();
    }
  }

  static Future<List<int>> _sendLockCommandAndReadResponse(
    String deviceId,
    String payload, {
    String? encryptKeyOverride,
    String? debugLabel,
    Duration timeout = _handshakeNotifyTimeout,
  }) async {
    return _readPostWriteLockResponse(
      deviceId,
      payload: payload,
      encryptKeyOverride: encryptKeyOverride,
      debugLabel: debugLabel,
      timeout: timeout,
    );
  }

  static Future<bool> requestToUnlock(
    String deviceId, {
    bool forceFresh = false,
  }) {
    return runExclusive(() async {
      try {
        if (!forceFresh && _deviceUnlockedThisSession[deviceId] == true) {
          _logUnlock('Lock $deviceId already unlocked this session');
          return true;
        }

        return await _requestToUnlockCore(deviceId, forceFresh: forceFresh);
      } on LockAuthenticationException {
        rethrow;
      } finally {
        await _releaseOnDemandConnectionInternal(deviceId);
      }
    });
  }

  /// Strict on-demand session: credentials → disconnect → connect → 06 01 AES handshake.
  static Future<String> _prepareOnDemandUnlockSession(String deviceId) async {
    _deviceUnlockedThisSession.remove(deviceId);
    _resetHandshakeState(deviceId);

    await _loadCredentialsForUnlock(deviceId);

    await _ensureFullyDisconnected(deviceId);
    await _waitBeforeConnect();

    if (!await _connectForUnlockGatt(deviceId)) {
      throw LockAuthenticationException(
        deviceId,
        message: 'Could not establish BLE connection for unlock.',
      );
    }

    final token = await _performSessionHandshake(deviceId);
    if (token == null) {
      await _safeDisconnect(BluetoothDevice.fromId(deviceId));
      throw LockAuthenticationException(
        deviceId,
        message:
            'AES session handshake failed. The lock did not return a valid token.',
      );
    }

    _deviceTokens[deviceId] = token;
    _activeDeviceId = deviceId;
    _logUnlock('Fresh AES session token acquired for unlock ($deviceId)');
    return token;
  }

  /// Same 06 01 challenge-response used when adding a lock (AES master key → session token).
  static Future<String?> _performSessionHandshake(String deviceId) async {
    _logHandshake(
      'Performing fresh 06 01 AES challenge-response handshake for $deviceId',
    );
    await _cancelHandshakeSubscriptions(deviceId);

    final token = await requestToken(
      deviceId,
      ignoreConnect: true,
    ).timeout(_unlockConnectTimeout, onTimeout: () => null);

    if (_isValidToken(token)) {
      cacheDeviceEncryptKey(deviceId, _handshakeEncryptKey(deviceId));
      _deviceTokens[deviceId] = token!;
      return token;
    }

    return null;
  }

  /// Fast single-attempt connect + handshake for unlock/toggle flows.
  static Future<bool> connectForUnlock(String deviceId) {
    return runExclusive(() async {
      try {
        await _prepareOnDemandUnlockSession(deviceId);
        return true;
      } on LockAuthenticationException {
        rethrow;
      } catch (_) {
        return false;
      }
    });
  }

  static Future<bool> _connectForUnlockGatt(String deviceId) async {
    _logUnlock('Connecting for unlock: $deviceId (${_unlockConnectTimeout.inSeconds}s timeout)');
    final device = BluetoothDevice.fromId(deviceId);

    try {
      await _stopScanBeforeConnect();

      await device
          .connect(
            timeout: _unlockConnectTimeout,
            license: License.free,
            autoConnect: false,
          )
          .timeout(_unlockConnectTimeout);

      if (!device.isConnected) {
        _logUnlock('Connect for unlock failed: device not connected');
        return false;
      }

      await device.discoverServices().timeout(_unlockConnectTimeout);

      _logUnlock('GATT link ready for unlock handshake ($deviceId)');
      return true;
    } on TimeoutException catch (error) {
      _logUnlock('Connect for unlock timed out for $deviceId: $error');
      await _abortPendingConnect(device);
      await _handleConnectFailure(deviceId);
      return false;
    } catch (error) {
      _logUnlock('Connect for unlock failed for $deviceId: $error');
      await _handleConnectFailure(deviceId);
      return false;
    }
  }

  static Future<bool> _requestToUnlockCore(
    String deviceId, {
    bool forceFresh = false,
    String? sessionToken,
    Duration responseTimeout = _unlockWriteTimeout,
  }) async {
    if (forceFresh) {
      _logUnlock('Sending fresh 05 01 06 unlock for $deviceId (manual unlock)');
    }

    final encryptKey = _handshakeEncryptKey(deviceId);
    cacheDeviceEncryptKey(deviceId, encryptKey);

    final String token;
    if (sessionToken != null && _isValidToken(sessionToken)) {
      token = sessionToken;
    } else if (forceFresh) {
      token = await BleService.getToken(
        deviceId,
        ignoreConnect: true,
        forceFresh: true,
      );
    } else {
      token = _deviceTokens[deviceId] ??
          await BleService.getToken(deviceId, ignoreConnect: true);
    }

    if (_isInvalidToken(token)) {
      throw LockAuthenticationException(
        deviceId,
        message: 'Invalid session token for unlock.',
      );
    }

    final unlockFrame = DataRequestPattern.getUnlockHex(token);
    _logUnlock(
      'Unlocking $deviceId — ${DataRequestPattern.describeUnlockFrame(token)}',
    );
    final response = await _sendLockCommandAndReadResponse(
      deviceId,
      unlockFrame,
      encryptKeyOverride: encryptKey,
      debugLabel: 'unlock',
      timeout: responseTimeout,
    );

    if (await _isAuthFailureResponse(
          deviceId,
          response,
          encryptKey: encryptKey,
        ) ||
        !await _isUnlockAck(
          deviceId,
          response,
          encryptKey: encryptKey,
        )) {
      throw LockAuthenticationException(deviceId);
    }

    _logUnlock('Unlock succeeded for $deviceId (ack frame 05 02 01 00)');
    _deviceUnlockedThisSession[deviceId] = true;
    return true;
  }

  static Future<bool> connectAndUnLock(String deviceId) {
    return runExclusive(() async {
      try {
        final sessionToken = await _prepareOnDemandUnlockSession(deviceId);

        return await _requestToUnlockCore(
          deviceId,
          forceFresh: true,
          sessionToken: sessionToken,
          responseTimeout: _unlockWriteTimeout,
        );
      } on LockAuthenticationException {
        rethrow;
      } on PairingRequiredException {
        rethrow;
      } on TimeoutException catch (error) {
        _logUnlock('Unlock timed out for $deviceId: $error');
        throw LockAuthenticationException(
          deviceId,
          message: 'Unlock timed out. Move closer to the lock and try again.',
        );
      } catch (error) {
        _logUnlock('Unlock failed for $deviceId: $error');
        throw LockAuthenticationException(
          deviceId,
          message: 'Unlock failed: $error',
        );
      } finally {
        await _explicitlyCloseGattConnection(deviceId);
      }
    });
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
    var connectedHere = false;

    try {
      if (!ignoreConnect) {
        connectedHere = await BleService.connect(deviceId);
        if (!connectedHere) {
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
    } finally {
      if (connectedHere) {
        await _releaseOnDemandConnectionInternal(deviceId);
      }
    }
  }
}
