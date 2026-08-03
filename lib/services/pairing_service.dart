import 'package:fitness_snack_lock/services/paired_lock_storage.dart';

class PairingRequiredException implements Exception {
  PairingRequiredException(this.deviceId);

  final String deviceId;

  @override
  String toString() =>
      'Lock $deviceId is not paired on this device. Claim the lock before unlocking.';
}

class PairingService {
  static Future<bool> isPaired(String deviceId) {
    return PairedLockStorage.isPaired(deviceId);
  }

  static Future<void> claimLock(String deviceId) async {
    await PairedLockStorage.pair(deviceId);
  }

  static Future<void> unpairLock(String deviceId) async {
    await PairedLockStorage.unpair(deviceId);
  }

  /// Ensures a lock is paired before any unlock command is sent.
  static Future<void> ensurePairedForUnlock(String deviceId) async {
    if (!await isPaired(deviceId)) {
      throw PairingRequiredException(deviceId);
    }
  }

  /// Migrates previously saved locks so existing users stay paired after upgrade.
  static Future<void> migrateExistingLocks(Iterable<String> deviceIds) async {
    for (final deviceId in deviceIds) {
      if (!await isPaired(deviceId)) {
        await claimLock(deviceId);
      }
    }
  }
}
