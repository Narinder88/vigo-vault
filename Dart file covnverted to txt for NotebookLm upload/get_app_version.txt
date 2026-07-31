import 'package:package_info_plus/package_info_plus.dart';

Future<({String version, String buildNumber})> getAppVersion() async {
  final packageInfo = await PackageInfo.fromPlatform();

  String version = packageInfo.version;
  String buildNumber = packageInfo.buildNumber;

  return (version: version, buildNumber: buildNumber);
}
