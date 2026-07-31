import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../constants/app_branding.dart';
import '../../constants/colors.dart';
import '../../constants/web.dart';
import '../../router.dart';

class GuideIntroPage extends ConsumerWidget {
  const GuideIntroPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: TextButton.icon(
          onPressed: () {
            context.pop();
          },
          icon: const PhosphorIcon(
            PhosphorIconsRegular.caretLeft,
          ),
          label: const Text('Back'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.kPrimaryColor,
          ),
        ),
        leadingWidth: 100,
      ),
      body: Container(
        padding: const EdgeInsets.all(24).copyWith(bottom: 0),
        child: Column(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Welcome to $kAppDisplayName',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 450),
                    padding: const EdgeInsets.only(top: 24),
                    child: Html(
                      data: Platform.isIOS
                          ? '''
                            Unlock healthier habits—one step at a time.<br/><br/>
                          '''
                          : '''
                            Unlock healthier habits—one step at a time.<br/><br/>
                            <b>Health Connect Required for Smart Watch</b><br/><br/>
                            If you're using Android 13 or older,  install it first.<br/><a href="${WebData.kHealthConnectAppUrl}" style="text-decoration: none;">Tap here to get it from Google Play</a>.
                          ''',
                      onAnchorTap: (url, attributes, element) {
                        launchUrlString(url!);
                      },
                    ),
                  ),
                  Expanded(
                    child: SvgPicture.asset(
                      'assets/img_guide_intro.svg',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.only(bottom: 8),
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      const DeviceDashboardRoute().go(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.kPrimaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Start'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
