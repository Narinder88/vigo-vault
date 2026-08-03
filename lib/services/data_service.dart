import 'package:convert/convert.dart';
import 'package:encrypt/encrypt.dart';
import 'package:fitness_snack_lock/constants/padlock.dart';
import 'package:flutter/foundation.dart' hide Key;

class DataRequestPattern {
  static const int frameSizeBytes = 16;
  static const String defaultEncryptKey = '3A60432A5C01211F291E0F4E0C132825';
  static const String defaultTokenHex = '00000000';
  static const String defaultPasswordAscii = '000000';
  static const String defaultUnlockSerialHex = '000001';

  static String getDefaultEncryptKey(String deviceId) {
    return kPadlockSecretKeyMap[deviceId] ?? defaultEncryptKey;
  }

  /// Command 06 01: request a 4-byte session token from the lock.
  static String getTokenRequestHex() {
    return _frameToHex(const [0x06, 0x01, 0x01, 0x01, 0x00]);
  }

  /// Command 05 01 06 + PWD[6] + TOKEN[4] + SN[3].
  static String getUnlockHex(
    String tokenHex, {
    String serialHex = defaultUnlockSerialHex,
  }) {
    final tokenBytes = _decodeFixedBytes(tokenHex, 4, 'TOKEN');
    final serialBytes = _decodeFixedBytes(serialHex, 3, 'SN');
    final passwordBytes = defaultPasswordAscii.codeUnits;

    return _frameToHex([
      0x05,
      0x01,
      0x06,
      ...passwordBytes,
      ...tokenBytes,
      ...serialBytes,
    ]);
  }

  static String getPowerHex(String tokenHex) {
    final tokenBytes = _decodeFixedBytes(tokenHex, 4, 'TOKEN');
    return _frameToHex([
      0x02,
      0x01,
      0x01,
      0x01,
      ...tokenBytes,
    ]);
  }

  /// Commands 07 01 and 07 02 write the first/last 8 bytes of the AES key.
  static (String first, String last) getSecretKeyProvisioningPayloads(
    String secretKeyHex,
  ) {
    final normalized = secretKeyHex.toLowerCase();
    if (normalized.length != 32) {
      throw ArgumentError('Secret key must be 32 hex characters (16 bytes).');
    }

    final keyBytes = hex.decode(normalized);
    return (
      _frameToHex([0x07, 0x01, ...keyBytes.sublist(0, 8)]),
      _frameToHex([0x07, 0x02, ...keyBytes.sublist(8, 16)]),
    );
  }

  /// Parses TOKEN[4] from decrypted response frame 06 02.
  static String? parseSessionToken(List<int> decrypted) {
    if (decrypted.length < 7) return null;
    if (decrypted[0] != 0x06 || decrypted[1] != 0x02) return null;

    final tokenBytes = decrypted.sublist(3, 7);
    if (tokenBytes.every((value) => value == 0)) {
      return null;
    }

    return hex.encode(tokenBytes);
  }

  static List<int> _decodeFixedBytes(
    String hexValue,
    int expectedBytes,
    String label,
  ) {
    final normalized = hexValue.toLowerCase();
    if (normalized.length != expectedBytes * 2) {
      throw ArgumentError('$label must be ${expectedBytes * 2} hex characters.');
    }
    return hex.decode(normalized);
  }

  static String _frameToHex(List<int> bytes) {
    if (bytes.length > frameSizeBytes) {
      throw ArgumentError('Command frame exceeds $frameSizeBytes bytes.');
    }

    final frame = List<int>.filled(frameSizeBytes, 0);
    for (var i = 0; i < bytes.length; i++) {
      frame[i] = bytes[i];
    }
    return hex.encode(frame);
  }
}

class DataService {
  static Uint8List hexStringToBytes(String hexString) {
    var result = Uint8List(hexString.length ~/ 2);
    for (var i = 0; i < hexString.length; i += 2) {
      var num = int.parse(hexString.substring(i, i + 2), radix: 16);
      result[i ~/ 2] = num;
    }
    return result;
  }

  static List<int> hexStringToBytesList(String hexString) {
    return hex.decode(hexString);
  }

  static String bytesListToHexString(List<int> bytes) {
    return hex.encode(bytes);
  }

  static String bytesToHexString(List<int> bytes) {
    final parsedBytes = Uint8List.fromList(bytes);
    StringBuffer hexStringBuffer = StringBuffer();

    for (var byte in parsedBytes) {
      hexStringBuffer.write(
        byte.toRadixString(16).padLeft(2, '0').toUpperCase(),
      );
    }
    return hexStringBuffer.toString();
  }

  static List<int>? encrypt(String data, String ekey) {
    try {
      final key = Key.fromBase16(ekey);
      final encrypter = Encrypter(AES(key, mode: AESMode.ecb, padding: null));
      final encrypted = encrypter.encryptBytes(
        Encrypted.fromBase16(data).bytes,
        iv: IV.fromBase16(ekey),
      );
      return encrypted.bytes.toList();
    } catch (_) {
      return null;
    }
  }

  static List<int>? decrypt(String data, String dkey) {
    try {
      final key = Key.fromBase16(dkey);
      final encrypter = Encrypter(AES(key, mode: AESMode.ecb, padding: null));
      final decrypted = encrypter.decryptBytes(
        Encrypted.fromBase16(data),
        iv: IV.fromBase16(dkey),
      );
      return decrypted;
    } catch (_) {
      return null;
    }
  }
}
