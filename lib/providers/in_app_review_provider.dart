import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/inv_service.dart';

typedef InAppReviewData = ({
  int count,
  DateTime? lastCountTime,
  DateTime? lastShownTime,
});

final inAppReviewProvider =
    StateNotifierProvider<InAppReviewProvider, InAppReviewData>((ref) {
  return InAppReviewProvider();
});

class InAppReviewProvider extends StateNotifier<InAppReviewData> {
  InAppReviewProvider()
      : super((count: 0, lastCountTime: null, lastShownTime: null));

  InAppReviewData get value => state;

  Future<void> setInitialData() async {
    final storedData = await getDataFromSharedPrefs();
    state = (
      count: storedData.count,
      lastCountTime: storedData.lastCountTime,
      lastShownTime: storedData.lastShownTime,
    );
  }

  Future<void> countUp() async {
    final now = DateTime.now();
    final lastCountTime = state.lastCountTime;

    // Check if we already counted today
    if (lastCountTime != null) {
      final lastCountDate = DateTime(
        lastCountTime.year,
        lastCountTime.month,
        lastCountTime.day,
      );
      final today = DateTime(now.year, now.month, now.day);

      // If already counted today, don't increment
      if (lastCountDate == today) {
        return;
      }
    }

    state = (
      count: state.count + 1,
      lastCountTime: now,
      lastShownTime: state.lastShownTime,
    );

    await saveStepDataToSharedPrefs();
  }

  Future<void> setLastShownTime() async {
    state = (
      count: state.count + 1,
      lastCountTime: state.lastCountTime,
      lastShownTime: DateTime.now(),
    );
    await saveStepDataToSharedPrefs();
  }

  Future<void> requestReview() async {
    if (state.count == 2 && state.lastShownTime == null) {
      await INVService.requestReview();
      await setLastShownTime();
      return;
    }
    if ((state.count - 2) % 4 == 0 && state.lastShownTime != null) {
      await INVService.requestReview();
      await setLastShownTime();
      return;
    }
  }

  Future<void> saveStepDataToSharedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'inAppReviewCount',
      state.count,
    );

    if (state.lastCountTime != null) {
      await prefs.setString(
        'inAppReviewLastCountTime',
        state.lastCountTime!.toIso8601String(),
      );
    }

    if (state.lastShownTime != null) {
      await prefs.setString(
        'inAppReviewLastShownTime',
        state.lastShownTime!.toIso8601String(),
      );
    }
  }

  Future<InAppReviewData> getDataFromSharedPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final inAppReviewCount = prefs.getInt('inAppReviewCount');
    final inAppReviewLastCountTime =
        prefs.getString('inAppReviewLastCountTime');
    final inAppReviewLastShownTime =
        prefs.getString('inAppReviewLastShownTime');

    return (
      count: inAppReviewCount ?? 0,
      lastCountTime: inAppReviewLastCountTime != null
          ? DateTime.parse(inAppReviewLastCountTime)
          : null,
      lastShownTime: inAppReviewLastShownTime != null
          ? DateTime.parse(inAppReviewLastShownTime)
          : null,
    );
  }
}
