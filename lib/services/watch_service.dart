import 'package:flutter/services.dart';

class WatchService {
  WatchService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel = MethodChannel('com.singh.vigovault/watch');

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'fromWatch') {
      return;
    }

    final arguments = call.arguments;
    if (arguments is Map && arguments['action'] == 'toggleLock') {
      // ignore: avoid_print
      print('⌚ Watch requested a vault toggle!');
    }
  }

  Future<void> sendStateToWatch(String state) async {
    await _channel.invokeMethod('sendToWatch', {'state': state});
  }
}
