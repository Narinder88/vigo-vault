import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:fitness_snack_lock/constants/app_branding.dart';
import 'package:fitness_snack_lock/features/device/device_scanning_page/device_scanning_page.dart';
import 'package:fitness_snack_lock/features/lock/home_page.dart';
import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/providers/lock_unlock_event_provider.dart';
import 'package:fitness_snack_lock/providers/notification_manager_provider.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/ble_connection_monitor.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/lock_connection_helper.dart';
import 'package:fitness_snack_lock/services/saved_lock_storage.dart';
import 'package:fitness_snack_lock/utils/rssi_utils.dart';
import 'package:fitness_snack_lock/widgets/rename_lock_dialog.dart';
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

enum _LockMenuAction { rename, setPrimary, remove }

class _DeviceDashboardPageState extends ConsumerState<DeviceDashboardPage> {
  static const _backgroundColor = Color(0xFF1A1B1E);
  static const _cardColor = Color(0xFF2C2D31);
  static const _labelColor = Color(0xFFFFFFFF);
  static const _subtextColor = Color(0xFF9E9E9E);
  static const _accentColor = Color(0xFF00E676);
  static const _disabledColor = Color(0xFF5C5D62);

  String? _connectingLockId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeDashboardBle();
    });
  }

  Future<void> _initializeDashboardBle() async {
    await _releaseStaleBleSessions();
    await _attemptPrimaryLockReconnect();
  }

  Future<String?> _resolvePrimaryLockId() async {
    final locksState = ref.read(savedLocksProvider);
    if (locksState.primaryLockId != null) {
      return locksState.primaryLockId;
    }
    if (locksState.activeLockId != null) {
      return locksState.activeLockId;
    }
    if (locksState.locks.isNotEmpty) {
      return locksState.locks.first.id;
    }

    return await SavedLockStorage.getPrimaryLockId() ??
        await SavedLockStorage.getActiveLockId();
  }

  Future<void> _attemptPrimaryLockReconnect() async {
    final lockId = await _resolvePrimaryLockId();
    if (lockId == null || lockId.isEmpty || !mounted) return;

    if (BleService.isDeviceConnected(lockId)) return;

    setState(() => _connectingLockId = lockId);
    final bleNotifier = ref.read(bleProvider.notifier);

    try {
      await LockConnectionHelper.connectAndRestoreSession(
        deviceId: lockId,
        bleNotifier: bleNotifier,
        locksNotifier: ref.read(savedLocksProvider.notifier),
        notificationManager: ref.read(notificationManagerProvider.notifier),
        background: true,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } finally {
      if (mounted) {
        setState(() => _connectingLockId = null);
      }
      if (bleNotifier.value.isConnecting) {
        bleNotifier.endConnecting();
      }
    }
  }

  void _resetBusyConnectionState() {
    final bleNotifier = ref.read(bleProvider.notifier);
    if (bleNotifier.value.isConnecting) {
      bleNotifier.endConnecting();
    }
    if (_connectingLockId != null) {
      setState(() => _connectingLockId = null);
    }
  }

  Future<void> _releaseStaleBleSessions() async {
    final bleState = ref.read(bleProvider);
    final device = bleState.device;
    final locksNotifier = ref.read(savedLocksProvider.notifier);
    final knownIds = locksNotifier.allDeviceIds;

    if (device != null) {
      await BleService.releaseOnDemandConnection(device.remoteId.str);
    } else if (knownIds.isNotEmpty) {
      await BleService.releaseAllActiveConnections(knownDeviceIds: knownIds);
    }

    ref.read(bleProvider.notifier).clearSession();
    BleConnectionMonitor.stopMonitoring();
  }

  Future<void> _openLock(SavedLock lock) async {
    final bleState = ref.read(bleProvider);
    if (_connectingLockId != null || bleState.isConnecting) return;

    setState(() => _connectingLockId = lock.id);
    final bleNotifier = ref.read(bleProvider.notifier);

    try {
      await ref.read(savedLocksProvider.notifier).setActiveLockId(lock.id);

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => LockControlPage(lockId: lock.id),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open lock. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _connectingLockId = null);
      }
      if (bleNotifier.value.isConnecting) {
        bleNotifier.endConnecting();
      }
    }

    if (!mounted) return;
  }

  Future<void> _addLock() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => const DeviceScanningPage(fromDashboard: true),
      ),
    );

    if (!mounted || added != true) return;

    final activeId = ref.read(savedLocksProvider).activeLockId;
    if (activeId == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LockControlPage(lockId: activeId),
      ),
    );

    if (!mounted) return;
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
    if (activeDevice?.remoteId.str == lock.id) {
      ref.read(bleProvider.notifier).setCustomDeviceName(newName);
    }
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
            'Remove "${lock.displayName}" from your saved locks?',
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

    if (confirmed != true) return;

    final activeDevice = ref.read(bleProvider).device;
    if (activeDevice?.remoteId.str == lock.id) {
      await BleService.disconnectDevice(lock.id);
      ref.read(bleProvider.notifier).reset();
    } else {
      BleService.clearDeviceSession(lock.id);
    }

    await ref.read(savedLocksProvider.notifier).removeLock(lock.id);
  }

  Future<void> _reconnectPrimaryInBackground() async {
    await _releaseStaleBleSessions();
  }

  Future<void> _setAsPrimaryLock(SavedLock lock) async {
    final locksNotifier = ref.read(savedLocksProvider.notifier);
    if (locksNotifier.isPrimaryLock(lock.id)) return;

    await locksNotifier.setPrimaryLockId(lock.id);
    await _reconnectPrimaryInBackground();

    if (!mounted) return;
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${lock.displayName} is now your primary lock.'),
        backgroundColor: _accentColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleLockReorder(int oldIndex, int newIndex) async {
    final changedPrimaryId = await ref
        .read(savedLocksProvider.notifier)
        .reorderLocks(oldIndex, newIndex, indicesAdjusted: true);

    if (!mounted) return;

    if (changedPrimaryId != null) {
      await _reconnectPrimaryInBackground();
    }

    setState(() {});
  }

  Future<void> _showLockMenu(SavedLock lock) async {
    final isPrimary = ref.read(savedLocksProvider.notifier).isPrimaryLock(lock.id);

    final action = await showModalBottomSheet<_LockMenuAction>(
      context: context,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
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
                onTap: () =>
                    Navigator.of(sheetContext).pop(_LockMenuAction.rename),
              ),
              if (!isPrimary)
                ListTile(
                  leading: const Icon(
                    PhosphorIconsRegular.star,
                    color: _accentColor,
                  ),
                  title: const Text(
                    'Set as Primary',
                    style: TextStyle(color: _labelColor),
                  ),
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_LockMenuAction.setPrimary),
                ),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.trash,
                  color: Color(0xFFFF2020),
                ),
                title: const Text(
                  'Remove',
                  style: TextStyle(color: Color(0xFFFF2020)),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_LockMenuAction.remove),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _LockMenuAction.rename:
        await _renameLock(lock);
      case _LockMenuAction.setPrimary:
        await _setAsPrimaryLock(lock);
      case _LockMenuAction.remove:
        await _removeLock(lock);
    }
  }

  bool _isLockConnected(SavedLock lock) => BleService.isDeviceConnected(lock.id);

  ({int? battery, int? rssi}) _lockTelemetry(SavedLock lock) {
    final bleState = ref.watch(bleProvider);
    if (_isLockConnected(lock)) {
      return (
        battery: bleState.batteryLevel > 0 ? bleState.batteryLevel : null,
        rssi: isRssiAvailable(bleState.rssi) ? bleState.rssi : null,
      );
    }

    return (
      battery: lock.lastBatteryLevel,
      rssi: isRssiAvailable(lock.lastRssi) ? lock.lastRssi : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bleProvider, (previous, next) {
      if (previous?.isConnecting == true && !next.isConnecting) {
        _resetBusyConnectionState();
      }
    });
    ref.listen(lockUnlockEventProvider, (previous, next) {
      if (previous == next) return;
      _resetBusyConnectionState();
      ref.read(bleProvider.notifier).endConnecting();
    });

    final locksState = ref.watch(savedLocksProvider);
    final locks = locksState.locks;
    final canAddLock = !locksState.isLoading && locks.isEmpty;

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
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: canAddLock ? _addLock : null,
          backgroundColor: canAddLock ? _accentColor : _disabledColor,
          foregroundColor: canAddLock ? _backgroundColor : _subtextColor,
          icon: const Icon(PhosphorIconsRegular.plus),
          label: const Text('Add Lock'),
        ),
        body: locksState.isLoading
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
                          final t = Curves.easeInOut.transform(animation.value);
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
                      final isConnected = _isLockConnected(lock);
                      final isSearching = false;
                      final isConnecting = _connectingLockId == lock.id ||
                          ref.watch(bleProvider).isConnecting;
                      final telemetry = _lockTelemetry(lock);

                      return Padding(
                        key: ValueKey(lock.id),
                        padding: EdgeInsets.only(
                          bottom: index < locks.length - 1 ? 12 : 0,
                        ),
                        child: _LockCard(
                          lock: lock,
                          isConnected: isConnected,
                          isSearching: isSearching,
                          isConnecting: isConnecting,
                          batteryLevel: telemetry.battery,
                          rssi: telemetry.rssi,
                          onTap: () => _openLock(lock),
                          onMenuTap: () => _showLockMenu(lock),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class LockControlPage extends ConsumerWidget {
  const LockControlPage({
    super.key,
    required this.lockId,
  });

  final String lockId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1B1E),
      body: HomePage(
        lockDeviceId: lockId,
        onUnlockSuccess: () {
          debugPrint('Lock unlocked successfully!');
        },
        onBackToDashboard: () {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
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
    if (isConnecting) return 'Connecting...';
    if (isSearching) return 'Searching...';
    if (isConnected) return 'Connected';
    return 'Tap to open';
  }

  bool get _isBusy => isConnecting || isSearching;

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
    const innerRadius = _cardBorderRadius - 1;

    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardBorderRadius),
        gradient: _steelBorderGradient,
      ),
      child: Material(
        color: _cardColor,
        borderRadius: BorderRadius.circular(innerRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _isBusy ? null : onTap,
          borderRadius: BorderRadius.circular(innerRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
            children: [
              _buildLockAvatar(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lock.displayName,
                      style: const TextStyle(
                        color: _labelColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                        _LockDetailChip(
                          icon: _isBusy
                              ? PhosphorIconsRegular.circleNotch
                              : (isConnected
                                  ? PhosphorIconsRegular.bluetooth
                                  : PhosphorIconsRegular.bluetoothSlash),
                          label: _connectionLabel,
                          color: isConnected || _isBusy
                              ? _accentColor
                              : _subtextColor,
                        ),
                        if (batteryLevel != null)
                          _LockDetailChip(
                            icon: PhosphorIconsRegular.batteryHigh,
                            label: '$batteryLevel%',
                            color: _subtextColor,
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
