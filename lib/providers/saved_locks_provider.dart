import 'dart:async';
import 'dart:io' show Platform;

import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/lock_invite.dart';
import 'package:fitness_snack_lock/services/pairing_service.dart';
import 'package:fitness_snack_lock/services/paired_lock_storage.dart';
import 'package:fitness_snack_lock/services/saved_lock_storage.dart';
import 'package:fitness_snack_lock/utils/lock_mac.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
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

  var _importInProgress = false;

  String? _inviteHardwareName(LockInvite invite) {
    final name = _usefulHardwareName(invite.name);
    if (name == null) return null;
    final display = LockInvite.sanitizeBleName(invite.displayName);
    if (name == display && name.contains(' ')) return null;
    return name;
  }

  String? _usefulHardwareName(String? raw) {
    final value = LockInvite.sanitizeBleName(raw ?? '');
    if (value.isEmpty || value == 'Smart Lock') return null;
    return value;
  }

  Future<void> load() async {
    final existing = state.locks;
    if (existing.isNotEmpty || _importInProgress) {
      state = (
        locks: existing,
        activeLockId: state.activeLockId,
        primaryLockId: state.primaryLockId,
        isLoading: false,
      );
    } else {
      state = (
        locks: existing,
        activeLockId: state.activeLockId,
        primaryLockId: state.primaryLockId,
        isLoading: true,
      );
    }

    final locks = await SavedLockStorage.loadLocks();
    if (_importInProgress && locks.isEmpty && state.locks.isNotEmpty) {
      state = (
        locks: state.locks,
        activeLockId: state.activeLockId,
        primaryLockId: state.primaryLockId,
        isLoading: false,
      );
      return;
    }
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

    final nextLocks = _importInProgress
        ? _unionLocks(loaded: locks, current: state.locks)
        : locks;
    state = (
      locks: nextLocks,
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

  List<SavedLock> _unionLocks({
    required List<SavedLock> loaded,
    required List<SavedLock> current,
  }) {
    final merged = [...loaded];
    for (final lock in current) {
      if (!merged.any((entry) => entry.id == lock.id)) {
        merged.add(lock);
      }
    }
    return merged;
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
    final query = LockMac.normalize(id);
    for (final lock in state.locks) {
      if (lock.id == id || lock.id == query) return lock;
    }
    return null;
  }

  List<String> get allDeviceIds =>
      state.locks.map((lock) => lock.id).toList(growable: false);

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
    final locks = sortLocksPinnedFirst(state.locks);
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
    final ordered = sortLocksPinnedFirst(locks);

    await SavedLockStorage.saveLocks(ordered);

    final previousPrimaryId = state.primaryLockId;
    final newPrimaryId = ordered.first.id;
    if (newPrimaryId != previousPrimaryId) {
      await SavedLockStorage.setPrimaryLockId(newPrimaryId);
      await PairedLockStorage.syncLockToWatch(newPrimaryId);
    }

    _setLocks(
      ordered,
      primaryLockId: newPrimaryId,
    );

    return newPrimaryId != previousPrimaryId ? newPrimaryId : null;
  }

  Future<void> setLockPinned(String lockId, bool isPinned) async {
    final existing = lockById(lockId);
    if (existing == null || existing.isPinned == isPinned) return;

    final locks = [
      for (final lock in state.locks)
        if (lock.id == existing.id)
          lock.copyWith(isPinned: isPinned)
        else
          lock,
    ];
    await SavedLockStorage.saveLocks(locks);
    _setLocks(locks);
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
    final locks = [
      for (final lock in state.locks)
        if (lock.id == updated.id) updated else lock,
    ];
    if (!locks.any((lock) => lock.id == updated.id)) {
      locks.add(updated);
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
    final id = LockMac.normalize(deviceId);
    await PairingService.registerLock(id);

    final existing = lockById(id);
    final rememberedHardware = _usefulHardwareName(hardwareName) ??
        _usefulHardwareName(existing?.hardwareName);
    final lock = (existing ??
            SavedLock(
              id: id,
              displayName: displayName,
              hardwareName: rememberedHardware,
            ))
        .copyWith(
      id: id,
      displayName: displayName,
      hardwareName: rememberedHardware ?? existing?.hardwareName,
      lastBatteryLevel: batteryLevel,
      lastRssi: rssi ?? existing?.lastRssi ?? -100,
      lastConnectedAt: DateTime.now(),
    );

    await SavedLockStorage.upsertLock(lock);
    await SavedLockStorage.setActiveLockId(id);

    final locks = [...state.locks];
    final index = locks.indexWhere((entry) => entry.id == id);
    if (index >= 0) {
      locks[index] = lock;
    } else {
      locks.add(lock);
    }

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

  /// Saves a shared lock locally. Does not factory-reset the padlock.
  ///
  /// Direct-MAC import is Android-only. iOS and iPadOS cannot connect by the
  /// hardware MAC in an Android invite, so they always scan fee7 and save the
  /// CoreBluetooth peripheral UUID that accepts the invite AES key.
  Future<void> importSharedLock(LockInvite invite) async {
    _importInProgress = true;
    try {
      if (!kIsWeb && Platform.isAndroid && invite.hasValidMac) {
        await _importByHardwareMac(
          LockMac.normalize(invite.macAddress),
          invite,
        );
        return;
      }
      await _importByAdvertisedName(invite);
    } finally {
      _importInProgress = false;
    }
  }

  Future<void> _importByHardwareMac(String id, LockInvite invite) async {
    debugPrint('Import shared lock by MAC $id');
    await PairedLockStorage.pair(id);
    await PairedLockStorage.saveSecretKey(id, invite.aesKey);
    await PairedLockStorage.savePassword(id, invite.password);

    final existing = lockById(id);
    final invitedHardware = _inviteHardwareName(invite);
    final hardwareName =
        invitedHardware ?? _usefulHardwareName(existing?.hardwareName);
    final lock = (existing ??
            SavedLock(
              id: id,
              displayName: invite.savedDisplayName,
              hardwareName: hardwareName,
            ))
        .copyWith(
          displayName: invite.savedDisplayName,
          hardwareName: hardwareName ?? existing?.hardwareName,
        );

    await addOrUpdateLock(lock);

    if (state.primaryLockId == null ||
        !state.locks.any((entry) => entry.id == state.primaryLockId)) {
      await setPrimaryLockId(id);
    }
  }

  Future<void> _importByAdvertisedName(LockInvite invite) async {
    final savedIds = allDeviceIds.toSet();
    final found = await BleService.findAuthenticatedRemoteId(
      advertisedName: invite.name,
      macAddress: invite.macAddress,
      aesKey: invite.aesKey,
      password: invite.password,
      savedRemoteIds: savedIds,
    );
    final rawId = found?.trim() ?? '';
    final connectId = LockMac.isMac(rawId) ? LockMac.normalize(rawId) : rawId;
    final alreadySaved = connectId.isNotEmpty &&
        (savedIds.contains(found) || savedIds.contains(connectId));
    if (connectId.isEmpty || alreadySaved) {
      throw SharedLockNotFound(
        'No nearby lock responded. Move closer to the lock, '
        'make sure no other phone is currently connected to it, and try again.',
      );
    }
    debugPrint('Import shared lock by name ${invite.name} -> $connectId');

    final seenName = BleService.advertisedNameSeen(connectId);
    final hardwareName =
        seenName.isNotEmpty ? seenName : _inviteHardwareName(invite);
    final lock = SavedLock(
      id: connectId,
      displayName: invite.savedDisplayName,
      hardwareName: hardwareName,
    );
    _publishLock(lock);

    await PairedLockStorage.pair(connectId);
    await PairedLockStorage.saveSecretKey(connectId, invite.aesKey);
    await PairedLockStorage.savePassword(connectId, invite.password);
    await SavedLockStorage.upsertLock(lock);
    if (state.primaryLockId == connectId) {
      await SavedLockStorage.setPrimaryLockId(connectId);
      unawaited(PairedLockStorage.syncLockToWatch(connectId));
    }
  }

  void _publishLock(SavedLock lock) {
    final locks = [...state.locks];
    final index = locks.indexWhere((entry) => entry.id == lock.id);
    if (index >= 0) {
      locks[index] = lock;
    } else {
      locks.add(lock);
    }
    var primaryLockId = state.primaryLockId;
    if (primaryLockId == null ||
        !locks.any((entry) => entry.id == primaryLockId)) {
      primaryLockId = lock.id;
    }
    state = (
      locks: locks,
      activeLockId: state.activeLockId,
      primaryLockId: primaryLockId,
      isLoading: false,
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
    final existing = lockById(lockId);
    final removedId = existing?.id ?? LockMac.normalize(lockId);
    try {
      await BleService.disconnectDevice(removedId);
    } catch (_) {}
    await PairingService.unpairLock(removedId);
    BleService.clearDeviceCredentials(removedId);
    await SavedLockStorage.removeLock(removedId);

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
