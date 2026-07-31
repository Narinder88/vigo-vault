import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/providers/notification_manager_provider.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/router.dart';
import 'package:fitness_snack_lock/services/ble_connection_monitor.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/lock_connection_helper.dart';
import 'package:fitness_snack_lock/widgets/smart_lock_connector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connected_device.dart';
import 'not_connected_device.dart';

class DeviceConnectionPage extends ConsumerStatefulWidget {
  const DeviceConnectionPage({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _DeviceConnectionPageState();
}

class _DeviceConnectionPageState extends ConsumerState<DeviceConnectionPage> {
  @override
  Widget build(BuildContext context) {
    final connectedDevice = ref.watch(bleProvider).device;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IconButton(
            onPressed: () {
              const DeviceDashboardRoute().go(context);
            },
            icon: PhosphorIcon(PhosphorIconsBold.house),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16).copyWith(bottom: 8),
        child: SmartLockConnector(
          device: connectedDevice,
          onConnectedBuilder: (context, device, batteryLevel) {
            return ConnectedDevice(
              device: device,
              batteryLevel: batteryLevel,
              onDisconnect: () async {
                final deviceId = device.remoteId.str;
                BleConnectionMonitor.stopMonitoring();
                await BleService.resetDeviceConnection(deviceId);
                ref.read(bleProvider.notifier).clearSession();

                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('CONNECTED_DEVICE_LOCK');
              },
            );
          },
          onDisconnectedBuilder: (context) => NotConnectedDevice(
            onConnect: (device) async {
              final restored = await LockConnectionHelper.connectAndRestoreSession(
                deviceId: device.remoteId.str,
                bleNotifier: ref.read(bleProvider.notifier),
                locksNotifier: ref.read(savedLocksProvider.notifier),
                notificationManager:
                    ref.read(notificationManagerProvider.notifier),
              );

              if (!restored) {
                ref.read(bleProvider.notifier).reset();
                return;
              }

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                'CONNECTED_DEVICE_LOCK',
                device.remoteId.str,
              );
            },
          ),
        ),
      ),
    );
  }
}
