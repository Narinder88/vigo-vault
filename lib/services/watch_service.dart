import 'package:flutter/services.dart';

typedef WatchToggleLockCallback = Future<void> Function();

class WatchService {
  WatchService() {
    instance = this;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static WatchService? instance;

  static const MethodChannel _channel =
      MethodChannel('com.singh.vigovault/watch');

  WatchToggleLockCallback? onToggleLock;

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'fromWatch') {
      return;
    }

    final arguments = call.arguments;
    if (arguments is Map && arguments['action'] == 'toggleLock') {
      if (onToggleLock != null) {
        await onToggleLock!();
      }
    }
  }

  Future<void> sendStateToWatch(String state) async {
    await _channel.invokeMethod('sendToWatch', {'state': state});
  }
}
