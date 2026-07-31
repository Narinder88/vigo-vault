import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class SmartLockBattery extends ConsumerWidget {
  const SmartLockBattery(this.batteryLevel, {super.key});

  final int batteryLevel;

  ({PhosphorIconData iconData, Color color}) getBatteryLevelAndColor(int level) {
    if (level == 100) {
      return (iconData: PhosphorIcons.batteryFull, color: Colors.green);
    }

    if (level == 0) {
      return (
        iconData: PhosphorIcons.batteryEmpty,
        color: Colors.black45
      );
    }

    if (level >= 80) {
      return (iconData: PhosphorIcons.batteryHigh, color: Colors.blue);
    }

    if (level > 20) {
      return (iconData: PhosphorIcons.batteryMedium, color: Colors.blue);
    }

    return (iconData: PhosphorIcons.batteryLow, color: Colors.red);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formattedBatteryLevel = max(batteryLevel, 0);
    final levelMetadata = getBatteryLevelAndColor(formattedBatteryLevel);
    return Row(
      children: [
        PhosphorIcon(
          levelMetadata.iconData,
          color: levelMetadata.color,
        ),
        Padding(
          padding: EdgeInsets.only(left: 8),
          child: Text(
            '$formattedBatteryLevel%',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: levelMetadata.color,
            ),
          ),
        ),
      ],
    );
  }
}
