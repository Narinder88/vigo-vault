import 'dart:async';

import 'package:flutter/material.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '../services/in_app_update_service.dart';
import 'library.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  TerminateRestart.instance.initialize();
  await setupLibrary();
  unawaited(InAppUpdateService.checkAndPromptForUpdate());
}
