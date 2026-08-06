import 'package:flutter/foundation.dart';

typedef BleDebugLogSink = void Function(String line);

/// Temporary on-device BLE lifecycle log for TestFlight / no-Mac debugging.
class BleDebugLog {
  BleDebugLog._();

  static const int maxEntries = 80;
  static BleDebugLogSink? _sink;
  static final List<String> _entries = [];

  static List<String> get entries => List.unmodifiable(_entries);

  static void bind(BleDebugLogSink sink) {
    _sink = sink;
  }

  static void clear() {
    _entries.clear();
    _sink?.call('[log cleared]');
  }

  static void _emit(String tag, String message) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final line = '$ts [$tag] $message';
    debugPrint(line);
    _entries.add(line);
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    _sink?.call(line);
  }

  static void ble(String message) => _emit('BLE', message);

  static void tap(String message) => _emit('TAP', message);

  static void write(String message) => _emit('WRITE', message);

  static void error(String message) => _emit('ERROR', message);
}
