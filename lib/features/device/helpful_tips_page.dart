import 'package:fitness_snack_lock/utils/get_app_version.dart';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpfulTipsPage extends StatelessWidget {
  const HelpfulTipsPage({super.key});

  static const _backgroundColor = Color(0xFF1A1B1E);
  static const _cardColor = Color(0xFF2C2D31);
  static const _labelColor = Color(0xFFFFFFFF);
  static const _bodyColor = Color(0xFFBDBDBD);
  static const _accentColor = Color(0xFF00E676);
  static const _importantColor = Color(0xFFFFB74D);
  static const _warningColor = Color(0xFFEF5350);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        foregroundColor: _labelColor,
        elevation: 0,
        title: const Text(
          'Helpful Tips',
          style: TextStyle(
            color: _labelColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: const [
          Text(
            'A few habits that keep your locks reachable.',
            style: TextStyle(
              color: _bodyColor,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          SizedBox(height: 16),
          _TipCard(
            icon: PhosphorIconsRegular.qrCode,
            iconColor: _importantColor,
            badge: 'Important',
            badgeColor: _importantColor,
            title: 'Back Up Your Lock QR Codes',
            body: Text.rich(
              TextSpan(
                style: TextStyle(color: _bodyColor, fontSize: 14, height: 1.45),
                children: [
                  TextSpan(
                    text: 'Open each lock\'s menu (⋮ → Share)',
                    style: TextStyle(
                      color: _labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: ', take a screenshot of the QR code, and save it in ',
                  ),
                  TextSpan(
                    text: 'Google Drive',
                    style: TextStyle(
                      color: _labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ', '),
                  TextSpan(
                    text: 'iCloud',
                    style: TextStyle(
                      color: _labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text:
                        ', or another secure cloud folder. Lock keys stay on this phone, so a saved QR screenshot lets you restore access if the phone is lost, broken, or replaced.',
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          _TipCard(
            icon: PhosphorIconsRegular.arrowClockwise,
            iconColor: _accentColor,
            title: 'Update — Never Uninstall',
            body: Text(
              'When a new version of Vigo Vault is released, tap Update in the App Store or Google Play. Uninstalling the app permanently deletes the lock keys stored on that phone.',
              style: TextStyle(color: _bodyColor, fontSize: 14, height: 1.45),
            ),
          ),
          SizedBox(height: 12),
          _TipCard(
            icon: PhosphorIconsRegular.batteryWarning,
            iconColor: _warningColor,
            title: 'Recharge at 20% Battery',
            body: Text.rich(
              TextSpan(
                style: TextStyle(color: _bodyColor, fontSize: 14, height: 1.45),
                children: [
                  TextSpan(
                    text:
                        'When a lock card shows a red border or a low-battery warning (20% or below), recharge it soon so it doesn\'t run out of power while locked. ',
                  ),
                  TextSpan(
                    text: 'Only charge using the included 5V cable',
                    style: TextStyle(
                      color: _labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text:
                        ' to prevent overheating from faster chargers, and allow ',
                  ),
                  TextSpan(
                    text: '2 to 3 hours',
                    style: TextStyle(
                      color: _labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ' for a full charge.'),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          _TipCard(
            icon: PhosphorIconsRegular.shareNetwork,
            iconColor: _accentColor,
            title: 'Share Access Safely',
            body: Text(
              'Use the Share QR code to give family members or trusted users access on iPhone or Android without sharing your phone or a physical key.',
              style: TextStyle(color: _bodyColor, fontSize: 14, height: 1.45),
            ),
          ),
          SizedBox(height: 12),
          _ContactSupportCard(),
          SizedBox(height: 20),
          _AppVersionFooter(),
        ],
      ),
    );
  }
}

class _ContactSupportCard extends StatefulWidget {
  const _ContactSupportCard();

  @override
  State<_ContactSupportCard> createState() => _ContactSupportCardState();
}

class _ContactSupportCardState extends State<_ContactSupportCard> {
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
    return Material(
      color: HelpfulTipsPage._cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF3A3B40)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _emailSupport,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: HelpfulTipsPage._accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.mail_outline,
                  color: HelpfulTipsPage._accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contact Support',
                      style: TextStyle(
                        color: HelpfulTipsPage._labelColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _supportEmail,
                      style: TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.badge,
    this.badgeColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget body;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HelpfulTipsPage._cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3B40)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                if (badge != null) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? iconColor).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: badgeColor ?? iconColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: HelpfulTipsPage._labelColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}

class _AppVersionFooter extends StatefulWidget {
  const _AppVersionFooter();

  @override
  State<_AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<_AppVersionFooter> {
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

  @override
  Widget build(BuildContext context) {
    return Text(
      _versionLabel,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFF9E9E9E)),
    );
  }
}
