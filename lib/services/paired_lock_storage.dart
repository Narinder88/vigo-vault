import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores paired lock identifiers securely on Android via EncryptedSharedPreferences.
/// Falls back to SharedPreferences on other platforms.
class PairedLockStorage {
  static const _channel =
      MethodChannel('com.singh.fitnessssnacklock/paired_locks');
  static const _fallbackKey = 'paired_lock_ids_fallback';

  static Future<bool> isPaired(String deviceId) async {
    if (deviceId.isEmpty) return false;

    if (_useNativeSecureStorage) {
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
      return;
    }

    final ids = await _loadFallbackIds();
    ids.add(deviceId);
    await _saveFallbackIds(ids);
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
  }

  static bool get _useNativeSecureStorage =>
      !kIsWeb && Platform.isAndroid;

  static Future<Set<String>> _loadFallbackIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_fallbackKey)?.toSet() ?? {};
  }

  static Future<void> _saveFallbackIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_fallbackKey, ids.toList());
  }
}
