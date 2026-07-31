class SavedLock {
  const SavedLock({
    required this.id,
    required this.displayName,
    this.hardwareName,
    this.lastBatteryLevel,
    this.lastRssi = -100,
    this.lastConnectedAt,
  });

  final String id;
  final String displayName;
  final String? hardwareName;
  final int? lastBatteryLevel;
  final int lastRssi;
  final DateTime? lastConnectedAt;

  SavedLock copyWith({
    String? id,
    String? displayName,
    String? hardwareName,
    int? lastBatteryLevel,
    int? lastRssi,
    DateTime? lastConnectedAt,
    bool clearBattery = false,
  }) {
    return SavedLock(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      hardwareName: hardwareName ?? this.hardwareName,
      lastBatteryLevel:
          clearBattery ? null : (lastBatteryLevel ?? this.lastBatteryLevel),
      lastRssi: lastRssi ?? this.lastRssi,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'hardwareName': hardwareName,
      'lastBatteryLevel': lastBatteryLevel,
      'lastRssi': lastRssi,
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
    };
  }

  factory SavedLock.fromJson(Map<String, dynamic> json) {
    final lastConnectedRaw = json['lastConnectedAt'] as String?;
    return SavedLock(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? 'Smart Lock',
      hardwareName: json['hardwareName'] as String?,
      lastBatteryLevel: json['lastBatteryLevel'] as int?,
      lastRssi: json['lastRssi'] as int? ?? -100,
      lastConnectedAt: lastConnectedRaw == null
          ? null
          : DateTime.tryParse(lastConnectedRaw),
    );
  }
}
