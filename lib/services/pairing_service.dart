import 'package:fitness_snack_lock/services/lock_secret_storage.dart';
import 'package:fitness_snack_lock/services/paired_lock_storage.dart';

class PairingRequiredException implements Exception {
  PairingRequiredException(this.deviceId);

  final String deviceId;

  @override
  String toString() =>
      'Lock $deviceId is not paired on this device. Claim the lock before unlocking.';
}

class LockAuthenticationException implements Exception {
  LockAuthenticationException(this.deviceId, {this.message});

  final String deviceId;
  final String? message;

  @override
  String toString() =>
      message ??
      'Authentication failed for lock $deviceId. The secret key was rejected.';
}

class PairingService {
  /// True only when an ownership secret exists in secure storage for [deviceId].
  static Future<bool> isPaired(String deviceId) async {
    if (deviceId.isEmpty) return false;
    return LockSecretStorage.hasSecretKey(deviceId);
  }

  static Future<bool> isRegisteredLocally(String deviceId) {
    return PairedLockStorage.isPaired(deviceId);
  }

  static Future<bool> hasOwnershipSecret(String deviceId) {
    return isPaired(deviceId);
  }

  static Future<String?> getOwnershipSecret(String deviceId) {
    return LockSecretStorage.getSecretKey(deviceId);
  }

  static Future<void> saveOwnershipSecret(
    String deviceId,
    String secretKey,
  ) async {
    await LockSecretStorage.saveSecretKey(deviceId, secretKey);
  }

  static Future<void> claimLock(String deviceId) async {
    await PairedLockStorage.pair(deviceId);
  }

  static Future<void> unpairLock(String deviceId) async {
    await LockSecretStorage.removeSecretKey(deviceId);
    await PairedLockStorage.unpair(deviceId);
  }

  /// Ensures a lock is paired and has a stored ownership secret before unlock.
  static Future<void> ensurePairedForUnlock(String deviceId) async {
    if (!await isPaired(deviceId)) {
      throw PairingRequiredException(deviceId);
    }
  }

  /// Keeps secure storage aligned with saved locks after app upgrades.
  static Future<void> migrateExistingLocks(Iterable<String> deviceIds) async {
    for (final deviceId in deviceIds) {
      if (await LockSecretStorage.hasSecretKey(deviceId)) {
        if (!await PairedLockStorage.isPaired(deviceId)) {
          await PairedLockStorage.pair(deviceId);
        }
        continue;
      }

      if (await PairedLockStorage.isPaired(deviceId)) {
        await PairedLockStorage.unpair(deviceId);
      }
    }
  }
}
