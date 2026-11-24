import 'package:fitness_snack_lock/utils/lock_mac.dart';

class SavedLock {
  const SavedLock({
    required this.id,
    required this.displayName,
    this.hardwareName,
    this.hardwareMac,
    this.peripheralUuid,
    this.lastBatteryLevel,
    this.lastRssi = -100,
    this.lastConnectedAt,
    this.isPinned = false,
  });

  final String id;
  final String displayName;
  final String? hardwareName;

  /// 6-byte lock address (`AA:BB:CC:DD:EE:FF`). On Android this matches [id].
  final String? hardwareMac;

  /// CoreBluetooth peripheral UUID. On iOS this matches [id] once the lock
  /// has been seen. Android leaves this empty.
  final String? peripheralUuid;
  final int? lastBatteryLevel;
  final int lastRssi;
  final DateTime? lastConnectedAt;

  /// Dashboard ordering only. Missing on older saved locks, which stay unpinned.
  final bool isPinned;

  /// Hardware MAC when it is already known, including Android ids that are MACs.
  String? get resolvedHardwareMac {
    final stored = hardwareMac?.trim();
    if (stored != null && stored.isNotEmpty && LockMac.isMac(stored)) {
      return LockMac.normalize(stored);
    }
    if (LockMac.isMac(id)) return LockMac.normalize(id);
    return null;
  }

  SavedLock copyWith({
    String? id,
    String? displayName,
    String? hardwareName,
    String? hardwareMac,
    String? peripheralUuid,
    int? lastBatteryLevel,
    int? lastRssi,
    DateTime? lastConnectedAt,
    bool? isPinned,
    bool clearBattery = false,
  }) {
    return SavedLock(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      hardwareName: hardwareName ?? this.hardwareName,
      hardwareMac: hardwareMac ?? this.hardwareMac,
      peripheralUuid: peripheralUuid ?? this.peripheralUuid,
      lastBatteryLevel:
          clearBattery ? null : (lastBatteryLevel ?? this.lastBatteryLevel),
      lastRssi: lastRssi ?? this.lastRssi,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'hardwareName': hardwareName,
      'hardwareMac': hardwareMac,
      'peripheralUuid': peripheralUuid,
      'lastBatteryLevel': lastBatteryLevel,
      'lastRssi': lastRssi,
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      'isPinned': isPinned,
    };
  }

  factory SavedLock.fromJson(Map<String, dynamic> json) {
    final lastConnectedRaw = json['lastConnectedAt'] as String?;
    return SavedLock(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? 'Smart Lock',
      hardwareName: json['hardwareName'] as String?,
      hardwareMac: json['hardwareMac'] as String?,
      peripheralUuid: json['peripheralUuid'] as String?,
      lastBatteryLevel: json['lastBatteryLevel'] as int?,
      lastRssi: json['lastRssi'] as int? ?? -100,
      lastConnectedAt: lastConnectedRaw == null
          ? null
          : DateTime.tryParse(lastConnectedRaw),
      isPinned: json['isPinned'] as bool? ?? false,
    );
  }
}

/// Pinned locks stay at the top. Relative order is kept inside each group.
List<SavedLock> sortLocksPinnedFirst(List<SavedLock> locks) {
  final pinned = <SavedLock>[];
  final unpinned = <SavedLock>[];
  for (final lock in locks) {
    if (lock.isPinned) {
      pinned.add(lock);
    } else {
      unpinned.add(lock);
    }
  }
  return [...pinned, ...unpinned];
}
