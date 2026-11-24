// TEMP_DEBUG_LOG
import 'dart:io' show Platform;

import 'package:fitness_snack_lock/services/lock_invite.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;

/// In-memory ring buffer for temporary share/import BLE traces.
class ShareDebugLog extends ChangeNotifier {
  ShareDebugLog._();

  static final ShareDebugLog instance = ShareDebugLog._();
  static const int _maxLines = 300;

  final List<String> _lines = [];

  static String platformLabel() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem;
  }

  /// Invite fields safe to copy off a device. Never includes the full key or password.
  static String inviteSummary(LockInvite invite, {String rawName = ''}) {
    final key = invite.aesKey;
    final prefix = key.length >= 4 ? key.substring(0, 4) : key;
    return 'v=${LockInvite.version} raw="$rawName" rawUnits=${rawName.codeUnits} '
        'name="${invite.name}" nameUnits=${invite.name.codeUnits} '
        'displayName="${invite.displayName}" mac="${invite.macAddress}" '
        'hasValidMac=${invite.hasValidMac} keyBytes=${key.length ~/ 2} '
        'keyPrefix=$prefix passwordLen=${invite.password.length}';
  }

  void log(String tag, String msg) {
    final now = DateTime.now();
    final stamp = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    _lines.add('$stamp [$tag] $msg');
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  String exportText() => _lines.join('\n');
}
