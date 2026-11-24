import 'dart:async';
import 'dart:io' show Platform;

import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/lock_invite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ImportSharedLockPage extends ConsumerStatefulWidget {
  const ImportSharedLockPage({super.key});

  @override
  ConsumerState<ImportSharedLockPage> createState() =>
      _ImportSharedLockPageState();
}

class _ImportSharedLockPageState extends ConsumerState<ImportSharedLockPage> {
  final TextEditingController _codeController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  var _scanning = false;
  var _importing = false;
  var _hasHandledScan = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _codeController.dispose();
    try {
      _scannerController.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!mounted || _importing || _hasHandledScan) return;

    try {
      final raw = capture.barcodes
          .map((barcode) => barcode.rawValue)
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .firstOrNull;
      if (raw == null) {
        _showReadError('Could not read that QR code. Try again.');
        return;
      }

      final parsed = LockInvite.tryParse(raw);
      final invite = parsed.invite;
      if (invite == null) {
        _showReadError(parsed.error ?? 'That invite code could not be read.');
        return;
      }

      _hasHandledScan = true;
      _importing = true;
      _codeController.text = raw;
      unawaited(_runImport(invite, stopScanner: true));
    } catch (error) {
      _showReadError(_visibleError(error, 'Could not read that QR code. Try again.'));
    }
  }

  void _showReadError(String message) {
    if (!mounted) return;
    setState(() {
      _importing = false;
      _hasHandledScan = false;
      _error = message;
    });
  }

  String _visibleError(Object error, String fallback) {
    if (error is SharedLockNotFound && error.message.trim().isNotEmpty) {
      return error.message;
    }
    final text = error.toString().trim();
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }

  void _importPastedCode() {
    if (!mounted || _importing || _hasHandledScan) return;

    try {
      final parsed = LockInvite.tryParse(_codeController.text);
      final invite = parsed.invite;
      if (invite == null) {
        _showReadError(parsed.error ?? 'That invite code could not be read.');
        return;
      }

      _importing = true;
      if (_scanning) _hasHandledScan = true;
      unawaited(_runImport(invite, stopScanner: _scanning));
    } catch (error) {
      _showReadError(
        _visibleError(error, 'Could not read that invite code. Try again.'),
      );
    }
  }

  Future<void> _runImport(
    LockInvite invite, {
    required bool stopScanner,
  }) async {
    if (!mounted) return;
    final useFee7 = kIsWeb || !Platform.isAndroid || !invite.hasValidMac;
    setState(() {
      _error = null;
      _status = useFee7
          ? 'Verifying nearby ${invite.savedDisplayName} lock...'
          : 'Saving...';
    });

    if (stopScanner) {
      try {
        await _scannerController.stop();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _scanning = false);
    }

    try {
      await ref.read(savedLocksProvider.notifier).importSharedLock(invite);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${invite.savedDisplayName} imported successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      navigator.popUntil((route) => route.isFirst);
    } catch (error) {
      await _importFailed(
        _visibleError(error, 'Could not save this lock on this phone.'),
        reopenScanner: stopScanner,
      );
    }
  }

  Future<void> _importFailed(
    String message, {
    required bool reopenScanner,
  }) async {
    if (!mounted) return;
    setState(() {
      _importing = false;
      _hasHandledScan = false;
      _status = null;
      _error = message;
      if (reopenScanner) _scanning = true;
    });
    if (!reopenScanner) return;
    try {
      await _scannerController.start();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('Import Shared Lock'),
      ),
      body: _importing
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.black),
                    const SizedBox(height: 24),
                    Text(
                      _status ?? 'Verifying nearby lock...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Paste an invite code, or scan the QR code from the phone that already has this lock.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep the lock within a few feet and make sure no other phone is currently connected to it.',
            style: TextStyle(color: Color(0xFF616161)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Invite code',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _importing ? null : _importPastedCode,
            child: Text(
              _importing ? (_status ?? 'Saving...') : 'Import pasted code',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _importing
                ? null
                : () => setState(() {
                      _scanning = !_scanning;
                      _error = null;
                    }),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(_scanning ? 'Hide scanner' : 'Scan QR code'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB00020)),
            ),
          ],
          if (_scanning) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
