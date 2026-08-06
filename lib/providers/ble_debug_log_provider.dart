import 'package:fitness_snack_lock/services/ble_debug_log.dart';
import 'package:flutter_riverpod/legacy.dart';

final bleDebugLogProvider =
    StateNotifierProvider<BleDebugLogNotifier, List<String>>((ref) {
  return BleDebugLogNotifier();
});

class BleDebugLogNotifier extends StateNotifier<List<String>> {
  BleDebugLogNotifier() : super(List<String>.from(BleDebugLog.entries)) {
    BleDebugLog.bind((line) {
      if (line == '[log cleared]') {
        state = [];
        return;
      }
      state = [...state, line];
      if (state.length > BleDebugLog.maxEntries) {
        state = state.sublist(state.length - BleDebugLog.maxEntries);
      }
    });
  }

  void clear() {
    BleDebugLog.clear();
  }
}
