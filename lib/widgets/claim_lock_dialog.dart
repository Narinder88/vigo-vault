import 'package:fitness_snack_lock/constants/colors.dart';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Prompts the user to claim a newly discovered lock before it is saved locally.
Future<bool?> showClaimLockDialog(
  BuildContext context, {
  required String deviceId,
  required String displayName,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Claim This Lock?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: Colors.blue.shade50,
                child: PhosphorIcon(
                  PhosphorIconsDuotone.lockKey,
                  size: 32,
                  color: AppColors.kPrimaryColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Save "$displayName" to this device so only you can unlock it from this phone.',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              deviceId,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Claim Lock'),
          ),
        ],
      );
    },
  );
}

/// Shown when an unlock attempt is blocked because the lock is not paired.
Future<void> showPairingRequiredDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Lock Not Paired'),
        content: const Text(
          'This lock has not been claimed on this device. Connect and claim the lock before trying to unlock.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
