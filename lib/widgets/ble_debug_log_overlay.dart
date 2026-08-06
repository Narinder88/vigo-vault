import 'package:fitness_snack_lock/providers/ble_debug_log_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BleDebugLogOverlay extends ConsumerStatefulWidget {
  const BleDebugLogOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<BleDebugLogOverlay> createState() => _BleDebugLogOverlayState();
}

class _BleDebugLogOverlayState extends ConsumerState<BleDebugLogOverlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(bleDebugLogProvider);
    final visible = _expanded ? logs : logs.take(3).toList();

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Material(
              color: Colors.black.withValues(alpha: 0.82),
              elevation: 8,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                onLongPress: () =>
                    ref.read(bleDebugLogProvider.notifier).clear(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'BLE Debug Log',
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _expanded ? 'tap to collapse' : 'tap to expand',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (visible.isEmpty)
                        Text(
                          'Waiting for BLE events…',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        )
                      else
                        ...visible.map(
                          (line) => Text(
                            line,
                            style: const TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontSize: 10,
                              height: 1.25,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
