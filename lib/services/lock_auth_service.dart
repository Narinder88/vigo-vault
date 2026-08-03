import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/lock_secret_storage.dart';
import 'package:fitness_snack_lock/services/paired_lock_storage.dart';

class LockAuthService {
  /// Generates an ownership secret, provisions it to firmware, and pairs locally.
  static Future<void> claimAndProvisionLock({
    required String deviceId,
    required String sessionToken,
  }) async {
    final secretKey = LockSecretStorage.generateSecretKey();
    await BleService.provisionSecretKey(
      deviceId: deviceId,
      secretKey: secretKey,
      token: sessionToken,
    );
    await LockSecretStorage.saveSecretKey(deviceId, secretKey);
    BleService.cacheDeviceEncryptKey(deviceId, secretKey);
    await PairedLockStorage.pair(deviceId);
  }
}
