import 'package:fitness_snack_lock/constants/colors.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/features/device/device_connection_page/updates_countdown.dart';
import 'package:fitness_snack_lock/router.dart';
import 'package:fitness_snack_lock/utils/rssi_utils.dart';
import 'package:fitness_snack_lock/widgets/smart_lock_connector.dart';
import 'package:fitness_snack_lock/widgets/smart_lock_rssi_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../providers/ble_provider.dart';
import '../../../widgets/smart_lock_battery.dart';

class DeviceConnection extends ConsumerStatefulWidget {
  const DeviceConnection({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _DeviceConnectionState();
}

class _DeviceConnectionState extends ConsumerState<DeviceConnection> {
  Widget _renderConnected(BluetoothDevice device, int batteryLevel) {
    final isConnected = BleService.isDeviceConnected(device.remoteId.str);

    return ListTile(
      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      leading: InkWell(
        onTap: () {
          DeviceConnectionRoute().push(context);
        },
        child: CircleAvatar(
          radius: 24,
          child: Icon(
            PhosphorIconsBold.lockKey,
            color: AppColors.kPrimaryColor,
            size: 28,
          ),
        ),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Smart Lock: ${device.advName.isNotEmpty ? device.advName : 'BR38'}',
          ),
          const Spacer(),
          const UpdatesCountdown(),
          const SizedBox(width: 8),
          Text(
            isConnected ? 'Connected' : kRssiDisconnectedLabel,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isConnected ? Colors.green : Colors.red,
              fontSize: 14,
            ),
          ),
        ],
      ),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmartLockBattery(batteryLevel),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              PhosphorIconsBold.dot,
              color: Colors.grey.shade800,
            ),
          ),
          SmartLockRssiReader(),
        ],
      ),
    );
  }

  Widget _renderNotConnected() {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      leading: CircleAvatar(
        radius: 24,
        child: Icon(
          PhosphorIconsBold.empty,
          color: Colors.blueGrey,
        ),
      ),
      title: Text('Not Connect'),
      subtitle: Text('--'),
      trailing: SizedBox(
        height: 32,
        child: FilledButton(
          onPressed: () async {
            await DeviceConnectionRoute().push(context);
            setState(() {});
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.kPrimaryColor,
          ),
          child: Text('Connect'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SmartLockConnector(
      onConnectedBuilder: (context, device, batteryLevel) {
        final shouldWarningBattery = batteryLevel <= 20 && batteryLevel > 0;
        return Container(
          padding: const EdgeInsets.all(16).copyWith(bottom: 0),
          decoration: BoxDecoration(
            color: shouldWarningBattery ? Colors.red.shade50 : Colors.white,
            border: Border(
              top: BorderSide(
                width: 4,
                color: shouldWarningBattery
                    ? Colors.red.shade400
                    : Colors.transparent,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Smart Lock Connection',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(width: 8),
                  InkWell(
                    onTap: () => {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text('Battery Notes'),
                          content: Text(
                            'Battery level is displayed only at 100%, 80%, 60%, 40%, 20%, and 0%.',
                          ),
                          actionsPadding:
                              EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.kPrimaryColor,
                              ),
                              child: Text('OK'),
                            )
                          ],
                        ),
                      )
                    },
                    child: PhosphorIcon(PhosphorIconsDuotone.info),
                  ),
                  Spacer(),
                  if (shouldWarningBattery)
                    Text(
                      '(Low battery)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                      ),
                    )
                ],
              ),
              _renderConnected(device, batteryLevel),
            ],
          ),
        );
      },
      onDisconnectedBuilder: (context) => Container(
        padding: const EdgeInsets.all(16).copyWith(bottom: 0),
        decoration: BoxDecoration(
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Smart Lock Connection',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            _renderNotConnected(),
          ],
        ),
      ),
    );
  }
}
