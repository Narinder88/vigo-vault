import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SmartLockConnector extends ConsumerStatefulWidget {
  const SmartLockConnector({
    super.key,
    this.device,
    this.fallbackDeviceId,
    this.fallbackBatteryLevel,
    required this.onConnectedBuilder,
    required this.onDisconnectedBuilder,
  });

  final BluetoothDevice? device;
  /// When set, shows the connected UI for a saved lock even if GATT was released.
  final String? fallbackDeviceId;
  final int? fallbackBatteryLevel;
  final Widget Function(BuildContext context, BluetoothDevice device,
      int batteryLevel) onConnectedBuilder;
  final Widget Function(BuildContext context) onDisconnectedBuilder;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _SmartLockConnectorState();
}

class _SmartLockConnectorState extends ConsumerState<SmartLockConnector> {
  BluetoothDevice? connectedDevice;

  @override
  void initState() {
    super.initState();

    if (widget.device != null) {
      if (context.mounted) {
        setState(() {
          connectedDevice = widget.device;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleProvider);
    final providerDevice = bleState.device;
    final device = providerDevice ??
        (widget.fallbackDeviceId != null
            ? BluetoothDevice.fromId(widget.fallbackDeviceId!)
            : null);
    final batteryLevel = providerDevice != null
        ? bleState.batteryLevel
        : (widget.fallbackBatteryLevel ?? 0);

    if (device != null) {
      return widget.onConnectedBuilder(
        context,
        device,
        batteryLevel,
      );
    }

    return widget.onDisconnectedBuilder(context);
  }
}
