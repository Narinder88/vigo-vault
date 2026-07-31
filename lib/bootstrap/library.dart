import 'database.dart';
import 'loader.dart';
import 'notification.dart';
import 'service.dart';

Future<void> setupLibrary() async {
  await setupDatabase();
  await setupNotification();
  await setupService();
  setupLoader();
}
