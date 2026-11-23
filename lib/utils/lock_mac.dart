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

  /// Every padlock puts these bytes in manufacturer data. They are not an id.
  static const String placeholderMac = 'FF:FF:FF:11:22:33';

  static bool isPlaceholderMac(String raw) => normalize(raw) == placeholderMac;

  /// A real Android hardware MAC. The shared manufacturer-data placeholder is not one.
  static bool isHardwareMac(String raw) {
    final mac = normalize(raw);
    return isMac(mac) && !isPlaceholderMac(mac);
  }
}
