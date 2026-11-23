import 'dart:convert';

import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:fitness_snack_lock/services/hardware_mac_service.dart';
import 'package:fitness_snack_lock/services/paired_lock_storage.dart';
import 'package:fitness_snack_lock/utils/lock_mac.dart';

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

  /// UTF-8 JSON `{ v, name, macAddress, aesKey, password }` encoded as Base64.
  ///
  /// [macAddress] is the 6-byte hardware MAC, never a CoreBluetooth UUID.
  static Future<({String code, SavedLock lock})?> encode(SavedLock lock) async {
    final shareable = HardwareMacService.usesPeripheralUuid
        ? await HardwareMacService.persistForLock(lock)
        : lock;
    if (shareable == null) return null;

    final macAddress = LockMac.normalize(
      HardwareMacService.usesPeripheralUuid
          ? (shareable.hardwareMac ?? shareable.id)
          : shareable.id,
    );
    if (!LockMac.isMac(macAddress)) return null;

    final credentialId = HardwareMacService.usesPeripheralUuid
        ? (shareable.peripheralUuid ?? shareable.id)
        : macAddress;
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

    final name = shareable.displayName.trim();
    if (name.isEmpty) return null;

    final payload = jsonEncode({
      'v': version,
      'name': name,
      'macAddress': macAddress,
      'aesKey': aesKey,
      'password': password,
    });
    return (
      code: base64Encode(utf8.encode(payload)),
      lock: shareable,
    );
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

    final macAddress = LockMac.normalize(json['macAddress']?.toString() ?? '');
    if (!LockMac.isMac(macAddress)) {
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

class LockInviteParseResult {
  const LockInviteParseResult.success(LockInvite this.invite) : error = null;

  const LockInviteParseResult.failure(String this.error) : invite = null;

  final LockInvite? invite;
  final String? error;

  bool get isValid => invite != null;
}
