import 'package:fitness_snack_lock/features/device/share_debug_log_sheet.dart';
import 'package:fitness_snack_lock/utils/get_app_version.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AppInfoSheet extends StatefulWidget {
  const AppInfoSheet({super.key});

  @override
  State<AppInfoSheet> createState() => _AppInfoSheetState();
}

class _AppInfoSheetState extends State<AppInfoSheet> {
  static const _supportEmail = 'fitnesssnacklock@gmail.com';

  String? _version;
  String? _buildNumber;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await getAppVersion();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (_) {}
  }

  String get _versionLabel {
    final version = _version;
    final buildNumber = _buildNumber;
    if (version == null ||
        version.isEmpty ||
        buildNumber == null ||
        buildNumber.isEmpty) {
      return 'Version …';
    }
    return 'Version $version ($buildNumber)';
  }

  Future<void> _emailSupport() async {
    final version = _version;
    final buildNumber = _buildNumber;
    final subject = (version == null || version.isEmpty)
        ? 'Vigo Vault support'
        : 'Vigo Vault $version ($buildNumber)';
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open an email app.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Switching to a New Phone',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Have both phones? Tap Share on each lock and scan the QR code onto the new phone.',
              style: TextStyle(color: Color(0xFFBDBDBD), height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Trading in first? Remove/unpair the lock in the app before wiping the phone, or save a copy of the Share Invite Code so you can import it on the new phone later.',
              style: TextStyle(color: Color(0xFFBDBDBD), height: 1.4),
            ),
            const SizedBox(height: 8),
            // TEMP_DEBUG_LOG
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bug_report_outlined, color: Color(0xFF00E676)),
              title: const Text(
                'Debug Logs',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => showShareDebugLogSheet(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mail_outline, color: Color(0xFF00E676)),
              title: const Text(
                'Contact Support',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                _supportEmail,
                style: TextStyle(color: Color(0xFF9E9E9E)),
              ),
              onTap: _emailSupport,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _versionLabel,
                style: const TextStyle(color: Color(0xFF9E9E9E)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
