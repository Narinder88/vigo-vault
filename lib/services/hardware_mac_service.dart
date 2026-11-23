import 'dart:async';
import 'dart:io' show Platform;

import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:fitness_snack_lock/services/paired_lock_storage.dart';
import 'package:fitness_snack_lock/services/saved_lock_storage.dart';
import 'package:fitness_snack_lock/utils/lock_mac.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Maps a CoreBluetooth peripheral UUID to the lock's 6-byte hardware MAC.
class HardwareMacService {
  HardwareMacService._();

  static final Map<String, String> _macByRemoteId = {};
  static const Duration _scanTimeout = Duration(seconds: 6);

  static bool get _isIos => !kIsWeb && Platform.isIOS;

  static void remember(ScanResult result) {
    final mac = macFromAdvertisement(result.advertisementData);
    if (mac == null) return;
    _macByRemoteId[result.device.remoteId.str] = mac;
  }

  static String? macFromAdvertisement(AdvertisementData advertisement) {
    for (final payload in advertisement.msd) {
      final mac = LockMac.macFromBytes(payload);
      if (mac != null) return mac;
    }
    for (final payload in advertisement.serviceData.values) {
      final mac = LockMac.macFromBytes(payload);
      if (mac != null) return mac;
    }
    for (final payload in advertisement.manufacturerData.values) {
      final mac = LockMac.macFromBytes(payload);
      if (mac != null) return mac;
    }
    return null;
  }

  static String? cachedMacForRemoteId(String remoteId) {
    final cached = _macByRemoteId[remoteId];
    if (cached != null) return cached;
    for (final result in FlutterBluePlus.lastScanResults) {
      if (result.device.remoteId.str != remoteId) continue;
      final mac = macFromAdvertisement(result.advertisementData);
      if (mac != null) {
        _macByRemoteId[remoteId] = mac;
        return mac;
      }
    }
    return null;
  }

  static String? cachedRemoteIdForMac(String hardwareMac) {
    final mac = LockMac.normalize(hardwareMac);
    for (final entry in _macByRemoteId.entries) {
      if (entry.value == mac) return entry.key;
    }
    for (final result in FlutterBluePlus.lastScanResults) {
      final seen = macFromAdvertisement(result.advertisementData);
      if (seen == mac) {
        final remoteId = result.device.remoteId.str;
        _macByRemoteId[remoteId] = mac;
        return remoteId;
      }
    }
    return null;
  }

  /// Scans until an advertisement contains [hardwareMac]. Returns the
  /// CoreBluetooth peripheral UUID on iOS, or the MAC itself on Android.
  static Future<String?> findPeripheralUuid(String hardwareMac) async {
    final mac = LockMac.normalize(hardwareMac);
    if (!LockMac.isMac(mac)) return null;
    if (!_isIos) return mac;

    final cached = cachedRemoteIdForMac(mac);
    if (cached != null && !LockMac.isMac(cached)) return cached;

    String? found;
    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        remember(result);
        final seen = macFromAdvertisement(result.advertisementData);
        if (seen == mac) found = result.device.remoteId.str;
      }
    });

    try {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await FlutterBluePlus.startScan(timeout: _scanTimeout);
      await FlutterBluePlus.isScanning
          .where((scanning) => scanning == false)
          .first
          .timeout(_scanTimeout + const Duration(seconds: 1));
    } catch (_) {
    } finally {
      await subscription.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }

    found ??= cachedRemoteIdForMac(mac);
    final resolved = found;
    if (resolved == null || LockMac.isMac(resolved)) return null;
    return resolved;
  }

  /// Reads a connected peripheral for a device-info value that contains the MAC.
  static Future<String?> readFromConnectedDevice(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices().timeout(
            const Duration(seconds: 4),
          );
      for (final service in services) {
        final serviceUuid = service.uuid.str.toLowerCase();
        final isDeviceInfo = serviceUuid.contains('180a');
        for (final characteristic in service.characteristics) {
          final characteristicUuid = characteristic.uuid.str.toLowerCase();
          final isIdentityValue = characteristicUuid.contains('2a23') ||
              characteristicUuid.contains('2a25') ||
              characteristicUuid.contains('2a24') ||
              characteristicUuid.contains('2a29');
          if (!isDeviceInfo && !isIdentityValue) continue;
          if (!characteristic.properties.read) continue;
          try {
            final value = await characteristic.read().timeout(
                  const Duration(seconds: 2),
                );
            final mac = LockMac.macFromBytes(value);
            if (mac != null) return mac;
            final ascii = String.fromCharCodes(
              value.where((byte) => byte >= 32 && byte < 127),
            );
            if (LockMac.isMac(ascii)) return LockMac.normalize(ascii);
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  /// Resolves the hardware MAC for a saved lock, persisting it and aliasing
  /// the AES key and password under both the peripheral id and the MAC.
  static Future<SavedLock?> persistForLock(SavedLock lock) async {
    final peripheralId = (lock.peripheralUuid != null &&
            lock.peripheralUuid!.isNotEmpty)
        ? lock.peripheralUuid!
        : lock.id;

    var mac = lock.hardwareMac == null
        ? null
        : LockMac.normalize(lock.hardwareMac!);
    if (mac != null && !LockMac.isMac(mac)) mac = null;
    if (mac == null && LockMac.isMac(lock.id)) {
      mac = LockMac.normalize(lock.id);
    }
    mac ??= cachedMacForRemoteId(peripheralId);

    if (mac == null && !LockMac.isMac(peripheralId)) {
      mac = await _scanRemoteId(peripheralId);
    }

    if (mac == null && !LockMac.isMac(peripheralId)) {
      mac = await _readByQuickConnect(peripheralId);
    }

    if (mac == null || !LockMac.isMac(mac)) return null;

    final peripheralUuid = LockMac.isMac(peripheralId) ? null : peripheralId;
    await PairedLockStorage.aliasCredentials(
      peripheralId: peripheralId,
      hardwareMac: mac,
    );

    final updated = lock.copyWith(
      hardwareMac: mac,
      peripheralUuid: peripheralUuid ?? lock.peripheralUuid,
    );
    if (updated.hardwareMac != lock.hardwareMac ||
        updated.peripheralUuid != lock.peripheralUuid) {
      await SavedLockStorage.upsertLock(updated);
    }
    return updated;
  }

  static Future<String?> _scanRemoteId(String remoteId) async {
    final cached = cachedMacForRemoteId(remoteId);
    if (cached != null) return cached;

    String? found;
    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        remember(result);
        if (result.device.remoteId.str == remoteId) {
          found = macFromAdvertisement(result.advertisementData);
        }
      }
    });

    try {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await FlutterBluePlus.startScan(timeout: _scanTimeout);
      await FlutterBluePlus.isScanning
          .where((scanning) => scanning == false)
          .first
          .timeout(_scanTimeout + const Duration(seconds: 1));
    } catch (_) {
    } finally {
      await subscription.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    return found ?? cachedMacForRemoteId(remoteId);
  }

  static Future<String?> _readByQuickConnect(String remoteId) async {
    final device = BluetoothDevice.fromId(remoteId);
    var openedHere = false;
    try {
      if (!device.isConnected) {
        await device
            .connect(
              timeout: const Duration(seconds: 6),
              license: License.nonprofit,
              autoConnect: false,
            )
            .timeout(const Duration(seconds: 6));
        openedHere = device.isConnected;
      }
      if (!device.isConnected) return null;
      final mac = await readFromConnectedDevice(device);
      if (mac != null) _macByRemoteId[remoteId] = mac;
      return mac;
    } catch (_) {
      return null;
    } finally {
      if (openedHere) {
        try {
          await device.disconnect(queue: false);
        } catch (_) {}
      }
    }
  }
}
