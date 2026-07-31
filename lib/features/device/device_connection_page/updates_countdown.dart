import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import 'package:fitness_snack_lock/constants/colors.dart';
import 'package:fitness_snack_lock/services/lock_telemetry_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Visual 60-second countdown that also refreshes lock telemetry when it completes.
class UpdatesCountdown extends ConsumerStatefulWidget {
  const UpdatesCountdown({super.key});

  @override
  ConsumerState<UpdatesCountdown> createState() => _UpdatesCountdownState();
}

class _UpdatesCountdownState extends ConsumerState<UpdatesCountdown> {
  final _countdownController = CountDownController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LockTelemetrySync.refresh(ref);
    });
  }

  Future<void> _syncLockTelemetry() async {
    await LockTelemetrySync.refresh(ref);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Syncing Notes'),
            content: const Text(
              'The app syncs lock connection, battery, and signal strength every minute.',
            ),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
      child: CircularCountDownTimer(
        controller: _countdownController,
        duration: 60,
        initialDuration: 0,
        width: 24,
        height: 24,
        ringColor: AppColors.kPrimaryColor.withValues(alpha: 0.1),
        fillColor: AppColors.kPrimaryColor.withValues(alpha: 0.8),
        backgroundColor: Colors.transparent,
        strokeWidth: 3,
        strokeCap: StrokeCap.round,
        isTimerTextShown: true,
        autoStart: true,
        onComplete: () async {
          await _syncLockTelemetry();
          _countdownController.restart();
        },
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.kPrimaryColor,
        ),
        timeFormatterFunction: (_, time) {
          return (60 - time.inSeconds).toString();
        },
      ),
    );
  }
}
