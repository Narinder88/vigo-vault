import 'package:fitness_snack_lock/providers/notification_manager_provider.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/ble_connection_monitor.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/lock_connection_helper.dart';
import 'package:fitness_snack_lock/utils/rssi_utils.dart';
import 'package:fitness_snack_lock/widgets/smart_lock_rssi_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../constants/colors.dart';
import '../../../providers/ble_provider.dart';
import '../../../widgets/smart_lock_battery.dart';
import 'updates_countdown.dart';

class ConnectedDevice extends ConsumerStatefulWidget {
  const ConnectedDevice({
    super.key,
    required this.onDisconnect,
    required this.device,
    required this.batteryLevel,
  });

  final BluetoothDevice device;
  final VoidCallback onDisconnect;
  final int batteryLevel;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ConnectedDeviceState();
}

class _ConnectedDeviceState extends ConsumerState<ConnectedDevice> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LockConnectionHelper.connectAndRestoreSession(
        deviceId: widget.device.remoteId.str,
        bleNotifier: ref.read(bleProvider.notifier),
        locksNotifier: ref.read(savedLocksProvider.notifier),
        notificationManager:
            ref.read(notificationManagerProvider.notifier),
        switchConnection: false,
      );
    });
  }

  Future<void> _handleManualDisconnect(String deviceId) async {
    BleConnectionMonitor.stopMonitoring();
    await BleService.resetDeviceConnection(deviceId);
    ref.read(bleProvider.notifier).clearSession();
    widget.onDisconnect();
  }

  Future<void> _handleReconnect(String deviceId) async {
    final restored = await LockConnectionHelper.connectAndRestoreSession(
      deviceId: deviceId,
      bleNotifier: ref.read(bleProvider.notifier),
      locksNotifier: ref.read(savedLocksProvider.notifier),
      notificationManager: ref.read(notificationManagerProvider.notifier),
    );

    if (!restored && mounted) {
      ref.read(bleProvider.notifier).clearSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleProvider);
    final deviceId = widget.device.remoteId.str;
    final displayName = widget.device.advName.isNotEmpty
        ? widget.device.advName
        : 'BR38';
    final isConnected = BleService.isDeviceConnected(deviceId);

    return Column(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const UpdatesCountdown(),
              Padding(
                padding: const EdgeInsets.only(top: 32, bottom: 12),
                child: Text(
                  'Smart Lock: $displayName',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isConnected ? 'Connected' : kRssiDisconnectedLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      PhosphorIconsBold.dot,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  SmartLockBattery(
                    isConnected && bleState.batteryLevel > 0
                        ? bleState.batteryLevel
                        : widget.batteryLevel,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      PhosphorIconsBold.dot,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SmartLockRssiReader(),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (isConnected) {
                      await _handleManualDisconnect(deviceId);
                    } else {
                      await _handleReconnect(deviceId);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.kPrimaryColor,
                  ),
                  child: Text(isConnected ? 'Disconnect' : 'Reconnect'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
