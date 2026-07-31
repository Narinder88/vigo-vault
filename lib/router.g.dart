// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'router.dart';

// **************************************************************************
// GoRouterGenerator
// **************************************************************************

List<RouteBase> get $appRoutes => [
      $deviceDashboardRoute,
      $guideIntroRoute,
      $settingRoute,
      $deviceConnectionRoute,
    ];

RouteBase get $deviceDashboardRoute => GoRouteData.$route(
      path: '/',
      hasOverriddenOnExit: false,
      factory: $DeviceDashboardRoute._fromState,
    );

mixin $DeviceDashboardRoute on GoRouteData {
  static DeviceDashboardRoute _fromState(GoRouterState state) =>
      const DeviceDashboardRoute();

  @override
  String get location => GoRouteData.$location(
        '/',
      );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $guideIntroRoute => GoRouteData.$route(
      path: '/guide',
      hasOverriddenOnExit: false,
      factory: $GuideIntroRoute._fromState,
    );

mixin $GuideIntroRoute on GoRouteData {
  static GuideIntroRoute _fromState(GoRouterState state) =>
      const GuideIntroRoute();

  @override
  String get location => GoRouteData.$location(
        '/guide',
      );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $settingRoute => GoRouteData.$route(
      path: '/setting',
      hasOverriddenOnExit: false,
      factory: $SettingRoute._fromState,
      routes: [
        GoRouteData.$route(
          path: 'references',
          hasOverriddenOnExit: false,
          factory: $ReferencesRoute._fromState,
        ),
      ],
    );

mixin $SettingRoute on GoRouteData {
  static SettingRoute _fromState(GoRouterState state) => const SettingRoute();

  @override
  String get location => GoRouteData.$location(
        '/setting',
      );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $ReferencesRoute on GoRouteData {
  static ReferencesRoute _fromState(GoRouterState state) =>
      const ReferencesRoute();

  @override
  String get location => GoRouteData.$location(
        '/setting/references',
      );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $deviceConnectionRoute => GoRouteData.$route(
      path: '/device',
      hasOverriddenOnExit: false,
      factory: $DeviceConnectionRoute._fromState,
      routes: [
        GoRouteData.$route(
          path: 'manage',
          hasOverriddenOnExit: false,
          factory: $DeviceManagementRoute._fromState,
        ),
        GoRouteData.$route(
          path: 'scan',
          hasOverriddenOnExit: false,
          factory: $DeviceScanningRoute._fromState,
        ),
      ],
    );

mixin $DeviceConnectionRoute on GoRouteData {
  static DeviceConnectionRoute _fromState(GoRouterState state) =>
      const DeviceConnectionRoute();

  @override
  String get location => GoRouteData.$location(
        '/device',
      );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $DeviceManagementRoute on GoRouteData {
  static DeviceManagementRoute _fromState(GoRouterState state) =>
      const DeviceManagementRoute();

  @override
  String get location => GoRouteData.$location(
        '/device/manage',
      );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $DeviceScanningRoute on GoRouteData {
  static DeviceScanningRoute _fromState(GoRouterState state) =>
      const DeviceScanningRoute();

  @override
  String get location => GoRouteData.$location(
        '/device/scan',
      );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}
