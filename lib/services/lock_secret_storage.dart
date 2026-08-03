import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores per-lock ownership secret keys in native secure storage.
class LockSecretStorage {
  static const _channel =
      MethodChannel('com.singh.fitnessssnacklock/paired_locks');
  static const _fallbackPrefix = 'lock_secret_key_';

  static const secretKeyHexLength = 32;

  static String generateSecretKey() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<String?> getSecretKey(String deviceId) async {
    if (deviceId.isEmpty) return null;

    if (_useNativeSecureStorage) {
      try {
        final secretKey = await _channel.invokeMethod<String>(
          'getSecretKey',
          {'deviceId': deviceId},
        );
        if (secretKey == null || secretKey.isEmpty) return null;
        return secretKey.toLowerCase();
      } on PlatformException {
        return null;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_fallbackPrefix$deviceId');
  }

  static Future<bool> hasSecretKey(String deviceId) async {
    if (deviceId.isEmpty) return false;

    if (_useNativeSecureStorage) {
      try {
        final hasKey = await _channel.invokeMethod<bool>(
          'hasSecretKey',
          {'deviceId': deviceId},
        );
        return hasKey ?? false;
      } on PlatformException {
        return false;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_fallbackPrefix$deviceId');
  }

  static Future<void> saveSecretKey(String deviceId, String secretKey) async {
    if (deviceId.isEmpty || secretKey.isEmpty) return;

    final normalized = secretKey.toLowerCase();
    if (normalized.length != secretKeyHexLength) {
      throw ArgumentError(
        'Secret key must be $secretKeyHexLength hex characters (16 bytes).',
      );
    }

    if (_useNativeSecureStorage) {
      await _channel.invokeMethod<void>('saveSecretKey', {
        'deviceId': deviceId,
        'secretKey': normalized,
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_fallbackPrefix$deviceId', normalized);
  }

  static Future<void> removeSecretKey(String deviceId) async {
    if (deviceId.isEmpty) return;

    if (_useNativeSecureStorage) {
      await _channel.invokeMethod<void>('removeSecretKey', {
        'deviceId': deviceId,
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_fallbackPrefix$deviceId');
  }

  static bool get _useNativeSecureStorage =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}
