import 'dart:async';

import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/hardware_mac_service.dart';
import 'package:fitness_snack_lock/services/lock_invite.dart';
import 'package:fitness_snack_lock/services/pairing_service.dart';
import 'package:fitness_snack_lock/services/paired_lock_storage.dart';
import 'package:fitness_snack_lock/services/saved_lock_storage.dart';
import 'package:fitness_snack_lock/utils/lock_mac.dart';
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
        )) {
    SavedLockStorage.onLocksChanged = () {
      if (!mounted) return;
      unawaited(load());
    };
  }

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

    if (primaryLockId != null) {
      await PairedLockStorage.syncLockToWatch(primaryLockId);
    }
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
    if (!HardwareMacService.usesPeripheralUuid) return null;
    for (final lock in state.locks) {
      if (_lockMatches(lock, id)) return lock;
    }
    return null;
  }

  bool _lockMatches(SavedLock lock, String raw) {
    final query = raw.trim();
    if (query.isEmpty) return false;
    if (lock.id == query || lock.peripheralUuid == query) return true;
    if (!LockMac.isMac(query)) return false;
    final mac = LockMac.normalize(query);
    if (LockMac.isMac(lock.id) && LockMac.normalize(lock.id) == mac) return true;
    final stored = lock.hardwareMac;
    return stored != null && LockMac.normalize(stored) == mac;
  }

  List<String> get allDeviceIds {
    if (!HardwareMacService.usesPeripheralUuid) {
      return state.locks.map((lock) => lock.id).toList(growable: false);
    }
    return [
      for (final lock in state.locks) ...[
        lock.id,
        if (lock.hardwareMac != null && lock.hardwareMac!.isNotEmpty)
          lock.hardwareMac!,
        if (lock.peripheralUuid != null && lock.peripheralUuid!.isNotEmpty)
          lock.peripheralUuid!,
      ],
    ];
  }

  String? get resolvedPrimaryLockId => state.primaryLockId;

  bool isPrimaryLock(String lockId) => state.primaryLockId == lockId;

  Future<void> setPrimaryLockId(String lockId) async {
    final id = LockMac.normalize(lockId);
    if (!state.locks.any((lock) => lock.id == id)) return;

    final locks = [...state.locks];
    final index = locks.indexWhere((lock) => lock.id == id);
    if (index < 0) return;

    final lock = locks.removeAt(index);
    locks.insert(0, lock);

    await SavedLockStorage.saveLocks(locks);
    await SavedLockStorage.setPrimaryLockId(id);
    state = (
      locks: locks,
      activeLockId: state.activeLockId,
      primaryLockId: id,
      isLoading: state.isLoading,
    );
    await PairedLockStorage.syncLockToWatch(id);
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
      await PairedLockStorage.syncLockToWatch(newPrimaryId);
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

  void replaceLock(SavedLock updated) {
    if (!HardwareMacService.usesPeripheralUuid) {
      final locks = [
        for (final lock in state.locks)
          if (lock.id == updated.id) updated else lock,
      ];
      if (!locks.any((lock) => lock.id == updated.id)) {
        locks.add(updated);
      }
      _setLocks(locks);
      return;
    }

    final locks = <SavedLock>[];
    var replaced = false;
    for (final lock in state.locks) {
      if (_lockMatches(lock, updated.id) ||
          (updated.hardwareMac != null &&
              _lockMatches(lock, updated.hardwareMac!)) ||
          (updated.peripheralUuid != null &&
              _lockMatches(lock, updated.peripheralUuid!))) {
        locks.add(updated);
        replaced = true;
      } else {
        locks.add(lock);
      }
    }
    if (!replaced) locks.add(updated);
    _setLocks(locks);
  }

  Future<void> registerConnectedLock({
    required String deviceId,
    required String displayName,
    String? hardwareName,
    String? hardwareMac,
    String? peripheralUuid,
    int? batteryLevel,
    int? rssi,
  }) async {
    final id = LockMac.normalize(deviceId);
    await PairingService.registerLock(id);

    final mapIds = HardwareMacService.usesPeripheralUuid;
    final normalizedMac = mapIds &&
            hardwareMac != null &&
            LockMac.isMac(hardwareMac)
        ? LockMac.normalize(hardwareMac)
        : null;
    final resolvedUuid = mapIds &&
            peripheralUuid != null &&
            peripheralUuid.isNotEmpty &&
            !LockMac.isMac(peripheralUuid)
        ? peripheralUuid
        : null;
    if (normalizedMac != null && normalizedMac != id) {
      await PairedLockStorage.aliasCredentials(
        peripheralId: id,
        hardwareMac: normalizedMac,
      );
    }

    final existing = lockById(id) ??
        (normalizedMac == null ? null : lockById(normalizedMac));
    final lock = (existing ??
            SavedLock(
              id: id,
              displayName: displayName,
              hardwareName: hardwareName,
            ))
        .copyWith(
      id: id,
      displayName: displayName,
      hardwareName: hardwareName ?? existing?.hardwareName,
      hardwareMac: mapIds
          ? (normalizedMac ?? existing?.hardwareMac)
          : existing?.hardwareMac,
      peripheralUuid: mapIds
          ? (resolvedUuid ?? existing?.peripheralUuid)
          : existing?.peripheralUuid,
      lastBatteryLevel: batteryLevel,
      lastRssi: rssi ?? existing?.lastRssi ?? -100,
      lastConnectedAt: DateTime.now(),
    );

    if (existing != null && existing.id != lock.id) {
      await SavedLockStorage.removeLock(existing.id);
    }
    await SavedLockStorage.upsertLock(lock);
    await SavedLockStorage.setActiveLockId(id);

    final locks = [
      for (final entry in state.locks)
        if (entry.id != id && entry.id != existing?.id) entry,
      lock,
    ];

    var primaryLockId = state.primaryLockId;
    if (primaryLockId == null ||
        !locks.any((entry) => entry.id == primaryLockId)) {
      primaryLockId = id;
      await SavedLockStorage.setPrimaryLockId(id);
      await PairedLockStorage.syncLockToWatch(id);
    }

    _setLocks(
      locks,
      activeLockId: id,
      primaryLockId: primaryLockId,
    );
  }

  /// Saves a shared lock locally. On iOS, scans for the hardware MAC and
  /// binds the CoreBluetooth peripheral UUID before the lock is stored.
  Future<void> importSharedLock(LockInvite invite) async {
    final mac = LockMac.normalize(invite.macAddress);
    if (!HardwareMacService.usesPeripheralUuid) {
      await PairedLockStorage.pair(mac);
      await PairedLockStorage.saveSecretKey(mac, invite.aesKey);
      await PairedLockStorage.savePassword(mac, invite.password);

      final existing = lockById(mac);
      final lock = (existing ??
              SavedLock(
                id: mac,
                displayName: invite.name,
              ))
          .copyWith(displayName: invite.name);

      await addOrUpdateLock(lock);

      if (state.primaryLockId == null ||
          !state.locks.any((entry) => entry.id == state.primaryLockId)) {
        await setPrimaryLockId(mac);
      }
      return;
    }

    var connectId = mac;
    String? peripheralUuid;
    peripheralUuid = await HardwareMacService.findPeripheralUuid(mac);
    if (peripheralUuid != null && peripheralUuid.isNotEmpty) {
      connectId = peripheralUuid;
    }

    await PairedLockStorage.pair(connectId);
    await PairedLockStorage.pair(mac);
    await PairedLockStorage.saveSecretKey(connectId, invite.aesKey);
    await PairedLockStorage.savePassword(connectId, invite.password);
    await PairedLockStorage.aliasCredentials(
      peripheralId: connectId,
      hardwareMac: mac,
    );

    final existing = lockById(connectId) ?? lockById(mac);
    final lock = (existing ??
            SavedLock(
              id: connectId,
              displayName: invite.name,
            ))
        .copyWith(
      id: connectId,
      displayName: invite.name,
      hardwareMac: mac,
      peripheralUuid: peripheralUuid ?? existing?.peripheralUuid,
    );

    await addOrUpdateLock(lock);

    if (state.primaryLockId == null ||
        !state.locks.any((entry) => entry.id == state.primaryLockId)) {
      await setPrimaryLockId(connectId);
    }
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
    final existing = lockById(lockId);
    await PairingService.unpairLock(lockId);
    if (HardwareMacService.usesPeripheralUuid &&
        existing?.hardwareMac != null &&
        existing!.hardwareMac != lockId) {
      await PairingService.unpairLock(existing.hardwareMac!);
    }
    if (HardwareMacService.usesPeripheralUuid &&
        existing?.peripheralUuid != null &&
        existing!.peripheralUuid != lockId) {
      await PairingService.unpairLock(existing.peripheralUuid!);
    }
    BleService.clearDeviceCredentials(lockId);
    if (HardwareMacService.usesPeripheralUuid &&
        existing?.hardwareMac != null &&
        existing!.hardwareMac != lockId) {
      BleService.clearDeviceCredentials(existing.hardwareMac!);
    }
    await SavedLockStorage.removeLock(existing?.id ?? lockId);

    final removedId = existing?.id ?? lockId;
    final locks = state.locks
        .where((entry) => entry.id != removedId && entry.id != lockId)
        .toList(growable: false);
    final activeLockId = state.activeLockId == removedId ||
            state.activeLockId == lockId
        ? null
        : state.activeLockId;
    final primaryLockId = state.primaryLockId == removedId ||
            state.primaryLockId == lockId
        ? _resolvePrimaryLockId(locks)
        : state.primaryLockId;

    if (state.primaryLockId == removedId || state.primaryLockId == lockId) {
      await SavedLockStorage.setPrimaryLockId(primaryLockId);
      if (primaryLockId != null) {
        await PairedLockStorage.syncLockToWatch(primaryLockId);
      }
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
    final id = lockId == null || lockId.isEmpty
        ? null
        : LockMac.normalize(lockId);
    await SavedLockStorage.setActiveLockId(id);
    state = (
      locks: state.locks,
      activeLockId: id,
      primaryLockId: state.primaryLockId,
      isLoading: state.isLoading,
    );
  }

  String? get activeLockId => state.activeLockId;
}
