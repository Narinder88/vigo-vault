import 'package:convert/convert.dart';
import 'package:encrypt/encrypt.dart';
import 'package:fitness_snack_lock/constants/padlock.dart';
import 'package:flutter/foundation.dart' hide Key;

class DataRequestPattern {
  // static String latestEncryptKey = '8ffa7ead965504b28ffa7ead965504b2';
  static String latestEncryptKey = '3A60432A5C01211F291E0F4E0C132825';
  static String defaultTokenHex = '00000000';

  static String getEncryptKey(String deviceId) {
    return kPadlockSecretKeyMap[deviceId] ?? latestEncryptKey;
  }

  static String getTokenHex() {
    return "497B5A81AF9EA6B22243685F03D0B087";
  }

  static String getPowerHex(String token) {
    return "02010101${token}0000000000000000";
  }

  static String getUnlockHex(String token) {
    return "050106303030303030${token}000001";
  }

  static (String first, String last) getSecretKey(
    String token,
    String value,
  ) {
    return ('070108$value${token}00', '070208$value${token}00');
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
