import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/lock_invite.dart';
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
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _importRaw(String raw) async {
    if (_importing) return;

    final parsed = LockInvite.parse(raw);
    final invite = parsed.invite;
    if (invite == null) {
      setState(() => _error = parsed.error);
      return;
    }

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      await ref.read(savedLocksProvider.notifier).importSharedLock(invite);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SharedLockNotFound catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = 'Could not save this lock on this phone.';
      });
    }
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Paste an invite code, or scan the QR code from the phone that already has this lock.',
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
            onPressed: _importing
                ? null
                : () => _importRaw(_codeController.text),
            child: Text(_importing ? 'Saving...' : 'Import pasted code'),
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
                  onDetect: (capture) {
                    final raw = capture.barcodes
                        .map((barcode) => barcode.rawValue)
                        .whereType<String>()
                        .where((value) => value.trim().isNotEmpty)
                        .firstOrNull;
                    if (raw == null) return;
                    _codeController.text = raw;
                    _importRaw(raw);
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
