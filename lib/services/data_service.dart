import 'package:convert/convert.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' hide Key;

class DataRequestPattern {
  static const int frameSizeBytes = 16;
  static const int aesBlockSizeBytes = 16;
  static const String defaultEncryptKey = '3A60432A5C01211F291E0F4E0C132825';
  static const String defaultTokenHex = '00000000';
  static const String defaultUnlockSerialHex = '000001';
  /// Factory default password: six ASCII '0' bytes (not hex-encoded "303030...").
  static const List<int> defaultPasswordBytes = [
    0x30,
    0x30,
    0x30,
    0x30,
    0x30,
    0x30,
  ];

  /// Factory AES-128 key used for all lock traffic (ECB, no padding).
  static String getDefaultEncryptKey([String? deviceId]) {
    return defaultEncryptKey;
  }

  /// Command 06 01: request a 4-byte session token from the lock.
  static String getTokenRequestHex() {
    return _frameToHex(const [0x06, 0x01, 0x01, 0x01, 0x00]);
  }

  /// Builds the 16-byte unlock/auth frame: 05 01 06 + PWD[6] + TOKEN[4] + SN[3].
  static List<int> buildUnlockAuthFrame(
    String tokenHex, {
    String serialHex = defaultUnlockSerialHex,
  }) {
    final tokenBytes = _decodeFixedBytes(tokenHex, 4, 'TOKEN');
    final serialBytes = _decodeFixedBytes(serialHex, 3, 'SN');

    return [
      0x05,
      0x01,
      0x06,
      ...defaultPasswordBytes,
      ...tokenBytes,
      ...serialBytes,
    ];
  }

  /// Command 05 01 06 + PWD[6] + TOKEN[4] + SN[3].
  static String getUnlockHex(
    String tokenHex, {
    String serialHex = defaultUnlockSerialHex,
  }) {
    return _frameToHex(buildUnlockAuthFrame(tokenHex, serialHex: serialHex));
  }

  /// Human-readable layout check for unlock/auth frames.
  static String describeUnlockFrame(
    String tokenHex, {
    String serialHex = defaultUnlockSerialHex,
  }) {
    final frame = buildUnlockAuthFrame(tokenHex, serialHex: serialHex);
    return 'header=${hex.encode(frame.sublist(0, 3))} '
        'pwd=${hex.encode(frame.sublist(3, 9))} '
        'token=${hex.encode(frame.sublist(9, 13))} '
        'sn=${hex.encode(frame.sublist(13, 16))} '
        'full=${hex.encode(frame)}';
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

  /// Verifies the 06 02 response checksum byte (sum of command bytes 0–1).
  static bool verifyTokenResponseChecksum(List<int> decrypted) {
    if (decrypted.length < 7) return false;
    if (decrypted[0] != 0x06 || decrypted[1] != 0x02) return false;

    final expectedChecksum = (decrypted[0] + decrypted[1]) & 0xFF;
    return decrypted[2] == expectedChecksum;
  }

  /// Parses TOKEN[4] from decrypted response frame 06 02.
  /// Checksum byte is advisory only — some firmware sends 0x07 instead of 0x08.
  static String? parseSessionToken(
    List<int> decrypted, {
    bool requireChecksum = false,
  }) {
    if (decrypted.length < 7) return null;
    if (decrypted[0] != 0x06 || decrypted[1] != 0x02) return null;
    if (requireChecksum && !verifyTokenResponseChecksum(decrypted)) {
      return null;
    }

    final tokenBytes = decrypted.sublist(3, 7);
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
  static const int aesBlockSizeBytes = DataRequestPattern.aesBlockSizeBytes;

  /// Fixed 8-byte trailer present in many 20-byte 36F6 notifies on provisioned locks.
  static const List<int> framedNotifySuffix = [
    0xC1,
    0xD3,
    0x86,
    0x60,
    0x97,
    0xC7,
    0x75,
    0x91,
  ];

  /// A 16-byte AES ciphertext candidate extracted from a notify payload.
  static ({List<int> block, String label}) aesCandidate(
    List<int> block,
    String label,
  ) {
    assert(block.length == aesBlockSizeBytes);
    return (block: block, label: label);
  }

  static List<int> padToAesBlock(List<int> bytes) {
    final block = List<int>.filled(aesBlockSizeBytes, 0);
    for (var i = 0; i < bytes.length && i < aesBlockSizeBytes; i++) {
      block[i] = bytes[i];
    }
    return block;
  }

  /// True when notify matches `[00 00] payload[6] suffix[8] 00 00 00 00`.
  static bool isFramedSuffixNotify(List<int> response) {
    if (response.length != 20) return false;
    if (response[16] != 0x00 ||
        response[17] != 0x00 ||
        response[18] != 0x00 ||
        response[19] != 0x00) {
      return false;
    }
    for (var i = 0; i < framedNotifySuffix.length; i++) {
      if (response[8 + i] != framedNotifySuffix[i]) return false;
    }
    return true;
  }

  static String describeFramedNotify(List<int> response) {
    if (!isFramedSuffixNotify(response)) {
      return 'not a framed suffix notify';
    }
    return 'leading=${hex.encode(response.sublist(0, 2))} '
        'dynamic=${hex.encode(response.sublist(2, 8))} '
        'suffix=${hex.encode(response.sublist(8, 16))} '
        'trailing=${hex.encode(response.sublist(16, 20))}';
  }

  /// Returns ordered 16-byte AES ciphertext slice candidates from a 36F6 notify.
  static List<({List<int> block, String label})> aesCiphertextBlockCandidates(
    List<int> response,
  ) {
    if (response.length <= aesBlockSizeBytes) {
      if (response.length < aesBlockSizeBytes) {
        return [
          aesCandidate(padToAesBlock(response), 'padded-${response.length}b'),
        ];
      }
      return [aesCandidate(List<int>.from(response), 'full-${response.length}b')];
    }

    if (response.length == 20 && isFramedSuffixNotify(response)) {
      final prefix8 = response.sublist(0, 8);
      final dynamic6 = response.sublist(2, 8);
      final tail4 = response.sublist(16, 20);
      final suffix8 = response.sublist(8, 16);

      return [
        // Bytes before the cleartext suffix — most likely ciphertext region.
        aesCandidate(padToAesBlock(prefix8), 'prefix[0:8]-zpad'),
        aesCandidate(padToAesBlock(dynamic6), 'dynamic[2:8]-zpad'),
        aesCandidate(
          padToAesBlock([...prefix8, ...tail4]),
          'stripSuffix[0:8+16:20]-zpad',
        ),
        aesCandidate(
          padToAesBlock([...dynamic6, ...tail4]),
          'stripSuffix[2:8+16:20]-zpad',
        ),
        aesCandidate(
          padToAesBlock([...dynamic6, ...suffix8]),
          'dynamic[2:8]+suffix[8:16]',
        ),
        aesCandidate(
          padToAesBlock([...prefix8, ...prefix8]),
          'prefix[0:8]x2',
        ),
        // Legacy windows (suffix may be embedded in ciphertext on some firmware).
        aesCandidate(response.sublist(0, aesBlockSizeBytes), 'window[0:16]'),
        aesCandidate(response.sublist(2, 18), 'window[2:18]'),
        aesCandidate(response.sublist(4, 20), 'window[4:20]'),
      ];
    }

    if (response.length == 20) {
      return [
        aesCandidate(response.sublist(0, aesBlockSizeBytes), 'window[0:16]'),
        aesCandidate(response.sublist(2, 18), 'window[2:18]'),
        aesCandidate(response.sublist(4, 20), 'window[4:20]'),
      ];
    }

    return [
      aesCandidate(response.sublist(0, aesBlockSizeBytes), 'window[0:16]'),
    ];
  }

  /// Primary slice candidate (first entry from [aesCiphertextBlockCandidates]).
  static List<int> extractAesCiphertextBlock(List<int> response) {
    return aesCiphertextBlockCandidates(response).first.block;
  }

  static String aesCiphertextHex(List<int> response) {
    return hex.encode(extractAesCiphertextBlock(response));
  }

  /// Tries each slice candidate with each key; returns the first decrypt that
  /// passes [isValidFrame], or the first successful decrypt when no validator.
  static List<int>? tryDecryptNotifyCandidates(
    List<int> response,
    Iterable<String> encryptKeyHexes, {
    bool Function(List<int> decrypted)? isValidFrame,
  }) {
    if (response.isEmpty) return null;

    for (final keyHex in encryptKeyHexes) {
      final normalizedKey = keyHex.toLowerCase();
      for (final candidate in aesCiphertextBlockCandidates(response)) {
        if (candidate.block.length != aesBlockSizeBytes) continue;
        final decrypted = decrypt(hex.encode(candidate.block), normalizedKey);
        if (decrypted == null) continue;
        if (isValidFrame == null || isValidFrame(decrypted)) {
          return decrypted;
        }
      }
    }
    return null;
  }

  static List<int>? decryptNotifyBlock(
    List<int> response,
    String encryptKeyHex, {
    bool Function(List<int> decrypted)? isValidFrame,
  }) {
    return tryDecryptNotifyCandidates(
      response,
      [encryptKeyHex],
      isValidFrame: isValidFrame,
    );
  }

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
