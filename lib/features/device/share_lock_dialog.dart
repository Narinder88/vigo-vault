import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

Future<void> showShareLockDialog({
  required BuildContext context,
  required String lockName,
  required String inviteCode,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: const Color(0xFF2C2D31),
        title: Text(
          'Share $lockName',
          style: const TextStyle(color: Color(0xFFFFFFFF)),
        ),
        content: SizedBox(
          width: 280,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Anyone with this code can open this lock. Share it only with people you trust.',
                  style: TextStyle(color: Color(0xFF9E9E9E)),
                ),
                const SizedBox(height: 16),
                ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: QrImageView(
                        data: inviteCode,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  inviteCode,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: inviteCode));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('Invite code copied.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () async {
              final box = dialogContext.findRenderObject() as RenderBox?;
              final origin = box == null
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size;
              await SharePlus.instance.share(
                ShareParams(
                  text: inviteCode,
                  subject: '$lockName lock invite',
                  sharePositionOrigin: origin,
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: const Color(0xFF1A1B1E),
            ),
            child: const Text('Share Invite Code'),
          ),
        ],
      );
    },
  );
}
