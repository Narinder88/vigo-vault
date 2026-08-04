import 'package:flutter/material.dart';

/// Shown when an unlock attempt is blocked because the lock is not saved locally.
Future<void> showPairingRequiredDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Lock Not Saved'),
        content: const Text(
          'This lock has not been connected on this device yet. '
          'Scan and connect to the lock first.',
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

/// Shown when the lock rejects the unlock command.
Future<void> showLockAuthenticationDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Unlock Failed'),
        content: const Text(
          'The lock rejected the unlock command. Move closer to the lock and try again.',
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
