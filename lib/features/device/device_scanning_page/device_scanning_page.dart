import 'dart:async';

import 'package:fitness_snack_lock/constants/colors.dart';
import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/widgets/smart_lock_rssi_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:simple_ripple_animation/simple_ripple_animation.dart';

import '../../../providers/notification_manager_provider.dart';
import '../../../providers/saved_locks_provider.dart';
import '../../../services/ble_service.dart';
import '../../../services/lock_auth_service.dart';
import '../../../services/lock_connection_helper.dart';
import '../../../services/pairing_service.dart';
import '../../../widgets/claim_lock_dialog.dart';

class DeviceScanningPage extends ConsumerStatefulWidget {
  const DeviceScanningPage({
    super.key,
    this.fromDashboard = false,
  });

  final bool fromDashboard;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _DeviceScanningPageState();
}

class _DeviceScanningPageState extends ConsumerState<DeviceScanningPage> {
  StreamSubscription<List<ScanResult>>? subscription;
  final scanResultsNotifier = ValueNotifier<List<ScanResult>>([]);
  final isConnectingNotifier = ValueNotifier<bool>(false);
  bool _scanStopped = false;
  bool _connectSessionActive = false;

  @override
  void initState() {
    super.initState();

    Future.delayed(Duration.zero, () async {
      if (!mounted || _connectSessionActive || _scanStopped) return;

      await FlutterBluePlus.adapterState
          .where((val) => val == BluetoothAdapterState.on)
          .first;

      if (!mounted || _connectSessionActive || _scanStopped) return;

      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: 30),
      );
    });

    subscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        if (_connectSessionActive || !mounted) return;

        scanResultsNotifier.value = _filterScanResults(results);
      },
    );
  }

  Future<void> _ensureScanStoppedOnce() async {
    if (_scanStopped) return;

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _scanStopped = true;
  }

  void _tearDownScanning() {
    _connectSessionActive = true;

    subscription?.cancel();
    subscription = null;

    unawaited(_ensureScanStoppedOnce());
  }

  ({double? left, double? top, double? bottom, double? right}) getLockPosition(
      int index) {
    // Map first four indices to the four corners of the scanning area.
    // 0: top-left, 1: top-right, 2: bottom-left, 3: bottom-right
    switch (index % 4) {
      case 0:
        return (left: 4, top: 4, bottom: null, right: null);
      case 1:
        return (left: null, top: 4, bottom: null, right: 4);
      case 2:
        return (left: 4, top: null, bottom: 4, right: null);
      case 3:
        return (left: null, top: null, bottom: 4, right: 4);
      default:
        return (left: null, top: null, bottom: null, right: null);
    }
  }

  bool _isValidToken(String? token) {
    return LockConnectionHelper.isValidToken(token);
  }

  Set<String> _knownLockDeviceIds() {
    final savedIds = ref.read(savedLocksProvider.notifier).allDeviceIds;
    final activeDeviceId = ref.read(bleProvider).device?.remoteId.str;

    return {
      for (final id in savedIds) id,
      if (activeDeviceId != null && activeDeviceId.isNotEmpty) activeDeviceId,
    };
  }

  List<ScanResult> _filterScanResults(List<ScanResult> results) {
    final knownIds = _knownLockDeviceIds();

    return results
        .where((e) => e.advertisementData.advName.isNotEmpty)
        .where((e) => !knownIds.contains(e.device.remoteId.str))
        .toList();
  }

  bool _isDiscoverableLock(ScanResult result) {
    return result.advertisementData.advName == 'BR38' ||
        result.device.platformName == 'BR38';
  }

  List<ScanResult> _visibleScanResults(List<ScanResult> results) {
    return _filterScanResults(results).where(_isDiscoverableLock).toList();
  }

  void _dismissConnectionSheet(BuildContext sheetContext) {
    if (!sheetContext.mounted) return;

    final navigator = Navigator.of(sheetContext);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    final rootNavigator = Navigator.of(sheetContext, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
    }
  }

  Future<bool> _ensureLockClaimed({
    required String deviceId,
    required String displayName,
    required String sessionToken,
  }) async {
    final alreadyPaired = await PairingService.isPaired(deviceId);
    final hasSecret = await PairingService.hasOwnershipSecret(deviceId);
    if (alreadyPaired && hasSecret) {
      return true;
    }

    if (!mounted) return false;

    final claimed = await showClaimLockDialog(
      context,
      deviceId: deviceId,
      displayName: displayName,
    );

    if (claimed != true) {
      await BleService.resetDeviceConnection(deviceId);
      _connectSessionActive = false;
      return false;
    }

    try {
      await LockAuthService.claimAndProvisionLock(
        deviceId: deviceId,
        sessionToken: sessionToken,
      );
      return true;
    } on LockAuthenticationException {
      await BleService.resetDeviceConnection(deviceId);
      _connectSessionActive = false;
      if (!mounted) return false;
      await showLockAuthenticationDialog(context);
      return false;
    }
  }

  Future<void> _registerAndFinishConnection({
    required ScanResult scanResult,
    required String token,
    required BuildContext sheetContext,
    int? batteryLevel,
    int? rssi,
  }) async {
    final deviceId = scanResult.device.remoteId.str;
    final displayName = LockConnectionHelper.defaultDisplayName(scanResult.device);
    final hardwareName = LockConnectionHelper.hardwareName(scanResult.device);

    final claimed = await _ensureLockClaimed(
      deviceId: deviceId,
      displayName: displayName,
      sessionToken: token,
    );
    if (!claimed || !mounted) return;

    await ref.read(savedLocksProvider.notifier).registerConnectedLock(
          deviceId: deviceId,
          displayName: displayName,
          hardwareName: hardwareName,
          batteryLevel: batteryLevel,
          rssi: rssi,
        );

    ref.read(bleProvider.notifier).setConnected(
          device: scanResult.device,
          token: token,
          batteryLevel: batteryLevel,
          rssi: rssi,
          customDeviceName: displayName,
        );

    if (batteryLevel != null) {
      await ref
          .read(notificationManagerProvider.notifier)
          .createReachBatteryNotification(batteryLevel);
    }

    if (widget.fromDashboard && mounted) {
      _dismissConnectionSheet(sheetContext);
      Navigator.of(context).pop(true);
      return;
    }

    _dismissConnectionSheet(sheetContext);
  }

  void _finishSuccessfulConnection({
    required ScanResult scanResult,
    required String token,
    required BuildContext sheetContext,
    int? batteryLevel,
    int? rssi,
  }) {
    unawaited(_registerAndFinishConnection(
      scanResult: scanResult,
      token: token,
      sheetContext: sheetContext,
      batteryLevel: batteryLevel,
      rssi: rssi,
    ));
  }

  Future<({int? batteryLevel, int rssi})> _readBatteryAndRssi({
    required ScanResult scanResult,
    required String deviceId,
    required String token,
  }) {
    return LockConnectionHelper.readBatteryAndRssi(
      device: scanResult.device,
      deviceId: deviceId,
      token: token,
    );
  }

  Future<void> _connectToDevice({
    required ScanResult scanResult,
    required BuildContext sheetContext,
    required void Function() onConnectFinished,
  }) async {
    if (_connectSessionActive) return;

    _tearDownScanning();

    if (!mounted) return;

    final result =
        await BleService.connect(scanResult.device.remoteId.str);

    if (!mounted) return;

    onConnectFinished();

    if (!result) {
      _connectSessionActive = false;
      return;
    }

    final token = BleService.lastConnectToken;
    if (!_isValidToken(token)) {
      _connectSessionActive = false;
      return;
    }

    final validToken = token!;

    if (!mounted) return;

    final readings = await _readBatteryAndRssi(
      scanResult: scanResult,
      deviceId: scanResult.device.remoteId.str,
      token: validToken,
    );

    if (!mounted) return;

    if (!sheetContext.mounted) {
      await _registerAndFinishConnection(
        scanResult: scanResult,
        token: validToken,
        sheetContext: sheetContext,
        batteryLevel: readings.batteryLevel,
        rssi: readings.rssi,
      );
      return;
    }

    _finishSuccessfulConnection(
      scanResult: scanResult,
      token: validToken,
      sheetContext: sheetContext,
      batteryLevel: readings.batteryLevel,
      rssi: readings.rssi,
    );
  }

  void _setConnecting(bool value) {
    if (!mounted || _connectSessionActive) return;

    try {
      isConnectingNotifier.value = value;
      setState(() {});
    } catch (_) {
      // Ignore if the notifier was already disposed.
    }
  }

  void _resetConnectingState() {
    if (!mounted || _connectSessionActive) return;
    _setConnecting(false);
  }

  @override
  void dispose() {
    subscription?.cancel();
    isConnectingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(savedLocksProvider);
    ref.watch(bleProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: widget.fromDashboard
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(false),
              )
            : null,
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16).copyWith(bottom: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StreamBuilder<bool>(
                stream: FlutterBluePlus.isScanning,
                builder: (context, snapshot) {
                  if (_connectSessionActive) {
                    return SizedBox(
                      width: double.infinity,
                      height: 400,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.kPrimaryColor,
                        ),
                      ),
                    );
                  }

                  final isScanning = snapshot.data ?? false;

                  if (!isScanning) {
                    return Container(
                      width: double.infinity,
                      height: 400,
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 80,
                            backgroundColor: Colors.blue.shade50,
                            child: PhosphorIcon(
                              PhosphorIconsDuotone.bluetooth,
                              size: 54,
                              color: Colors.blueAccent.shade200,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 32),
                            child: Text(
                              'Do not find any Smart Lock?\nPlease try to re-scan.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Container(
                            width: 200,
                            padding: EdgeInsets.only(top: 16),
                            child: FilledButton(
                              onPressed: _connectSessionActive
                                  ? null
                                  : () async {
                                if (_scanStopped) {
                                  _scanStopped = false;
                                }

                                await FlutterBluePlus.adapterState
                                    .where((val) =>
                                        val == BluetoothAdapterState.on)
                                    .first;

                                if (!mounted || _connectSessionActive) return;

                                await FlutterBluePlus.startScan(
                                  withServices: [],
                                  timeout: Duration(seconds: 30),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.kPrimaryColor,
                              ),
                              child: Text('SCAN'),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ValueListenableBuilder(
                    valueListenable: scanResultsNotifier,
                    builder: (dialogContext, scanResults, _) {
                      return Stack(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 400,
                            child: RippleAnimation(
                              color: Colors.blue.shade300,
                              delay: const Duration(milliseconds: 300),
                              repeat: true,
                              minRadius: 75,
                              ripplesCount: 8,
                              duration: const Duration(milliseconds: 6 * 300),
                              child: PhosphorIcon(
                                PhosphorIconsDuotone.bluetooth,
                                size: 54,
                                color: Colors.blueAccent.shade200,
                              ),
                            ),
                          ),
                          ..._visibleScanResults(scanResults)
                              .asMap()
                              .entries
                              .map(
                            (entry) {
                              final idx = entry.key;
                              final e = entry.value;
                              return Positioned(
                              right: getLockPosition(idx).right,
                              left: getLockPosition(idx).left,
                              top: getLockPosition(idx).top,
                              bottom: getLockPosition(idx).bottom,
                              child: InkWell(
                                onTap: () {
                                  showCupertinoModalBottomSheet(
                                    context: context,
                                    barrierColor: Colors.black87,
                                    builder: (sheetContext) {
                                      return SafeArea(
                                        bottom: false,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Padding(
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 28),
                                              child: CircleAvatar(
                                                radius: 60,
                                                child: PhosphorIcon(
                                                  PhosphorIconsDuotone.lockKey,
                                                  size: 48,
                                                  color:
                                                      AppColors.kPrimaryColor,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              e.device.advName,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              e.device.remoteId.str,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.black26,
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 16,
                                              ).copyWith(bottom: 12, top: 8),
                                              child: SmartLockRssiReader(
                                                rssi: e.rssi,
                                              ),
                                            ),
                                            SafeArea(
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 8),
                                                child: ValueListenableBuilder(
                                                  valueListenable:
                                                      isConnectingNotifier,
                                                  builder: (buttonContext,
                                                      isConnecting, _) {
                                                    return FilledButton(
                                                      onPressed: () async {
                                                        if (isConnectingNotifier
                                                            .value) {
                                                          return;
                                                        }

                                                        _setConnecting(true);
                                                        try {
                                                          await _connectToDevice(
                                                            scanResult: e,
                                                            sheetContext:
                                                                sheetContext,
                                                            onConnectFinished:
                                                                _resetConnectingState,
                                                          );
                                                        } on TimeoutException {
                                                          _connectSessionActive =
                                                              false;
                                                        } catch (_) {
                                                          _connectSessionActive =
                                                              false;
                                                        } finally {
                                                          if (mounted &&
                                                              !_connectSessionActive) {
                                                            _resetConnectingState();
                                                          }
                                                        }
                                                      },
                                                      style:
                                                          TextButton.styleFrom(
                                                        backgroundColor:
                                                            AppColors
                                                                .kPrimaryColor,
                                                        foregroundColor:
                                                            Colors.white,
                                                      ),
                                                      child: Text(
                                                        isConnecting
                                                            ? 'Connecting...'
                                                            : 'Connect',
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            )
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Column(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor:
                                            AppColors.kPrimaryColor,
                                        child: PhosphorIcon(
                                          PhosphorIconsRegular.lockKey,
                                          size: 28,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text(
                                          "Smart Lock: ${e.device.advName.isNotEmpty ? e.device.advName : 'BR38'}",
                                          style: TextStyle(
                                            color: AppColors.kPrimaryColor,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            );
                            },
                          )
                        ],
                      );
                    },
                  );
                }),
            const Text(
              'Scanning for devices...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Please hold your phone\nnear the Smart Lock',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
