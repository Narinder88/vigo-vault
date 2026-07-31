import 'package:in_app_review/in_app_review.dart';

class INVService {
  static Future<void> requestReview() async {
    final inAppReview = InAppReview.instance;

    if (await inAppReview.isAvailable()) {
      inAppReview.requestReview();
    }
  }

  static Future<void> openStore() async {
    final inAppReview = InAppReview.instance;

    await inAppReview.openStoreListing(
      appStoreId: '6657971709',
    );
  }
}
