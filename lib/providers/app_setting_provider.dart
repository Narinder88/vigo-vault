import 'package:cron/cron.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef AppSettingData = ({
  DateTime? acceptPrivacyTime,
  DateTime? changeGoalTime,
  int changedGoalCount,
});

final appSettingProvider =
    StateNotifierProvider<AppSettingProvider, AppSettingData>((ref) {
  return AppSettingProvider();
});

class AppSettingProvider extends StateNotifier<AppSettingData> {
  AppSettingProvider()
      : super((
          acceptPrivacyTime: null,
          changeGoalTime: null,
          changedGoalCount: 0,
        ));

  final cron = Cron();

  AppSettingData get value => state;

  Future<void> setInitialData() async {
    final storedData = await getDataFromSharedPrefs();
    state = (
      acceptPrivacyTime: storedData.acceptPrivacyTime,
      changeGoalTime: storedData.changeGoalTime,
      changedGoalCount: storedData.changedGoalCount,
    );
  }

  Future<void> setAcceptPrivacyTime() async {
    state = (
      acceptPrivacyTime: DateTime.now(),
      changeGoalTime: state.changeGoalTime,
      changedGoalCount: state.changedGoalCount,
    );

    await saveDataToSharedPrefs();
  }

  Future<bool> setChangeGoalTime({
    bool isReset = false,
    bool forceReset = false,
  }) async {
    var isActualReset = false;

    if (forceReset) {
      state = (
        acceptPrivacyTime: state.acceptPrivacyTime,
        changeGoalTime: null,
        changedGoalCount: 0,
      );
    } else {
      final currentDateTime = DateTime.now();
      if (isReset) {
        DateTime resetPointTime = DateTime(currentDateTime.year,
            currentDateTime.month, currentDateTime.day, 0, 5, 0);

        final prefs = await SharedPreferences.getInstance();
        final selectedDateTimeStr = prefs.getString('RESET_POINT');
        if (selectedDateTimeStr != null) {
          resetPointTime = DateTime.parse(selectedDateTimeStr);
        }

        final isResetPoint =
            (state.changeGoalTime?.isBefore(resetPointTime) ?? true);

        state = (
          acceptPrivacyTime: state.acceptPrivacyTime,
          changeGoalTime: isResetPoint ? null : state.changeGoalTime,
          changedGoalCount: isResetPoint ? 0 : state.changedGoalCount,
        );
        isActualReset = isResetPoint;
      } else {
        state = (
          acceptPrivacyTime: state.acceptPrivacyTime,
          changeGoalTime: currentDateTime,
          changedGoalCount: state.changedGoalCount,
        );
      }
    }

    await saveDataToSharedPrefs();

    return isActualReset;
  }

  Future<void> setChangedGoalCount() async {
    state = (
      acceptPrivacyTime: state.acceptPrivacyTime,
      changeGoalTime: state.changeGoalTime,
      changedGoalCount: state.changedGoalCount + 1,
    );

    await saveDataToSharedPrefs();
  }

  Future<void> saveDataToSharedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final acceptPrivacyTimeStr =
        state.acceptPrivacyTime?.toIso8601String() ?? '';
    final changeGoalTimeStr = state.changeGoalTime?.toIso8601String() ?? '';

    await prefs.setString(
      'acceptPrivacyTime',
      acceptPrivacyTimeStr,
    );

    await prefs.setString(
      'changeGoalTime',
      changeGoalTimeStr,
    );

    await prefs.setInt(
      'changedGoalCount',
      state.changedGoalCount,
    );
  }

  Future<AppSettingData> getDataFromSharedPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final acceptPrivacyTimeStr = prefs.getString('acceptPrivacyTime');
    final changeGoalTimeStr = prefs.getString('changeGoalTime');
    final changedGoalCount = prefs.getInt('changedGoalCount');

    return (
      acceptPrivacyTime: acceptPrivacyTimeStr?.isEmpty ?? true
          ? null
          : DateTime.parse(acceptPrivacyTimeStr!),
      changeGoalTime: changeGoalTimeStr?.isEmpty ?? true
          ? null
          : DateTime.parse(changeGoalTimeStr!),
      changedGoalCount: changedGoalCount ?? 0,
    );
  }

  void getDataPerPeriod() {
    cron.schedule(Schedule.parse('0 0 * * *'), () async {
      setChangeGoalTime(forceReset: true);
    });

    cron.schedule(Schedule.parse('5 0 * * *'), () async {
      setChangeGoalTime(forceReset: true);
    });
  }

  void syncDataPerPeriod() {
    setChangeGoalTime(forceReset: true);
  }
}
