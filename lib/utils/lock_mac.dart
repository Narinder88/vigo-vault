/// Canonical BLE MAC form used as the saved-lock key.
class LockMac {
  static final RegExp _hex12 = RegExp(r'^[0-9A-Fa-f]{12}$');

  /// Colon-separated uppercase MAC when [raw] is 12 hex digits.
  /// Other ids (for example an iOS peripheral UUID) are returned trimmed.
  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    final compact = trimmed.replaceAll(RegExp(r'[-:\s]'), '');
    if (!_hex12.hasMatch(compact)) return trimmed;

    final upper = compact.toUpperCase();
    final octets = <String>[
      for (var index = 0; index < 12; index += 2) upper.substring(index, index + 2),
    ];
    return octets.join(':');
  }

  static bool isMac(String raw) {
    final compact = raw.replaceAll(RegExp(r'[-:\s]'), '');
    return _hex12.hasMatch(compact);
  }

  /// Pulls a 6-byte lock address out of raw advertisement or GATT bytes.
  ///
  /// This lock family advertises an address beginning with `FF:FF:FF`.
  /// A payload that is exactly six bytes is accepted as well.
  static String? macFromBytes(List<int> bytes) {
    if (bytes.length < 6) return null;

    for (var index = 0; index <= bytes.length - 6; index++) {
      if (bytes[index] != 0xFF ||
          bytes[index + 1] != 0xFF ||
          bytes[index + 2] != 0xFF) {
        continue;
      }
      final mac = _formatOctets(bytes.sublist(index, index + 6));
      if (mac != null) return mac;
    }

    for (var index = 0; index <= bytes.length - 6; index++) {
      if (bytes[index + 3] != 0xFF ||
          bytes[index + 4] != 0xFF ||
          bytes[index + 5] != 0xFF) {
        continue;
      }
      final mac = _formatOctets(bytes.sublist(index, index + 6).reversed.toList());
      if (mac != null) return mac;
    }

    if (bytes.length == 6) return _formatOctets(bytes);
    return null;
  }

  static String? _formatOctets(List<int> octets) {
    if (octets.length != 6) return null;
    if (octets.every((byte) => byte == 0x00) ||
        octets.every((byte) => byte == 0xFF)) {
      return null;
    }
    return octets
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
}
