import 'dart:io';

import 'package:fitness_snack_lock/services/data_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores paired lock identifiers securely on Android (EncryptedSharedPreferences)
/// and iOS (Keychain). Falls back to SharedPreferences on other platforms.
class PairedLockStorage {
  static const _channel =
      MethodChannel('com.singh.fitnessssnacklock/paired_locks');
  static const _fallbackKey = 'paired_lock_ids_fallback';
  static const _fallbackMigratedKey = 'paired_lock_ids_migrated';
  static const _fallbackSecretKeyPrefix = 'lock_secret_';
  static const _fallbackPasswordPrefix = 'lock_password_';
  static var _fallbackMigrationChecked = false;

  static Future<void> _ensureFallbackMigrated() async {
    if (!_useNativeSecureStorage || _fallbackMigrationChecked) {
      return;
    }
    _fallbackMigrationChecked = true;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_fallbackMigratedKey) ?? false) {
      return;
    }

    final fallbackIds = prefs.getStringList(_fallbackKey) ?? const [];
    for (final deviceId in fallbackIds) {
      if (deviceId.isEmpty) continue;
      try {
        await _channel.invokeMethod<void>('pair', {'deviceId': deviceId});
      } on PlatformException {
        // Ignore individual migration failures and continue.
      }
    }

    await prefs.remove(_fallbackKey);
    await prefs.setBool(_fallbackMigratedKey, true);
  }

  static Future<bool> isPaired(String deviceId) async {
    if (deviceId.isEmpty) return false;

    if (_useNativeSecureStorage) {
      await _ensureFallbackMigrated();
      try {
        final paired = await _channel.invokeMethod<bool>(
          'isPaired',
          {'deviceId': deviceId},
        );
        return paired ?? false;
      } on PlatformException {
        return false;
      }
    }

    final ids = await _loadFallbackIds();
    return ids.contains(deviceId);
  }

  static Future<Set<String>> getPairedIds() async {
    if (_useNativeSecureStorage) {
      await _ensureFallbackMigrated();
      try {
        final ids = await _channel.invokeMethod<List<dynamic>>('getPairedIds');
        return ids?.map((id) => id.toString()).toSet() ?? {};
      } on PlatformException {
        return {};
      }
    }

    return _loadFallbackIds();
  }

  static Future<void> pair(String deviceId) async {
    if (deviceId.isEmpty) return;

    if (_useNativeSecureStorage) {
      await _channel.invokeMethod<void>('pair', {'deviceId': deviceId});
      await ensureSecretKey(deviceId);
      return;
    }

    final ids = await _loadFallbackIds();
    ids.add(deviceId);
    await _saveFallbackIds(ids);
    await ensureSecretKey(deviceId);
  }

  static Future<void> unpair(String deviceId) async {
    if (deviceId.isEmpty) return;

    if (_useNativeSecureStorage) {
      await _channel.invokeMethod<void>('unpair', {'deviceId': deviceId});
      return;
    }

    final ids = await _loadFallbackIds();
    ids.remove(deviceId);
    await _saveFallbackIds(ids);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_fallbackSecretKeyPrefix$deviceId');
    await prefs.remove('$_fallbackPasswordPrefix$deviceId');
  }

  /// Reads the per-lock AES-128 master key from secure storage (Keychain / EncryptedSharedPreferences).
  static Future<String?> getSecretKey(String deviceId) async {
    if (deviceId.isEmpty) return null;

    if (_useNativeSecureStorage) {
      try {
        final key = await _channel.invokeMethod<String>(
          'getSecretKey',
          {'deviceId': deviceId},
        );
        return key?.trim();
      } on PlatformException {
        return null;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_fallbackSecretKeyPrefix$deviceId');
  }

  static Future<void> saveSecretKey(String deviceId, String secretKey) async {
    if (deviceId.isEmpty || secretKey.isEmpty) return;

    if (_useNativeSecureStorage) {
      await _channel.invokeMethod<void>('saveSecretKey', {
        'deviceId': deviceId,
        'secretKey': secretKey,
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_fallbackSecretKeyPrefix$deviceId', secretKey);
  }

  static Future<bool> hasSecretKey(String deviceId) async {
    final key = await getSecretKey(deviceId);
    return key != null && key.isNotEmpty;
  }

  /// Normalizes AES-128 key hex read from Keychain / secure storage.
  static String sanitizeAesKeyHex(String key) {
    return key.replaceAll(RegExp(r'[\s\r\n:]'), '').toLowerCase();
  }

  static bool isValidAesKeyHex(String key) {
    final normalized = sanitizeAesKeyHex(key);
    return RegExp(r'^[0-9a-f]{32}$').hasMatch(normalized);
  }

  static bool isFactoryAesKey(String key) {
    return sanitizeAesKeyHex(key) ==
        DataRequestPattern.defaultEncryptKey.toLowerCase();
  }

  /// True when a non-factory AES-128 key is stored for [deviceId].
  static Future<bool> hasCustomAesKey(String deviceId) async {
    final key = await getSecretKey(deviceId);
    if (key == null || key.isEmpty) return false;
    final normalized = sanitizeAesKeyHex(key);
    return isValidAesKeyHex(normalized) && !isFactoryAesKey(normalized);
  }

  /// Returns the stored AES master key, or the factory default when missing.
  /// Does not persist the factory key — custom keys are saved only after
  /// confirmed hardware rotation (`07 03 01 00`).
  static Future<String> ensureSecretKey(String deviceId) async {
    final existing = await getSecretKey(deviceId);
    if (existing != null && existing.isNotEmpty) {
      final normalized = sanitizeAesKeyHex(existing);
      if (isValidAesKeyHex(normalized)) {
        if (normalized != existing) {
          await saveSecretKey(deviceId, normalized);
        }
        return normalized;
      }
    }

    return DataRequestPattern.defaultEncryptKey.toLowerCase();
  }

  static String sanitizePasswordHex(String password) {
    return password.replaceAll(RegExp(r'[\s\r\n:]'), '').toLowerCase();
  }

  static bool isValidPasswordHex(String password) {
    return RegExp(r'^[0-9a-f]{12}$').hasMatch(sanitizePasswordHex(password));
  }

  static bool isFactoryPassword(String password) {
    return sanitizePasswordHex(password) ==
        DataRequestPattern.defaultPasswordHex.toLowerCase();
  }

  static Future<String?> getPassword(String deviceId) async {
    if (deviceId.isEmpty) return null;

    if (_useNativeSecureStorage) {
      try {
        final password = await _channel.invokeMethod<String>(
          'getPassword',
          {'deviceId': deviceId},
        );
        return password?.trim();
      } on PlatformException {
        return null;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_fallbackPasswordPrefix$deviceId');
  }

  static Future<void> savePassword(String deviceId, String passwordHex) async {
    if (deviceId.isEmpty || passwordHex.isEmpty) return;
    final normalized = sanitizePasswordHex(passwordHex);
    if (!isValidPasswordHex(normalized)) return;

    if (_useNativeSecureStorage) {
      await _channel.invokeMethod<void>('savePassword', {
        'deviceId': deviceId,
        'password': normalized,
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_fallbackPasswordPrefix$deviceId', normalized);
  }

  static Future<bool> hasCustomPassword(String deviceId) async {
    final password = await getPassword(deviceId);
    if (password == null || password.isEmpty) return false;
    final normalized = sanitizePasswordHex(password);
    return isValidPasswordHex(normalized) && !isFactoryPassword(normalized);
  }

  /// Returns the stored 6-byte password hex, or the factory default when missing.
  static Future<String> ensurePassword(String deviceId) async {
    final existing = await getPassword(deviceId);
    if (existing != null && existing.isNotEmpty) {
      final normalized = sanitizePasswordHex(existing);
      if (isValidPasswordHex(normalized)) {
        if (normalized != existing) {
          await savePassword(deviceId, normalized);
        }
        return normalized;
      }
    }

    return DataRequestPattern.defaultPasswordHex.toLowerCase();
  }

  /// Pushes the lock MAC and secret key to the paired watch app (Wear OS / watchOS).
  /// Failures are logged only — callers must not be blocked by watch sync issues.
  static Future<void> syncLockToWatch(String deviceId) async {
    if (deviceId.isEmpty || !_useNativeSecureStorage) return;

      try {
        final secretKey = await getSecretKey(deviceId);
        final password = await getPassword(deviceId);
        await _channel.invokeMethod<void>(
          'syncLockToWatch',
          {
            'deviceId': deviceId,
            if (secretKey != null && secretKey.isNotEmpty) 'secretKey': secretKey,
            if (password != null && password.isNotEmpty) 'password': password,
          },
        );
    } on MissingPluginException catch (error) {
      debugPrint('syncLockToWatch unavailable (no native handler): $error');
    } on PlatformException catch (error) {
      debugPrint(
        'syncLockToWatch failed (${error.code}): ${error.message ?? error}',
      );
    } catch (error) {
      debugPrint('syncLockToWatch failed: $error');
    }
  }

  static bool get _useNativeSecureStorage =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<Set<String>> _loadFallbackIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_fallbackKey)?.toSet() ?? {};
  }

  static Future<void> _saveFallbackIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_fallbackKey, ids.toList());
  }
}
