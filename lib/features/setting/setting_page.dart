import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../constants/app_branding.dart';
import '../../constants/web.dart';
import '../../router.dart';
import '../../services/inv_service.dart';
import '../../utils/get_app_version.dart';

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        centerTitle: false,
      ),
      body: ListView(
        children: [
          ListTile(
            onTap: () {
              DeviceConnectionRoute().push(context);
            },
            leading: const PhosphorIcon(PhosphorIconsDuotone.lockKey, size: 28),
            trailing: const Icon(
              PhosphorIconsRegular.caretRight,
              size: 18,
            ),
            title: Text('My Locks — $kAppDisplayName'),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade300,
            indent: 20,
          ),
          ListTile(
            onTap: () async {
              ReferencesRoute().push(context);
            },
            leading: const PhosphorIcon(PhosphorIconsDuotone.link, size: 28),
            trailing: const Icon(
              PhosphorIconsRegular.caretRight,
              size: 18,
            ),
            title: const Text('Sources & References'),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade300,
            indent: 20,
          ),
          ListTile(
            onTap: () async {
              INVService.openStore();
            },
            leading: PhosphorIcon(
              Platform.isAndroid
                  ? PhosphorIconsDuotone.googlePlayLogo
                  : PhosphorIconsDuotone.appStoreLogo,
              size: 28,
            ),
            trailing: const Icon(
              PhosphorIconsRegular.caretRight,
              size: 18,
            ),
            title: Text(
                'Rate on ${Platform.isAndroid ? 'Play Store' : 'App Store'}'),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade300,
            indent: 20,
          ),
          ListTile(
            onTap: () async {
              launchUrlString(
                WebData.kPrivacyUrl,
                mode: LaunchMode.inAppBrowserView,
              );
            },
            leading:
                const PhosphorIcon(PhosphorIconsDuotone.shieldCheck, size: 28),
            trailing: const Icon(
              PhosphorIconsRegular.caretRight,
              size: 18,
            ),
            title: const Text('Privacy Policy'),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade300,
            indent: 20,
          ),
          ListTile(
            onTap: () async {
              launchUrlString(
                WebData.kTermUrl,
                mode: LaunchMode.inAppBrowserView,
              );
            },
            leading: const PhosphorIcon(PhosphorIconsDuotone.note, size: 28),
            trailing: const Icon(
              PhosphorIconsRegular.caretRight,
              size: 18,
            ),
            title: const Text('Term of Use'),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade300,
            indent: 20,
          ),
          ListTile(
            onTap: () async {},
            leading: const PhosphorIcon(PhosphorIconsDuotone.info, size: 28),
            trailing: FutureBuilder(
              future: getAppVersion(),
              builder: (context, snapshot) {
                return Text(
                  snapshot.data?.version ?? '--',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500),
                );
              },
            ),
            title: const Text('Version'),
          ),
        ],
      ),
    );
  }
}
