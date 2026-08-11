import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Internal BLE lifecycle log for development (console only).
class BleDebugLog {
  BleDebugLog._();

  static void _emit(String tag, String message) {
    if (!kDebugMode) return;

    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final line = '$ts [$tag] $message';
    developer.log(line, name: 'BleDebugLog');
  }

  static void ble(String message) => _emit('BLE', message);

  static void tap(String message) => _emit('TAP', message);

  static void write(String message) => _emit('WRITE', message);

  static void error(String message) => _emit('ERROR', message);
}
