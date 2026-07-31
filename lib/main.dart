import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap/index.dart';
import 'constants/app_branding.dart';
import 'constants/colors.dart';
import 'features/device/device_dashboard_page.dart';
import 'features/onboarding/splash_screen.dart';
import 'providers/saved_locks_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrap();

  runApp(
    const ProviderScope(
      child: RootApp(),
    ),
  );
}

class RootApp extends ConsumerWidget {
  const RootApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: kAppDisplayName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.kPrimaryColor),
        useMaterial3: true,
      ),
      builder: EasyLoading.init(),
      home: const SplashScreen(),
      routes: {
        SplashScreen.routeName: (context) => const LockHomePage(),
        DeviceDashboardPage.routeName: (context) => const DeviceDashboardPage(),
      },
    );
  }
}

/// Entry point after splash — shows the multi-lock dashboard.
class LockHomePage extends ConsumerWidget {
  const LockHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(savedLocksProvider);
    return const DeviceDashboardPage();
  }
}
