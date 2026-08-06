import 'dart:async';

import 'package:fitness_snack_lock/constants/app_branding.dart';
import 'package:fitness_snack_lock/features/device/device_scanning_page/device_scanning_page.dart';
import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/providers/in_app_review_provider.dart';
import 'package:fitness_snack_lock/providers/lock_unlock_event_provider.dart';
import 'package:fitness_snack_lock/providers/notification_manager_provider.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/widgets/smart_lock_connector.dart';
import 'package:fitness_snack_lock/widgets/rename_lock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../services/ble_service.dart';
import '../../services/lock_connection_helper.dart';
import '../../services/pairing_service.dart';
import '../../utils/rssi_utils.dart';
import '../../widgets/claim_lock_dialog.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({
    super.key,
    required this.onUnlockSuccess,
    this.lockDeviceId,
    this.onBackToDashboard,
  });

  final VoidCallback onUnlockSuccess;
  final String? lockDeviceId;
  final VoidCallback? onBackToDashboard;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with TickerProviderStateMixin {
  static const _backgroundColor = Color(0xFF1A1B1E);
  static const _lockedColor = Color(0xFFFF2020);
  static const _unlockedColor = Color(0xFF00E676);
  static const _labelColor = Color(0xFFFFFFFF);
  static const _subtextColor = Color(0xFF9E9E9E);
  static const _defaultLockTitle = kAppDisplayName;
  static const _defaultDeviceLabel = 'Main Lock';

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isUnlocked = false;
  bool _isUnlocking = false;

  late AnimationController _pulseController;
  late AnimationController _spinController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureLockSessionReady());
    });
  }

  Future<void> _ensureLockSessionReady() async {
    final lockId = widget.lockDeviceId;
    if (lockId == null || lockId.isEmpty || !mounted) return;
    if (BleService.isDeviceConnected(lockId)) return;

    await LockConnectionHelper.connectAndRestoreSession(
      deviceId: lockId,
      bleNotifier: ref.read(bleProvider.notifier),
      locksNotifier: ref.read(savedLocksProvider.notifier),
      notificationManager: ref.read(notificationManagerProvider.notifier),
      background: true,
    );
  }

  String _unlockTargetId(BluetoothDevice device) {
    return widget.lockDeviceId ?? device.remoteId.str;
  }

  String? _resolvedLockId(BluetoothDevice? device) {
    return widget.lockDeviceId ?? device?.remoteId.str;
  }

  String? _savedDisplayName(String? lockId) {
    if (lockId == null) return null;
    return ref.read(savedLocksProvider.notifier).lockById(lockId)?.displayName;
  }

  String _headerTitle(BluetoothDevice? device, BleData bleState) {
    final savedName = _savedDisplayName(_resolvedLockId(device));
    if (savedName != null && savedName.isNotEmpty) return savedName;

    final customName = bleState.customDeviceName;
    if (customName != null && customName.isNotEmpty) return customName;
    if (device != null) return _hardwareName(device);
    return _defaultLockTitle;
  }

  String _deviceLabel(BleData bleState, {BluetoothDevice? device}) {
    final savedName = _savedDisplayName(_resolvedLockId(device));
    if (savedName != null && savedName.isNotEmpty) return savedName;
    return bleState.customDeviceName ?? _defaultDeviceLabel;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  String _hardwareName(BluetoothDevice device) {
    if (device.advName.isNotEmpty) return device.advName;
    if (device.platformName.isNotEmpty) return device.platformName;
    return _defaultLockTitle;
  }

  Future<void> _saveCustomDeviceName(String name) async {
    final lockId = widget.lockDeviceId ?? ref.read(bleProvider).device?.remoteId.str;
    if (lockId == null) return;

    ref.read(bleProvider.notifier).setCustomDeviceName(name);
    await ref.read(savedLocksProvider.notifier).renameLock(lockId, name.trim());
  }

  Future<void> _closeDrawerIfOpen() async {
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState == null || !scaffoldState.isDrawerOpen) return;

    scaffoldState.closeDrawer();
    await Future<void>.delayed(const Duration(milliseconds: 260));
  }

  Future<void> _showRenameDialog() async {
    await _closeDrawerIfOpen();
    if (!mounted) return;

    final lockId =
        widget.lockDeviceId ?? ref.read(bleProvider).device?.remoteId.str;
    final savedName = lockId != null
        ? ref.read(savedLocksProvider.notifier).lockById(lockId)?.displayName
        : null;
    final currentName = savedName ??
        ref.read(bleProvider).customDeviceName ??
        _defaultDeviceLabel;

    final newName = await showRenameLockDialog(
      context: context,
      initialName: currentName,
      title: 'Rename Device',
      accentColor: _unlockedColor,
    );

    if (!mounted || newName == null || newName.isEmpty) return;

    await _saveCustomDeviceName(newName);
  }

  Future<void> _showAboutDialog() async {
    await _closeDrawerIfOpen();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2D31),
          title: Text(
            'About $kAppDisplayName',
            style: const TextStyle(color: _labelColor),
          ),
          content: Text(
            '$kAppDisplayName connects to your Bluetooth padlock for secure, '
            'convenient access. Manage your lock name, monitor battery '
            'level, and unlock from the home screen.',
            style: const TextStyle(
              color: _subtextColor,
              height: 1.45,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: _unlockedColor,
                foregroundColor: _backgroundColor,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _startUnlockAnimation() {
    _pulseController.repeat(reverse: true);
    _spinController.repeat();
  }

  void _stopUnlockAnimation() {
    _pulseController.stop();
    _pulseController.reset();
    _spinController.stop();
    _spinController.reset();
  }

  Future<void> _handleLockTap(BluetoothDevice device) async {
    if (_isUnlocking) return;

    final lockId = _unlockTargetId(device);
    if (lockId.isEmpty) return;

    setState(() => _isUnlocking = true);
    _startUnlockAnimation();

    try {
      final isUnlocked = await LockConnectionHelper.triggerUnlock(lockId);

      if (!mounted) return;

      if (isUnlocked) {
        setState(() => _isUnlocked = true);
        widget.onUnlockSuccess();
        notifyLockUnlockSuccess(ref);
        ref.read(bleProvider.notifier).endConnecting();
        await ref.read(inAppReviewProvider.notifier).countUp();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Connection timed out or unlock failed. Move closer to the lock and try again.',
            ),
            backgroundColor: _lockedColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on LockAuthenticationException {
      if (!mounted) return;
      await showLockAuthenticationDialog(context);
    } on PairingRequiredException {
      if (!mounted) return;
      await showPairingRequiredDialog(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Failed to unlock. Please ensure you are in range and try again.',
          ),
          backgroundColor: _lockedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _stopUnlockAnimation();
      if (mounted) {
        setState(() => _isUnlocking = false);
      }
    }
  }

  Widget _buildDrawer(BluetoothDevice? device, BleData bleState) {
    final isConnected = device != null;
    final battery = bleState.batteryLevel > 0 ? bleState.batteryLevel : 0;
    final rssi = bleState.rssi;
    final deviceLabel = _deviceLabel(bleState, device: device);

    return Drawer(
      backgroundColor: const Color(0xFF1A1B1E),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF2C2D31),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(
                    PhosphorIconsRegular.gear,
                    color: _labelColor,
                    size: 28,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$kAppDisplayName Settings',
                    style: const TextStyle(
                      color: _labelColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(
                PhosphorIconsRegular.pencilSimple,
                color: _labelColor,
              ),
              title: const Text(
                'Rename Device',
                style: TextStyle(color: _labelColor),
              ),
              subtitle: Text(
                deviceLabel,
                style: const TextStyle(color: _subtextColor),
              ),
              onTap: _showRenameDialog,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'BLUETOOTH & DEVICE',
                style: TextStyle(
                  color: _subtextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                isConnected
                    ? PhosphorIconsRegular.bluetooth
                    : PhosphorIconsRegular.bluetoothSlash,
                color: isConnected ? _unlockedColor : _subtextColor,
              ),
              title: Text(
                isConnected ? 'Connected' : 'Not Connected',
                style: const TextStyle(color: _labelColor),
              ),
              subtitle: Text(
                isConnected
                    ? device.remoteId.str
                    : 'No lock paired',
                style: const TextStyle(color: _subtextColor, fontSize: 12),
              ),
            ),
            if (isConnected) ...[
              ListTile(
                dense: true,
                title: const Text(
                  'Hardware Name',
                  style: TextStyle(color: _subtextColor, fontSize: 13),
                ),
                trailing: Text(
                  _hardwareName(device),
                  style: const TextStyle(color: _labelColor, fontSize: 13),
                ),
              ),
              ListTile(
                dense: true,
                title: const Text(
                  'Battery',
                  style: TextStyle(color: _subtextColor, fontSize: 13),
                ),
                trailing: Text(
                  '$battery%',
                  style: const TextStyle(color: _labelColor, fontSize: 13),
                ),
              ),
              ListTile(
                dense: true,
                title: const Text(
                  'Signal (RSSI)',
                  style: TextStyle(color: _subtextColor, fontSize: 13),
                ),
                trailing: Text(
                  isRssiAvailable(rssi)
                      ? formatRssiDisplay(rssi)
                      : kRssiDisconnectedLabel,
                  style: TextStyle(
                    color: isRssiAvailable(rssi)
                        ? _labelColor
                        : _subtextColor,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            const Spacer(),
            ListTile(
              leading: const Icon(
                PhosphorIconsRegular.info,
                color: _labelColor,
              ),
              title: const Text(
                'About',
                style: TextStyle(color: _labelColor),
              ),
              onTap: _showAboutDialog,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(lockUnlockEventProvider, (previous, next) {
      if (previous == next) return;
      _stopUnlockAnimation();
      if (mounted) {
        setState(() {
          _isUnlocked = true;
          _isUnlocking = false;
        });
      }
    });

    ref.watch(savedLocksProvider);
    final bleState = ref.watch(bleProvider);
    final lockId = widget.lockDeviceId;
    final savedLock =
        lockId != null ? ref.read(savedLocksProvider.notifier).lockById(lockId) : null;

    return SmartLockConnector(
      fallbackDeviceId: lockId,
      fallbackBatteryLevel: savedLock?.lastBatteryLevel,
      onConnectedBuilder: (context, device, batteryLevel) {
        final displayBattery = batteryLevel > 0 ? batteryLevel : 0;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _backgroundColor,
          drawer: _buildDrawer(device, bleState),
          body: SafeArea(
            child: Column(
              children: [
                _LockScreenHeader(
                  title: _headerTitle(device, bleState),
                  onMenuTap: _openDrawer,
                  onBackTap: widget.onBackToDashboard,
                ),
                _LockSubHeader(
                  deviceLabel: _deviceLabel(bleState, device: device).toUpperCase(),
                  batteryLevel: displayBattery,
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CentralLockButton(
                          isUnlocked: _isUnlocked,
                          isUnlocking: _isUnlocking,
                          pulseAnimation: _pulseAnimation,
                          spinController: _spinController,
                          onTap: () => _handleLockTap(device),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      onDisconnectedBuilder: (context) => Scaffold(
        key: _scaffoldKey,
        backgroundColor: _backgroundColor,
        drawer: _buildDrawer(null, bleState),
        body: SafeArea(
          child: Column(
            children: [
              _LockScreenHeader(
                title: _headerTitle(null, bleState),
                onMenuTap: _openDrawer,
                onBackTap: widget.onBackToDashboard,
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIconsRegular.bluetoothSlash,
                        size: 64,
                        color: _subtextColor,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'No padlock connected yet',
                        style: TextStyle(
                          color: _labelColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Connect a lock to get started',
                        style: TextStyle(
                          color: _subtextColor,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: widget.lockDeviceId == null
                            ? () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        const DeviceScanningPage(
                                      fromDashboard: true,
                                    ),
                                  ),
                                );
                                if (mounted) setState(() {});
                              }
                            : () async {
                                final restored =
                                    await LockConnectionHelper
                                        .connectAndRestoreSession(
                                  deviceId: widget.lockDeviceId!,
                                  bleNotifier:
                                      ref.read(bleProvider.notifier),
                                  locksNotifier: ref
                                      .read(savedLocksProvider.notifier),
                                  notificationManager: ref.read(
                                    notificationManagerProvider.notifier,
                                  ),
                                );
                                if (mounted) setState(() {});
                                if (!restored && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not reconnect. Move closer to the lock and try again.',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        icon: Icon(
                          widget.lockDeviceId == null
                              ? PhosphorIconsRegular.bluetooth
                              : PhosphorIconsRegular.arrowsClockwise,
                        ),
                        label: Text(
                          widget.lockDeviceId == null
                              ? 'Connect Lock'
                              : 'Reconnect',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _unlockedColor,
                          foregroundColor: _backgroundColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockScreenHeader extends StatelessWidget {
  const _LockScreenHeader({
    required this.title,
    required this.onMenuTap,
    this.onBackTap,
  });

  final String title;
  final VoidCallback onMenuTap;
  final VoidCallback? onBackTap;

  static const _labelColor = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBackTap ?? onMenuTap,
            icon: Icon(
              onBackTap != null
                  ? PhosphorIconsRegular.arrowLeft
                  : PhosphorIconsRegular.list,
              color: _labelColor,
              size: 24,
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _labelColor,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          IconButton(
            onPressed: onBackTap != null ? onMenuTap : null,
            icon: Icon(
              onBackTap != null
                  ? PhosphorIconsRegular.list
                  : PhosphorIconsRegular.lockKey,
              color: _labelColor,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockSubHeader extends StatelessWidget {
  const _LockSubHeader({
    required this.deviceLabel,
    required this.batteryLevel,
  });

  final String deviceLabel;
  final int batteryLevel;

  static const _labelColor = Color(0xFFFFFFFF);
  static const _subtextColor = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              deviceLabel,
              style: const TextStyle(
                color: _subtextColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                PhosphorIconsRegular.batteryHigh,
                color: _labelColor,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                '$batteryLevel%',
                style: const TextStyle(
                  color: _labelColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              const Icon(
                PhosphorIconsRegular.bluetooth,
                color: _labelColor,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CentralLockButton extends StatelessWidget {
  const _CentralLockButton({
    required this.isUnlocked,
    required this.isUnlocking,
    required this.pulseAnimation,
    required this.spinController,
    required this.onTap,
  });

  static const _lockedColor = Color(0xFFFF2020);
  static const _unlockedColor = Color(0xFF00E676);
  static const _buttonSize = 200.0;

  final bool isUnlocked;
  final bool isUnlocking;
  final Animation<double> pulseAnimation;
  final AnimationController spinController;
  final VoidCallback onTap;

  Color get _stateColor => isUnlocked ? _unlockedColor : _lockedColor;

  String get _label => isUnlocked ? 'Lock Open' : 'Lock Closed';

  Gradient _metalGradient() {
    final tint = _stateColor;
    return SweepGradient(
      center: Alignment.center,
      startAngle: 0.8,
      endAngle: 6.5,
      colors: [
        const Color(0xFF1C1C1E),
        Color.lerp(const Color(0xFF2A2A2E), tint, 0.18)!,
        const Color(0xFF0A0A0C),
        const Color(0xFF3D3D42),
        Color.lerp(const Color(0xFF141416), tint, 0.12)!,
        const Color(0xFF252528),
        const Color(0xFF1C1C1E),
      ],
      stops: const [0.0, 0.18, 0.34, 0.52, 0.68, 0.84, 1.0],
    );
  }

  List<BoxShadow> _neonGlow() {
    return [
      BoxShadow(
        color: _stateColor.withValues(alpha: 0.75),
        blurRadius: 28,
        spreadRadius: 2,
      ),
      BoxShadow(
        color: _stateColor.withValues(alpha: 0.45),
        blurRadius: 56,
        spreadRadius: 10,
      ),
      BoxShadow(
        color: _stateColor.withValues(alpha: 0.22),
        blurRadius: 96,
        spreadRadius: 22,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: isUnlocking ? null : onTap,
          child: AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, child) {
              final scale = isUnlocking ? pulseAnimation.value : 1.0;
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: SizedBox(
              width: _buttonSize + 48,
              height: _buttonSize + 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isUnlocking)
                    Container(
                      width: _buttonSize + 32,
                      height: _buttonSize + 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _stateColor.withValues(alpha: 0.12),
                      ),
                    ),
                  Container(
                    width: _buttonSize,
                    height: _buttonSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _metalGradient(),
                      boxShadow: _neonGlow(),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.5,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          margin: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: const Alignment(-0.35, -0.45),
                              radius: 1.1,
                              colors: [
                                Colors.white.withValues(alpha: 0.14),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.35),
                              ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _stateColor.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                        ),
                        if (isUnlocking)
                          RotationTransition(
                            turns: spinController,
                            child: Icon(
                              PhosphorIconsRegular.circleNotch,
                              color: _stateColor,
                              size: 58,
                            ),
                          )
                        else
                          Icon(
                            isUnlocked
                                ? PhosphorIconsRegular.lockOpen
                                : PhosphorIconsRegular.lockKey,
                            color: Colors.white.withValues(alpha: 0.92),
                            size: 58,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          _label,
          style: TextStyle(
            color: _stateColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            shadows: [
              Shadow(
                color: _stateColor.withValues(alpha: 0.55),
                blurRadius: 12,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
