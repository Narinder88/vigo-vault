import 'package:fitness_snack_lock/services/paired_lock_storage.dart';

class PairingRequiredException implements Exception {
  PairingRequiredException(this.deviceId);

  final String deviceId;

  @override
  String toString() =>
      'Lock $deviceId is not saved on this device. Connect to the lock first.';
}

class LockAuthenticationException implements Exception {
  LockAuthenticationException(this.deviceId, {this.message});

  final String deviceId;
  final String? message;

  @override
  String toString() =>
      message ??
      'Authentication failed for lock $deviceId. Check that you are near the lock and try again.';
}

class PairingService {
  /// True when the lock is registered locally on this device.
  static Future<bool> isPaired(String deviceId) async {
    if (deviceId.isEmpty) return false;
    return PairedLockStorage.isPaired(deviceId);
  }

  static Future<bool> isRegisteredLocally(String deviceId) {
    return PairedLockStorage.isPaired(deviceId);
  }

  static Future<void> registerLock(String deviceId) async {
    await PairedLockStorage.pair(deviceId);
  }

  static Future<void> unpairLock(String deviceId) async {
    await PairedLockStorage.unpair(deviceId);
  }

  /// Ensures a lock is saved locally before unlock from saved-lock UI.
  static Future<void> ensurePairedForUnlock(String deviceId) async {
    if (!await isPaired(deviceId)) {
      throw PairingRequiredException(deviceId);
    }
  }

  /// Keeps paired-lock storage aligned with saved locks after app upgrades.
  static Future<void> migrateExistingLocks(Iterable<String> deviceIds) async {
    for (final deviceId in deviceIds) {
      if (!await PairedLockStorage.isPaired(deviceId)) {
        await PairedLockStorage.pair(deviceId);
      } else {
        await PairedLockStorage.ensureSecretKey(deviceId);
      }
    }
  }
}
