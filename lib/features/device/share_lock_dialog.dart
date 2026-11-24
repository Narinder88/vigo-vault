import 'dart:async';

import 'package:fitness_snack_lock/models/saved_lock.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/lock_invite.dart';
import 'package:fitness_snack_lock/utils/share_debug_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

Future<({String code, SavedLock lock})?> _encodeInvite(SavedLock lock) async {
  try {
    return await LockInvite.encode(
      lock.copyWith(
        displayName: LockInvite.sanitizeBleName(lock.displayName),
        hardwareName: lock.hardwareName == null
            ? null
            : LockInvite.sanitizeBleName(lock.hardwareName!),
      ),
    );
  } catch (_) {
    return null;
  }
}

Future<void> showShareLockDialog({
  required BuildContext context,
  required SavedLock lock,
}) async {
  final prepared = await _encodeInvite(lock);
  if (!context.mounted) return;

  if (prepared == null) {
    // TEMP_DEBUG_LOG
    ShareDebugLog.instance.log(
      'share',
      'encode failed platform=${ShareDebugLog.platformLabel()} '
      'remoteId=${lock.id} hardwareName="${lock.hardwareName}" '
      'units=${(lock.hardwareName ?? '').codeUnits}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This lock does not have a saved key and password yet.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  ProviderScope.containerOf(context)
      .read(savedLocksProvider.notifier)
      .replaceLock(prepared.lock);

  final inviteCode = prepared.code;
  final lockName = prepared.lock.displayName;
  final parsed = LockInvite.tryParse(inviteCode);
  // TEMP_DEBUG_LOG
  ShareDebugLog.instance.log(
    'share',
    'platform=${ShareDebugLog.platformLabel()} remoteId=${prepared.lock.id} '
    'codeLen=${inviteCode.length}',
  );
  if (parsed.invite != null) {
    // TEMP_DEBUG_LOG
    ShareDebugLog.instance.log(
      'share',
      ShareDebugLog.inviteSummary(
        parsed.invite!,
        rawName: lock.hardwareName ?? lock.displayName,
      ),
    );
  } else {
    // TEMP_DEBUG_LOG
    ShareDebugLog.instance.log('share', 'encode parsed empty ${parsed.error}');
  }
  await BleService.disconnectIfConnected(prepared.lock.id);
  await BleService.disconnectActiveDevice();
  if (!context.mounted) return;
  unawaited(BleService.wakeLockForSharing(prepared.lock.id));
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
              try {
                await Clipboard.setData(ClipboardData(text: inviteCode));
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Invite code copied.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (_) {}
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                if (!dialogContext.mounted) return;
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
              } catch (_) {}
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
