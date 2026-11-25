import 'dart:ui' show lerpDouble;

import 'package:fitness_snack_lock/constants/app_branding.dart';
import 'package:fitness_snack_lock/features/device/helpful_tips_page.dart';
import 'package:fitness_snack_lock/features/lock/home_page.dart';
import 'package:fitness_snack_lock/features/device/device_scanning_page/device_scanning_page.dart';
import 'package:fitness_snack_lock/features/device/share_lock_dialog.dart';
import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/providers/lock_unlock_event_provider.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/ble_connection_monitor.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/lock_connection_helper.dart';
import 'package:fitness_snack_lock/utils/battery_level.dart';
import 'package:fitness_snack_lock/utils/lock_mac.dart';
import 'package:fitness_snack_lock/utils/rssi_utils.dart';
import 'package:fitness_snack_lock/widgets/rename_lock_dialog.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:zo_animated_border/zo_animated_border.dart';

class DeviceDashboardPage extends ConsumerStatefulWidget {
  const DeviceDashboardPage({super.key});

  static const routeName = '/dashboard';

  @override
  ConsumerState<DeviceDashboardPage> createState() =>
      _DeviceDashboardPageState();
}

enum _LockMenuAction { rename, share, pin, forget, factoryReset }

class _DeviceDashboardPageState extends ConsumerState<DeviceDashboardPage> {
  static const _backgroundColor = Color(0xFF1A1B1E);
  static const _cardColor = Color(0xFF2C2D31);
  static const _labelColor = Color(0xFFFFFFFF);
  static const _subtextColor = Color(0xFF9E9E9E);
  static const _accentColor = Color(0xFF00E676);
  static const _disabledColor = Color(0xFF5C5D62);

  String? _connectingLockId;
  final Set<String> _unlockReadyLockIds = {};
  final Set<String> _sessionLockIds = {};
  final Map<String, int> _sessionGenerationByLockId = {};
  final Map<String, int> _backgroundWarmUpGenerationByLockId = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeDashboardBle();
    });
  }

  Future<void> _initializeDashboardBle() async {
    await _releaseStaleBleSessions();
  }

  void _clearConnectingLockId(String lockId) {
    if (_connectingLockId != lockId) return;
    if (mounted) {
      setState(() => _connectingLockId = null);
    } else {
      _connectingLockId = null;
    }
  }

  void _markLockUnlockReady(String lockId) {
    if (mounted) {
      setState(() => _unlockReadyLockIds.add(lockId));
    } else {
      _unlockReadyLockIds.add(lockId);
    }
  }

  void _clearLockUnlockReady(String lockId) {
    if (mounted) {
      setState(() => _unlockReadyLockIds.remove(lockId));
    } else {
      _unlockReadyLockIds.remove(lockId);
    }
  }

  bool _sameLock(String? remoteId, String lockId) {
    if (remoteId == null || remoteId.isEmpty) return false;
    return LockMac.normalize(remoteId) == LockMac.normalize(lockId);
  }

  bool _hasBleSession(SavedLock lock, BleData bleState) {
    return _sameLock(bleState.device?.remoteId.str, lock.id) &&
        bleState.token != null &&
        !bleState.isConnecting;
  }

  bool _isLockConnected(SavedLock lock, BleData bleState) {
    if (!BluetoothDevice.fromId(lock.id).isConnected) return false;
    if (BleService.isDeviceConnected(lock.id)) return true;
    if (_hasBleSession(lock, bleState)) return true;
    return _unlockReadyLockIds.contains(lock.id) &&
        LockConnectionHelper.isValidToken(BleService.tokenForDevice(lock.id));
  }

  Future<void> _releaseStaleBleSessions() async {
    final knownIds = ref.read(savedLocksProvider.notifier).allDeviceIds;
    await BleService.releaseAllActiveConnections(knownDeviceIds: knownIds);
    if (!mounted) return;
    ref.read(bleProvider.notifier).clearSession();
    BleConnectionMonitor.stopMonitoring();
    setState(() {
      _unlockReadyLockIds.clear();
      _sessionLockIds.clear();
      _connectingLockId = null;
    });
  }

  Future<void> _openLock(SavedLock lock) async {
    await ref.read(savedLocksProvider.notifier).setActiveLockId(lock.id);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => HomePage(
          lockDeviceId: lock.id,
          onUnlockSuccess: () {},
          onBackToDashboard: () {
            final navigator = Navigator.maybeOf(routeContext);
            if (navigator != null && navigator.canPop()) {
              navigator.pop();
            }
          },
        ),
      ),
    );
  }

  Future<void> _addLock() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => const DeviceScanningPage(fromDashboard: true),
      ),
    );

    if (!mounted) return;
    await _releaseStaleBleSessions();
  }

  Future<void> _renameLock(SavedLock lock) async {
    final newName = await showRenameLockDialog(
      context: context,
      initialName: lock.displayName,
      title: 'Rename Lock',
    );

    if (!mounted || newName == null || newName.isEmpty) return;

    await ref.read(savedLocksProvider.notifier).renameLock(lock.id, newName);

    if (!mounted) return;

    final activeDevice = ref.read(bleProvider).device;
    if (_sameLock(activeDevice?.remoteId.str, lock.id)) {
      ref.read(bleProvider.notifier).setCustomDeviceName(newName);
    }
  }

  Future<void> _shareLock(SavedLock lock) async {
    await showShareLockDialog(
      context: context,
      lock: lock,
    );
  }

  Future<void> _forgetLockOnThisPhone(SavedLock lock) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _cardColor,
          title: const Text(
            'Forget on this phone',
            style: TextStyle(color: _labelColor),
          ),
          content: Text(
            'Remove "${lock.displayName}" from this phone only. '
            'The padlock is not factory reset, and anyone with a shared '
            'invite can still open it.',
            style: const TextStyle(color: _subtextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF2020),
              ),
              child: const Text('Forget'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await _forgetLockLocally(lock);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${lock.displayName} was removed from this phone.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _forgetLockLocally(SavedLock lock) async {
    await ref.read(savedLocksProvider.notifier).removeLock(lock.id);
    ref.read(bleProvider.notifier).clearSession();
    _clearLockUnlockReady(lock.id);
    _sessionLockIds.remove(lock.id);
    _sessionGenerationByLockId.remove(lock.id);
    _backgroundWarmUpGenerationByLockId.remove(lock.id);
  }

  Future<void> _removeLock(SavedLock lock) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _cardColor,
          title: const Text(
            'Remove Lock',
            style: TextStyle(color: _labelColor),
          ),
          content: Text(
            'This factory-resets "${lock.displayName}" over Bluetooth, '
            'then removes it from this device. Stay near the lock.',
            style: const TextStyle(color: _subtextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF2020),
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: _cardColor,
            content: const Row(
              children: [
                CircularProgressIndicator(color: _accentColor),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Resetting lock...',
                    style: TextStyle(color: _labelColor),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    final result = await LockConnectionHelper.removeLock(
      deviceId: lock.id,
      wipeLocal: () => _forgetLockLocally(lock),
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    switch (result) {
      case LockHardwareResetResult.success:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${lock.displayName} was reset and removed.'),
            backgroundColor: _accentColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      case LockHardwareResetResult.unreachable:
        await _offerForceRemove(lock);
      case LockHardwareResetResult.rejected:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The lock could not be reset. It was not removed so you '
              'are not locked out.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _offerForceRemove(SavedLock lock) async {
    final force = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _cardColor,
          title: const Text(
            'Lock Unreachable',
            style: TextStyle(color: _labelColor),
          ),
          content: const Text(
            'Lock is unreachable. Force removing will require a manual '
            'hardware reset on the padlock itself.',
            style: TextStyle(color: _subtextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF2020),
              ),
              child: const Text('Force Remove'),
            ),
          ],
        );
      },
    );

    if (force != true || !mounted) return;

    await LockConnectionHelper.removeLock(
      deviceId: lock.id,
      wipeLocal: () => _forgetLockLocally(lock),
      force: true,
    );
  }

  Future<void> _handleLockReorder(int oldIndex, int newIndex) async {
    await ref
        .read(savedLocksProvider.notifier)
        .reorderLocks(oldIndex, newIndex, indicesAdjusted: true);

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _togglePin(SavedLock lock) async {
    await ref.read(savedLocksProvider.notifier).setLockPinned(
          lock.id,
          !lock.isPinned,
        );
  }

  Future<void> _showLockMenu(SavedLock lock) async {
    final action = await showModalBottomSheet<_LockMenuAction>(
      context: context,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.pencilSimple,
                  color: _labelColor,
                ),
                title: const Text(
                  'Rename',
                  style: TextStyle(color: _labelColor),
                ),
                subtitle: const Text(
                  'Bedroom, Fridge, Freezer, or any name',
                  style: TextStyle(color: _subtextColor),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_LockMenuAction.rename),
              ),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.shareNetwork,
                  color: _labelColor,
                ),
                title: const Text(
                  'Share',
                  style: TextStyle(color: _labelColor),
                ),
                subtitle: const Text(
                  'QR code and invite code',
                  style: TextStyle(color: _subtextColor),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_LockMenuAction.share),
              ),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.pushPin,
                  color: _labelColor,
                ),
                title: Text(
                  lock.isPinned ? 'Unpin' : 'Pin to top',
                  style: const TextStyle(color: _labelColor),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_LockMenuAction.pin),
              ),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.trash,
                  color: Color(0xFFFF2020),
                ),
                title: const Text(
                  'Forget on this phone',
                  style: TextStyle(color: Color(0xFFFF2020)),
                ),
                subtitle: const Text(
                  'Removes the saved lock locally. The padlock is not reset.',
                  style: TextStyle(color: _subtextColor),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_LockMenuAction.forget),
              ),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.arrowCounterClockwise,
                  color: Color(0xFFFF2020),
                ),
                title: const Text(
                  'Factory reset',
                  style: TextStyle(color: Color(0xFFFF2020)),
                ),
                subtitle: const Text(
                  'Resets the padlock over Bluetooth, then removes it here.',
                  style: TextStyle(color: _subtextColor),
                ),
                onTap: () => Navigator.of(sheetContext)
                    .pop(_LockMenuAction.factoryReset),
              ),
            ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _LockMenuAction.rename:
        await _renameLock(lock);
      case _LockMenuAction.share:
        await _shareLock(lock);
      case _LockMenuAction.pin:
        await _togglePin(lock);
      case _LockMenuAction.forget:
        await _forgetLockOnThisPhone(lock);
      case _LockMenuAction.factoryReset:
        await _removeLock(lock);
    }
  }

  /// Live percentage when this lock has a real reading, otherwise the last
  /// saved percentage above 0. `0` and `null` stay unread.
  int? _knownBatteryLevel(SavedLock lock, BleData bleState) {
    if (_isLockConnected(lock, bleState)) {
      final live = persistableBatteryLevel(bleState.batteryLevel);
      if (live != null) return live;
    }
    return persistableBatteryLevel(lock.lastBatteryLevel);
  }

  ({int? battery, int? rssi}) _lockTelemetry(SavedLock lock, BleData bleState) {
    final connected = _isLockConnected(lock, bleState);
    final rssi = connected ? bleState.rssi : lock.lastRssi;
    return (
      battery: _knownBatteryLevel(lock, bleState),
      rssi: isRssiAvailable(rssi) ? rssi : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleProvider);

    ref.listen(bleProvider, (previous, next) {
      final lockId = next.device?.remoteId.str ?? next.connectingDeviceId;

      if (lockId != null &&
          next.device != null &&
          next.token != null &&
          !next.isConnecting) {
        _markLockUnlockReady(lockId);
        if (_connectingLockId == lockId && mounted) {
          if (!_sessionLockIds.contains(lockId)) {
            _clearConnectingLockId(lockId);
          }
        }
      }
    });
    ref.listen(lockUnlockEventProvider, (previous, next) {
      if (previous == next) return;
      final activeId = ref.read(savedLocksProvider).activeLockId;
      if (activeId != null) {
        _markLockUnlockReady(activeId);
      }
    });

    final locksState = ref.watch(savedLocksProvider);
    final locks = sortLocksPinnedFirst(locksState.locks);
    final canAddLock = !locksState.isLoading;

    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/vault_bg.png'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.7),
            BlendMode.darken,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            kAppDisplayName,
            style: TextStyle(
              color: _labelColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Info',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HelpfulTipsPage(),
                  ),
                );
              },
              icon: const Icon(Icons.info_outline, color: _labelColor),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: canAddLock ? _addLock : null,
          backgroundColor: canAddLock ? _accentColor : _disabledColor,
          foregroundColor: canAddLock ? _backgroundColor : _subtextColor,
          icon: const Icon(PhosphorIconsRegular.plus),
          label: const Text('Add Lock'),
        ),
        body: locksState.isLoading && locks.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: _accentColor),
              )
            : locks.isEmpty
                ? _EmptyLocksView(onAddLock: _addLock)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: locks.length,
                    onReorderItem: _handleLockReorder,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          final t =
                              Curves.easeInOut.transform(animation.value);
                          return Material(
                            color: Colors.transparent,
                            elevation: lerpDouble(0, 8, t) ?? 0,
                            shadowColor: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                            child: child,
                          );
                        },
                      );
                    },
                    itemBuilder: (context, index) {
                      final lock = locks[index];
                      final isUnlocking = _connectingLockId == lock.id;
                      final telemetry = _lockTelemetry(lock, bleState);

                      return Padding(
                        key: ValueKey(lock.id),
                        padding: EdgeInsets.only(
                          bottom: index < locks.length - 1 ? 12 : 0,
                        ),
                        child: _LockCard(
                          lock: lock,
                          isConnected: false,
                          isSearching: false,
                          isConnecting: isUnlocking,
                          batteryLevel: telemetry.battery,
                          rssi: telemetry.rssi,
                          onTap: () {
                            print(
                              '[LockCard] InkWell onTap lockId=${lock.id} '
                              'unlocking=$isUnlocking',
                            );
                            _openLock(lock);
                          },
                          onMenuTap: () => _showLockMenu(lock),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _EmptyLocksView extends StatelessWidget {
  const _EmptyLocksView({required this.onAddLock});

  final VoidCallback onAddLock;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.lockKey,
              size: 72,
              color: Colors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 24),
            const Text(
              'No locks saved yet',
              style: TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first Bluetooth lock to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onAddLock,
              icon: const Icon(PhosphorIconsRegular.plus),
              label: const Text('Add Lock'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: const Color(0xFF1A1B1E),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockCard extends StatelessWidget {
  const _LockCard({
    required this.lock,
    required this.isConnected,
    required this.isSearching,
    required this.isConnecting,
    required this.batteryLevel,
    required this.rssi,
    required this.onTap,
    required this.onMenuTap,
  });

  final SavedLock lock;
  final bool isConnected;
  final bool isSearching;
  final bool isConnecting;
  final int? batteryLevel;
  final int? rssi;
  final VoidCallback onTap;
  final VoidCallback onMenuTap;

  static const _cardColor = Color(0xFF2C2D31);
  static const _labelColor = Color(0xFFFFFFFF);
  static const _subtextColor = Color(0xFF9E9E9E);
  static const _accentColor = Color(0xFF00E676);
  static const _lowBatteryColor = Color(0xFFEF5350);
  static const _lowBatteryTextColor = Color(0xFFFF8A80);
  static const _cardBorderRadius = 16.0;

  static const _steelBorderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF757575),
      Color(0xFFE0E0E0),
      Color(0xFF9E9E9E),
      Color(0xFFEEEEEE),
      Color(0xFF424242),
    ],
  );

  String get _connectionLabel {
    if (isConnecting) return 'Unlocking...';
    return 'Tap to open';
  }

  bool get _isBusy => !isConnected && (isConnecting || isSearching);

  Widget _buildLockAvatar() {
    const avatarRadius = 26.0;

    final avatar = CircleAvatar(
      radius: avatarRadius,
      backgroundColor: isConnected
          ? _accentColor.withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.08),
      child: Icon(
        isConnected
            ? PhosphorIconsBold.lockKey
            : PhosphorIconsRegular.lockKey,
        color: isConnected ? _accentColor : _subtextColor,
        size: 26,
      ),
    );

    if (!_isBusy) return avatar;

    return ZoAnimatedGradientBorder(
      borderRadius: avatarRadius + 2,
      borderThickness: 2.5,
      glowOpacity: 0.35,
      animationDuration: const Duration(milliseconds: 1800),
      animationCurve: Curves.linear,
      gradientColor: [
        _accentColor,
        _accentColor.withValues(alpha: 0.2),
        Colors.transparent,
        _accentColor.withValues(alpha: 0.2),
      ],
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: avatar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lowBattery = isLowBatteryLevel(batteryLevel);
    final borderWidth = lowBattery ? 2.0 : 1.0;
    final innerRadius = _cardBorderRadius - borderWidth;
    final batteryColor = lowBattery ? _lowBatteryColor : _subtextColor;

    return Container(
      padding: EdgeInsets.all(borderWidth),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardBorderRadius),
        gradient: lowBattery ? null : _steelBorderGradient,
        color: lowBattery ? _lowBatteryColor : null,
      ),
      child: Material(
        color: _cardColor,
        borderRadius: BorderRadius.circular(innerRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _isBusy
              ? () {
                  print(
                    '[LockCard] tap ignored (busy) lockId=${lock.id} '
                    'isConnecting=$isConnecting isSearching=$isSearching',
                  );
                }
              : onTap,
          borderRadius: BorderRadius.circular(innerRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildLockAvatar(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  lock.displayName,
                                  style: const TextStyle(
                                    color: _labelColor,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (lock.isPinned) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  PhosphorIconsRegular.pushPin,
                                  size: 14,
                                  color: _subtextColor,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            lock.hardwareName ?? lock.id,
                            style: const TextStyle(
                              color: _subtextColor,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (isConnecting)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _accentColor,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _connectionLabel,
                                      style: const TextStyle(
                                        color: _accentColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                _LockDetailChip(
                                  icon: PhosphorIconsRegular.bluetoothSlash,
                                  label: _connectionLabel,
                                  color: _subtextColor,
                                ),
                              if (batteryLevel != null)
                                _LockDetailChip(
                                  icon: PhosphorIconsRegular.batteryHigh,
                                  label: '$batteryLevel%',
                                  color: batteryColor,
                                ),
                              if (isConnected && rssi != null)
                                _LockDetailChip(
                                  icon: PhosphorIconsRegular.cellSignalHigh,
                                  label: formatRssiWithLabel(rssi!),
                                  color: _subtextColor,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onMenuTap,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        PhosphorIconsRegular.dotsThreeVertical,
                        color: _labelColor,
                      ),
                    ),
                  ],
                ),
                if (lowBattery) ...[
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Icon(
                        PhosphorIconsRegular.warning,
                        size: 15,
                        color: _lowBatteryColor,
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Low battery — charge soon',
                          style: TextStyle(
                            color: _lowBatteryTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LockDetailChip extends StatelessWidget {
  const _LockDetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
