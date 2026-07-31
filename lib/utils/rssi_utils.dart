/// No live RSSI reading available (disconnected or not yet synced).
const kRssiUnavailable = -100;

bool isRssiAvailable(int? rssi) =>
    rssi != null && rssi > kRssiUnavailable;

/// Maps a Bluetooth RSSI value (dBm) to a user-friendly signal strength label.
String rssiStrengthLabel(int rssi) {
  if (rssi > -60) return 'Strong';
  if (rssi >= -80) return 'Good';
  return 'Weak';
}

/// Formats RSSI for display, e.g. "-96 dBm (Weak)".
String formatRssiWithLabel(int rssi) {
  return '$rssi dBm (${rssiStrengthLabel(rssi)})';
}

/// Compact RSSI label for inline UI elements when a reading exists.
String formatRssiDisplay(int rssi) => '$rssi dBm';

/// Label when connected but RSSI has not been read yet.
String get kRssiDisconnectedLabel => 'Disconnected';
