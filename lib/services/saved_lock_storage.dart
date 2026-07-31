import 'dart:convert';

import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedLockStorage {
  static const _locksKey = 'smart_lock_saved_locks';
  static const _activeLockIdKey = 'smart_lock_active_lock_id';
  static const _primaryLockIdKey = 'smart_lock_primary_lock_id';
  static const _legacyLastDeviceIdKey = 'smart_lock_last_device_id';
  static const _legacyCustomNameKey = 'smart_lock_custom_device_name';

  static Future<List<SavedLock>> loadLocks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_locksKey);

    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((entry) => SavedLock.fromJson(entry as Map<String, dynamic>))
          .toList();
    }

    return _migrateLegacyLock(prefs);
  }

  static Future<List<SavedLock>> _migrateLegacyLock(
    SharedPreferences prefs,
  ) async {
    final legacyId = prefs.getString(_legacyLastDeviceIdKey);
    if (legacyId == null || legacyId.isEmpty) return [];

    final legacyName = prefs.getString(_legacyCustomNameKey);
    final lock = SavedLock(
      id: legacyId,
      displayName: (legacyName != null && legacyName.isNotEmpty)
          ? legacyName
          : 'Main Lock',
      lastConnectedAt: DateTime.now(),
    );

    await saveLocks([lock]);
    await prefs.remove(_legacyLastDeviceIdKey);
    return [lock];
  }

  static Future<void> saveLocks(List<SavedLock> locks) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(locks.map((lock) => lock.toJson()).toList());
    await prefs.setString(_locksKey, encoded);
  }

  static Future<void> upsertLock(SavedLock lock) async {
    final locks = await loadLocks();
    final index = locks.indexWhere((entry) => entry.id == lock.id);

    if (index >= 0) {
      locks[index] = lock;
    } else {
      locks.add(lock);
    }

    await saveLocks(locks);
  }

  static Future<void> removeLock(String lockId) async {
    final locks = await loadLocks();
    locks.removeWhere((entry) => entry.id == lockId);
    await saveLocks(locks);

    final activeId = await getActiveLockId();
    if (activeId == lockId) {
      await setActiveLockId(null);
    }

    final primaryId = await getPrimaryLockId();
    if (primaryId == lockId) {
      final nextPrimary = locks.isNotEmpty ? locks.first.id : null;
      await setPrimaryLockId(nextPrimary);
    }
  }

  static Future<String?> getPrimaryLockId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_primaryLockIdKey);
  }

  static Future<void> setPrimaryLockId(String? lockId) async {
    final prefs = await SharedPreferences.getInstance();
    if (lockId == null || lockId.isEmpty) {
      await prefs.remove(_primaryLockIdKey);
      return;
    }
    await prefs.setString(_primaryLockIdKey, lockId);
  }

  static Future<String?> getActiveLockId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeLockIdKey);
  }

  static Future<void> setActiveLockId(String? lockId) async {
    final prefs = await SharedPreferences.getInstance();
    if (lockId == null || lockId.isEmpty) {
      await prefs.remove(_activeLockIdKey);
      return;
    }
    await prefs.setString(_activeLockIdKey, lockId);
  }

  /// Legacy helpers kept for gradual migration.
  static Future<void> saveLastDeviceId(String deviceId) async {
    await setActiveLockId(deviceId);
  }

  static Future<String?> getLastDeviceId() async {
    return getActiveLockId();
  }

  static Future<void> clearLastDeviceId() async {
    await setActiveLockId(null);
  }
}
