import 'dart:convert';
import 'dart:io' show Platform;

import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:fitness_snack_lock/services/paired_lock_storage.dart';
import 'package:fitness_snack_lock/utils/lock_mac.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LockInvite {
  const LockInvite({
    required this.name,
    required this.displayName,
    required this.macAddress,
    required this.aesKey,
    required this.password,
  });

  /// Padlock BLE advertised name, for example `BR38`.
  final String name;

  /// User-facing nickname, for example `Fridge`. Falls back to [name].
  final String displayName;
  final String macAddress;
  final String aesKey;
  final String password;

  /// Nickname shown in the lock list. Older invites omit [displayName].
  String get savedDisplayName {
    final custom = displayName.trim();
    if (custom.isNotEmpty) return custom;
    return name;
  }

  static const int version = 1;

  /// UTF-8 JSON `{ v, name, displayName, mac, macAddress, aesKey, password }`
  /// encoded as Base64.
  ///
  /// [name] is always the advertised BLE name so fee7 discovery can match it.
  /// [displayName] is the custom nickname. Android writes the real remoteId
  /// MAC. iOS writes an empty `mac` because CoreBluetooth has no hardware
  /// address. The manufacturer-data placeholder [LockMac.placeholderMac] is
  /// never written.
  static Future<({String code, SavedLock lock})?> encode(SavedLock lock) async {
    final credentialId = lock.id.trim();
    if (credentialId.isEmpty) return null;

    final mac = _exportMac(lock);
    if (mac == null) return null;

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
    final customName = lock.displayName.trim();
    final displayName = customName.isEmpty ? name : customName;

    final payload = jsonEncode({
      'v': version,
      'name': name,
      'displayName': displayName,
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

  /// Android shares its real remoteId MAC. iOS returns an empty string.
  /// Returns null when an Android lock has no real MAC to export.
  static String? _exportMac(SavedLock lock) {
    if (kIsWeb || !Platform.isAndroid) return '';
    final id = LockMac.normalize(lock.id);
    if (!LockMac.isHardwareMac(id)) return null;
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

    final macAddress = _readMac(json);
    if (macAddress == null) {
      return const LockInviteParseResult.failure(
        'The invite MAC address must be 12 hex digits.',
      );
    }

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

    final displayName = _readDisplayName(json, name);

    return LockInviteParseResult.success(
      LockInvite(
        name: name,
        displayName: displayName,
        macAddress: macAddress,
        aesKey: aesKey,
        password: password,
      ),
    );
  }

  /// Custom nickname when the invite has one. Older codes only have [name].
  static String _readDisplayName(Map<String, dynamic> json, String name) {
    final custom = json['displayName']?.toString().trim() ?? '';
    if (custom.isNotEmpty) return custom;
    return name;
  }

  /// Empty, omitted, or the shared placeholder means "discover by name".
  /// A non-empty value must be a 12-digit hardware MAC. Returns null when it is not.
  static String? _readMac(Map<String, dynamic> json) {
    final macField = json.containsKey('mac') ? json['mac']?.toString().trim() : null;
    final legacyField = json.containsKey('macAddress')
        ? json['macAddress']?.toString().trim()
        : null;
    final rawMac = (macField != null && macField.isNotEmpty)
        ? macField
        : (legacyField ?? '');
    if (rawMac.isEmpty || LockMac.isPlaceholderMac(rawMac)) return '';
    if (!LockMac.isMac(rawMac)) return null;
    return LockMac.normalize(rawMac);
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
