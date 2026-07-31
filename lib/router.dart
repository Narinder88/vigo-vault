import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/device/device_connection_page/device_connection_page.dart';
import 'features/device/device_dashboard_page.dart';
import 'features/device/device_management_page.dart';
import 'features/device/device_scanning_page/device_scanning_page.dart';
import 'features/onboarding/guide_intro_page.dart';
import 'features/setting/references_page.dart';
import 'features/setting/setting_page.dart';

part 'router.g.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final rootRouter = GoRouter(
  initialLocation: const DeviceDashboardRoute().location,
  routes: $appRoutes,
  navigatorKey: rootNavigatorKey,
);

@TypedGoRoute<DeviceDashboardRoute>(
  path: '/',
)
class DeviceDashboardRoute extends GoRouteData with $DeviceDashboardRoute {
  const DeviceDashboardRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const DeviceDashboardPage();
  }
}

@TypedGoRoute<GuideIntroRoute>(
  path: '/guide',
)
class GuideIntroRoute extends GoRouteData with $GuideIntroRoute {
  const GuideIntroRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const GuideIntroPage();
  }
}

@TypedGoRoute<SettingRoute>(
  path: '/setting',
  routes: <TypedRoute<RouteData>>[
    TypedGoRoute<ReferencesRoute>(path: 'references'),
  ],
)
class SettingRoute extends GoRouteData with $SettingRoute {
  const SettingRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const SettingPage();
  }
}

class ReferencesRoute extends GoRouteData with $ReferencesRoute {
  const ReferencesRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const ReferencesPage();
  }
}

@TypedGoRoute<DeviceConnectionRoute>(
  path: '/device',
  routes: <TypedRoute<RouteData>>[
    TypedGoRoute<DeviceManagementRoute>(path: 'manage'),
    TypedGoRoute<DeviceScanningRoute>(path: 'scan'),
  ],
)
class DeviceConnectionRoute extends GoRouteData with $DeviceConnectionRoute {
  const DeviceConnectionRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const DeviceConnectionPage();
  }
}

class DeviceManagementRoute extends GoRouteData with $DeviceManagementRoute {
  const DeviceManagementRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const DeviceManagementPage();
  }
}

class DeviceScanningRoute extends GoRouteData with $DeviceScanningRoute {
  const DeviceScanningRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const DeviceScanningPage();
  }
}
