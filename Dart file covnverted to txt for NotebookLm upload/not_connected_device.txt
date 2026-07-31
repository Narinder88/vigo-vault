import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../constants/colors.dart';

class NotConnectedDevice extends ConsumerWidget {
  const NotConnectedDevice({
    super.key,
    required this.onConnect,
  });

  final Function(BluetoothDevice connected) onConnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 80,
            child: PhosphorIcon(
              PhosphorIconsDuotone.empty,
              size: 64,
              color: AppColors.kPrimaryColor.withOpacity(0.5),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 24, bottom: 12),
            child: Text('No Smart Locks connect yet!'),
          ),
          SizedBox(
            width: 200,
            child: FilledButton(
              onPressed: () async {
                ref.read(bleProvider.notifier).reset();
                final result =
                    await DeviceScanningRoute().push<BluetoothDevice?>(context);

                if (result != null) {
                  onConnect(result);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.kPrimaryColor,
              ),
              child: const Text('Scan'),
            ),
          )
        ],
      ),
    );
  }
}
