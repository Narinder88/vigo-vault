import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';

class InAppUpdateService {
  InAppUpdateService._();

  static StreamSubscription<InstallStatus>? _flexibleUpdateSubscription;

  /// Checks Google Play for an update and prompts when one is available.
  static Future<void> checkAndPromptForUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      final updateInfo = await InAppUpdate.checkForUpdate();

      if (updateInfo.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }

      if (updateInfo.immediateUpdateAllowed) {
        await _performImmediateUpdate();
        return;
      }

      if (updateInfo.flexibleUpdateAllowed) {
        await _startFlexibleUpdate();
      }
    } on PlatformException catch (error, stackTrace) {
      _logSkippedUpdate('In-app update unavailable', error, stackTrace);
    } catch (error, stackTrace) {
      _logSkippedUpdate('In-app update check failed', error, stackTrace);
    }
  }

  static Future<void> _performImmediateUpdate() async {
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      if (kDebugMode && result != AppUpdateResult.success) {
        developer.log(
          'Immediate update result: $result',
          name: 'InAppUpdateService',
        );
      }
    } on PlatformException catch (error, stackTrace) {
      _logSkippedUpdate('Immediate update failed', error, stackTrace);
    }
  }

  static Future<void> _startFlexibleUpdate() async {
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result != AppUpdateResult.success) {
        if (kDebugMode) {
          developer.log(
            'Flexible update not started: $result',
            name: 'InAppUpdateService',
          );
        }
        return;
      }

      await _flexibleUpdateSubscription?.cancel();
      _flexibleUpdateSubscription = InAppUpdate.installUpdateListener.listen(
        (status) async {
          if (status != InstallStatus.downloaded) {
            return;
          }

          try {
            await InAppUpdate.completeFlexibleUpdate();
          } on PlatformException catch (error, stackTrace) {
            _logSkippedUpdate(
              'Flexible update install failed',
              error,
              stackTrace,
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _logSkippedUpdate('Flexible update listener error', error, stackTrace);
        },
      );
    } on PlatformException catch (error, stackTrace) {
      _logSkippedUpdate('Flexible update failed', error, stackTrace);
    }
  }

  static void _logSkippedUpdate(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    if (kDebugMode) {
      developer.log(
        '$message: $error',
        name: 'InAppUpdateService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> dispose() async {
    await _flexibleUpdateSubscription?.cancel();
    _flexibleUpdateSubscription = null;
  }
}
