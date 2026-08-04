import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:fitness_snack_lock/services/pairing_service.dart';
import 'package:fitness_snack_lock/services/saved_lock_storage.dart';
import 'package:flutter_riverpod/legacy.dart';

typedef SavedLocksState = ({
  List<SavedLock> locks,
  String? activeLockId,
  String? primaryLockId,
  bool isLoading,
});

final savedLocksProvider =
    StateNotifierProvider<SavedLocksNotifier, SavedLocksState>((ref) {
  return SavedLocksNotifier()..load();
});

class SavedLocksNotifier extends StateNotifier<SavedLocksState> {
  SavedLocksNotifier()
      : super((
          locks: const [],
          activeLockId: null,
          primaryLockId: null,
          isLoading: true,
        ));

  Future<void> load() async {
    if (state.locks.isEmpty) {
      state = (
        locks: state.locks,
        activeLockId: state.activeLockId,
        primaryLockId: state.primaryLockId,
        isLoading: true,
      );
    }

    final locks = await SavedLockStorage.loadLocks();
    await PairingService.migrateExistingLocks(locks.map((lock) => lock.id));
    final activeLockId = await SavedLockStorage.getActiveLockId();
    final storedPrimaryLockId = await SavedLockStorage.getPrimaryLockId();
    var primaryLockId = _resolvePrimaryLockId(
      locks,
      storedPrimaryLockId: storedPrimaryLockId,
      activeLockId: activeLockId,
    );

    if (primaryLockId != storedPrimaryLockId) {
      await SavedLockStorage.setPrimaryLockId(primaryLockId);
    }

    // Keep primary aligned with the first lock in the saved display order.
    if (locks.isNotEmpty && primaryLockId != locks.first.id) {
      primaryLockId = locks.first.id;
      await SavedLockStorage.setPrimaryLockId(primaryLockId);
    }

    state = (
      locks: locks,
      activeLockId: activeLockId,
      primaryLockId: primaryLockId,
      isLoading: false,
    );
  }

  String? _resolvePrimaryLockId(
    List<SavedLock> locks, {
    String? storedPrimaryLockId,
    String? activeLockId,
  }) {
    if (storedPrimaryLockId != null &&
        locks.any((lock) => lock.id == storedPrimaryLockId)) {
      return storedPrimaryLockId;
    }

    if (activeLockId != null && locks.any((lock) => lock.id == activeLockId)) {
      return activeLockId;
    }

    if (locks.isNotEmpty) {
      return locks.first.id;
    }

    return null;
  }

  void _setLocks(
    List<SavedLock> locks, {
    String? activeLockId,
    String? primaryLockId,
  }) {
    state = (
      locks: locks,
      activeLockId: activeLockId ?? state.activeLockId,
      primaryLockId: primaryLockId ?? state.primaryLockId,
      isLoading: false,
    );
  }

  SavedLock? lockById(String id) {
    for (final lock in state.locks) {
      if (lock.id == id) return lock;
    }
    return null;
  }

  List<String> get allDeviceIds =>
      state.locks.map((lock) => lock.id).toList(growable: false);

  String? get resolvedPrimaryLockId => state.primaryLockId;

  bool isPrimaryLock(String lockId) => state.primaryLockId == lockId;

  Future<void> setPrimaryLockId(String lockId) async {
    if (!state.locks.any((lock) => lock.id == lockId)) return;

    final locks = [...state.locks];
    final index = locks.indexWhere((lock) => lock.id == lockId);
    if (index < 0) return;

    final lock = locks.removeAt(index);
    locks.insert(0, lock);

    await SavedLockStorage.saveLocks(locks);
    await SavedLockStorage.setPrimaryLockId(lockId);
    state = (
      locks: locks,
      activeLockId: state.activeLockId,
      primaryLockId: lockId,
      isLoading: state.isLoading,
    );
  }

  /// Reorders locks, persists the new list, and promotes index 0 to primary.
  /// Returns the new primary ID when it changed.
  Future<String?> reorderLocks(
    int oldIndex,
    int newIndex, {
    bool indicesAdjusted = false,
  }) async {
    final locks = [...state.locks];
    if (oldIndex < 0 ||
        oldIndex >= locks.length ||
        newIndex < 0 ||
        newIndex > locks.length) {
      return null;
    }

    var insertIndex = newIndex;
    if (!indicesAdjusted && insertIndex > oldIndex) {
      insertIndex -= 1;
    }
    if (insertIndex == oldIndex) {
      return null;
    }

    final movedLock = locks.removeAt(oldIndex);
    locks.insert(insertIndex, movedLock);

    await SavedLockStorage.saveLocks(locks);

    final previousPrimaryId = state.primaryLockId;
    final newPrimaryId = locks.first.id;
    if (newPrimaryId != previousPrimaryId) {
      await SavedLockStorage.setPrimaryLockId(newPrimaryId);
    }

    _setLocks(
      locks,
      primaryLockId: newPrimaryId,
    );

    return newPrimaryId != previousPrimaryId ? newPrimaryId : null;
  }

  Future<void> addOrUpdateLock(SavedLock lock) async {
    await SavedLockStorage.upsertLock(lock);

    final locks = [...state.locks];
    final index = locks.indexWhere((entry) => entry.id == lock.id);
    if (index >= 0) {
      locks[index] = lock;
    } else {
      locks.add(lock);
    }

    _setLocks(locks);
  }

  Future<void> registerConnectedLock({
    required String deviceId,
    required String displayName,
    String? hardwareName,
    int? batteryLevel,
    int? rssi,
  }) async {
    await PairingService.registerLock(deviceId);

    final existing = lockById(deviceId);
    final lock = (existing ??
            SavedLock(
              id: deviceId,
              displayName: displayName,
              hardwareName: hardwareName,
            ))
        .copyWith(
      displayName: displayName,
      hardwareName: hardwareName ?? existing?.hardwareName,
      lastBatteryLevel: batteryLevel,
      lastRssi: rssi ?? existing?.lastRssi ?? -100,
      lastConnectedAt: DateTime.now(),
    );

    await SavedLockStorage.upsertLock(lock);
    await SavedLockStorage.setActiveLockId(deviceId);

    final locks = [...state.locks];
    final index = locks.indexWhere((entry) => entry.id == deviceId);
    if (index >= 0) {
      locks[index] = lock;
    } else {
      locks.add(lock);
    }

    var primaryLockId = state.primaryLockId;
    if (primaryLockId == null ||
        !locks.any((entry) => entry.id == primaryLockId)) {
      primaryLockId = deviceId;
      await SavedLockStorage.setPrimaryLockId(deviceId);
    }

    _setLocks(
      locks,
      activeLockId: deviceId,
      primaryLockId: primaryLockId,
    );
  }

  Future<void> renameLock(String lockId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final existing = lockById(lockId);
    if (existing == null) return;

    final updated = existing.copyWith(displayName: trimmed);
    await SavedLockStorage.upsertLock(updated);

    final locks = [
      for (final lock in state.locks)
        if (lock.id == lockId) updated else lock,
    ];
    _setLocks(locks);
  }

  Future<void> removeLock(String lockId) async {
    await PairingService.unpairLock(lockId);
    await SavedLockStorage.removeLock(lockId);

    final locks =
        state.locks.where((entry) => entry.id != lockId).toList(growable: false);
    final activeLockId =
        state.activeLockId == lockId ? null : state.activeLockId;
    final primaryLockId = state.primaryLockId == lockId
        ? _resolvePrimaryLockId(locks)
        : state.primaryLockId;

    if (state.primaryLockId == lockId) {
      await SavedLockStorage.setPrimaryLockId(primaryLockId);
    }

    _setLocks(
      locks,
      activeLockId: activeLockId,
      primaryLockId: primaryLockId,
    );
  }

  Future<void> updateTelemetry({
    required String lockId,
    int? batteryLevel,
    int? rssi,
  }) async {
    final existing = lockById(lockId);
    if (existing == null) return;

    final updated = existing.copyWith(
      lastBatteryLevel: batteryLevel ?? existing.lastBatteryLevel,
      lastRssi: rssi ?? existing.lastRssi,
      lastConnectedAt: DateTime.now(),
    );

    await SavedLockStorage.upsertLock(updated);

    final locks = [
      for (final lock in state.locks)
        if (lock.id == lockId) updated else lock,
    ];
    _setLocks(locks);
  }

  Future<void> setActiveLockId(String? lockId) async {
    await SavedLockStorage.setActiveLockId(lockId);
    state = (
      locks: state.locks,
      activeLockId: lockId,
      primaryLockId: state.primaryLockId,
      isLoading: state.isLoading,
    );
  }

  String? get activeLockId => state.activeLockId;
}
