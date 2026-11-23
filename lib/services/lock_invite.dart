import 'dart:convert';
import 'dart:io' show Platform;

import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:fitness_snack_lock/services/paired_lock_storage.dart';
import 'package:fitness_snack_lock/utils/lock_mac.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LockInvite {
  const LockInvite({
    required this.name,
    required this.macAddress,
    required this.aesKey,
    required this.password,
  });

  final String name;
  final String macAddress;
  final String aesKey;
  final String password;

  static const int version = 1;

  /// UTF-8 JSON `{ v, name, mac, aesKey, password }` encoded as Base64.
  ///
  /// [macAddress] is the Android hardware MAC, or empty when the phone that
  /// created the invite only has a CoreBluetooth UUID. The manufacturer-data
  /// placeholder [LockMac.placeholderMac] is never written here.
  static Future<({String code, SavedLock lock})?> encode(SavedLock lock) async {
    final credentialId = lock.id.trim();
    if (credentialId.isEmpty) return null;

    final aesKey = PairedLockStorage.sanitizeAesKeyHex(
      await PairedLockStorage.ensureSecretKey(credentialId),
    );
    final password = PairedLockStorage.sanitizePasswordHex(
      await PairedLockStorage.ensurePassword(credentialId),
    );
    if (!PairedLockStorage.isValidAesKeyHex(aesKey) ||
        !PairedLockStorage.isValidPasswordHex(password)) {
      return null;
    }

    final name = _advertisedName(lock);
    if (name.isEmpty) return null;

    final mac = _exportMac(lock);
    final payload = jsonEncode({
      'v': version,
      'name': name,
      'mac': mac,
      'macAddress': mac,
      'aesKey': aesKey,
      'password': password,
    });
    return (
      code: base64Encode(utf8.encode(payload)),
      lock: lock,
    );
  }

  /// Advertised BLE name (for example `BR38`), not a user-chosen label.
  static String _advertisedName(SavedLock lock) {
    final hardware = lock.hardwareName?.trim() ?? '';
    if (hardware.isNotEmpty && hardware != 'Smart Lock') return hardware;
    return lock.displayName.trim();
  }

  /// Android shares its real remoteId MAC. iOS has no hardware MAC to export.
  static String _exportMac(SavedLock lock) {
    if (kIsWeb || !Platform.isAndroid) return '';
    final id = LockMac.normalize(lock.id);
    if (!LockMac.isHardwareMac(id)) return '';
    return id;
  }

  static LockInviteParseResult parse(String raw) {
    final compact = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) {
      return const LockInviteParseResult.failure(
        'Paste the invite code or scan the QR code.',
      );
    }

    Map<String, dynamic> json;
    try {
      final decoded = utf8.decode(base64Decode(_padBase64(compact)));
      final parsed = jsonDecode(decoded);
      if (parsed is! Map) {
        return const LockInviteParseResult.failure(
          'That invite code could not be read.',
        );
      }
      json = Map<String, dynamic>.from(parsed);
    } catch (_) {
      return const LockInviteParseResult.failure(
        'That invite code could not be read.',
      );
    }

    if (json['v'] != version) {
      return const LockInviteParseResult.failure(
        'This invite was made by a newer app version.',
      );
    }

    final name = json['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      return const LockInviteParseResult.failure(
        'The invite is missing a lock name.',
      );
    }

    final rawMac = json['mac']?.toString() ?? json['macAddress']?.toString() ?? '';
    final normalizedMac = LockMac.normalize(rawMac);
    final macAddress = LockMac.isHardwareMac(normalizedMac) ? normalizedMac : '';

    final aesKey = PairedLockStorage.sanitizeAesKeyHex(
      json['aesKey']?.toString() ?? '',
    );
    if (!PairedLockStorage.isValidAesKeyHex(aesKey)) {
      return const LockInviteParseResult.failure(
        'The invite AES key must be 32 hex characters.',
      );
    }

    final password = PairedLockStorage.sanitizePasswordHex(
      json['password']?.toString() ?? '',
    );
    if (!PairedLockStorage.isValidPasswordHex(password)) {
      return const LockInviteParseResult.failure(
        'The invite password must be 6 bytes (12 hex characters).',
      );
    }

    return LockInviteParseResult.success(
      LockInvite(
        name: name,
        macAddress: macAddress,
        aesKey: aesKey,
        password: password,
      ),
    );
  }

  static String _padBase64(String value) {
    final remainder = value.length % 4;
    if (remainder == 0) return value;
    return value.padRight(value.length + (4 - remainder), '=');
  }
}

class SharedLockNotFound implements Exception {
  const SharedLockNotFound(this.message);

  final String message;

  @override
  String toString() => message;
}

class LockInviteParseResult {
  const LockInviteParseResult.success(LockInvite this.invite) : error = null;

  const LockInviteParseResult.failure(String this.error) : invite = null;

  final LockInvite? invite;
  final String? error;

  bool get isValid => invite != null;
}
