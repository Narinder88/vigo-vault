import 'package:flutter/services.dart';

typedef WatchToggleLockCallback = Future<bool> Function();

class WatchService {
  WatchService() {
    instance = this;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static WatchService? instance;

  static const MethodChannel _channel =
      MethodChannel('com.singh.vigovault/watch');

  WatchToggleLockCallback? onToggleLock;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method != 'fromWatch') {
      return null;
    }

    final arguments = call.arguments;
    if (arguments is Map && arguments['action'] == 'toggleLock') {
      if (onToggleLock != null) {
        try {
          final success = await onToggleLock!();
          return {'status': success ? 'unlocked' : 'failed'};
        } catch (_) {
          return {'status': 'failed'};
        }
      }
      return {'status': 'failed', 'error': 'handler_not_registered'};
    }

    return null;
  }

  Future<void> sendStateToWatch(String state) async {
    await _channel.invokeMethod('sendToWatch', {'state': state});
  }
}
