// Unread and disconnected battery values are `0` or `null`.
// Only a percentage above 0 is a real reading.

/// `null` and `0` are not readings and must not be stored or alerted on.
int? persistableBatteryLevel(int? battery) {
  if (battery == null || battery <= 0) return null;
  return battery;
}

/// Keeps the last real percentage. `0` and `null` never replace it.
int? retainedBatteryLevel(int? incoming, int? existing) {
  return persistableBatteryLevel(incoming) ?? existing;
}

/// Low battery is a known reading from 1% through 20%.
bool isLowBatteryLevel(int? battery) {
  final reading = persistableBatteryLevel(battery);
  return reading != null && reading <= 20;
}
