import 'dart:async';

import 'package:fitness_snack_lock/providers/ble_provider.dart';
import 'package:fitness_snack_lock/providers/saved_locks_provider.dart';
import 'package:fitness_snack_lock/services/ble_connection_monitor.dart';
import 'package:fitness_snack_lock/services/ble_service.dart';
import 'package:fitness_snack_lock/services/pairing_service.dart';
import 'package:fitness_snack_lock/services/watch_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap/index.dart';
import 'constants/app_branding.dart';
import 'constants/colors.dart';
import 'features/device/device_dashboard_page.dart';
import 'features/onboarding/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WatchService();
  await bootstrap();

  runApp(
    const ProviderScope(
      child: RootApp(),
    ),
  );
}

class RootApp extends ConsumerStatefulWidget {
  const RootApp({super.key});

  @override
  ConsumerState<RootApp> createState() => _RootAppState();
}

class _RootAppState extends ConsumerState<RootApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WatchService.instance?.onToggleLock = _handleWatchToggleLock;
    });
  }

  Future<bool> _handleWatchToggleLock() async {
    final locksState = ref.read(savedLocksProvider);
    final lockId = locksState.primaryLockId ??
        locksState.activeLockId ??
        (locksState.locks.isNotEmpty ? locksState.locks.first.id : null);

    if (lockId == null || lockId.isEmpty) {
      await WatchService.instance?.sendStateToWatch('failed');
      return false;
    }

    try {
      final isUnlocked = await BleService.connectAndUnLock(lockId);
      await WatchService.instance?.sendStateToWatch(
        isUnlocked ? 'unlocked' : 'failed',
      );
      return isUnlocked;
    } on LockAuthenticationException {
      await WatchService.instance?.sendStateToWatch('auth_required');
      return false;
    } on PairingRequiredException {
      await WatchService.instance?.sendStateToWatch('failed');
      return false;
    } catch (_) {
      await WatchService.instance?.sendStateToWatch('failed');
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_releaseBleOnBackground());
    }
  }

  Future<void> _releaseBleOnBackground() async {
    final locks = ref.read(savedLocksProvider).locks;
    final deviceIds = locks.map((lock) => lock.id);

    await BleService.releaseAllActiveConnections(
      knownDeviceIds: deviceIds,
    );
    ref.read(bleProvider.notifier).clearSession();
    BleConnectionMonitor.stopMonitoring();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(savedLocksProvider);

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
    return const DeviceDashboardPage();
  }
}
