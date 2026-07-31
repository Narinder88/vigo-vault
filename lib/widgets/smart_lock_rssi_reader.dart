import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/utils/rssi_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'signal_indicator.dart';

class SmartLockRssiReader extends ConsumerWidget {
  const SmartLockRssiReader({super.key, this.rssi});

  final int? rssi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceRssi = ref.watch(bleProvider).rssi;
    final rssiValue = rssi ?? deviceRssi;

    if (!isRssiAvailable(rssiValue)) {
      return Text(
        kRssiDisconnectedLabel,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SignalIndicator(rssi: rssiValue),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            formatRssiDisplay(rssiValue),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ),
      ],
    );
  }
}
