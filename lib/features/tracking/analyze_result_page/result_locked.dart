import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:wave_blob/wave_blob.dart';

class ResultLocked extends ConsumerStatefulWidget {
  const ResultLocked({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ResultLockedState();
}

class _ResultLockedState extends ConsumerState<ResultLocked> {
  Timer? timer;

  var _amplitude = 4250.0;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        setState(() {
          _amplitude = 8500.0 * 0.65;
        });
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.sizeOf(context).width * 0.8,
      height: MediaQuery.sizeOf(context).width * 0.8,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: WaveBlob(
        blobCount: 3,
        amplitude: _amplitude,
        scale: 1,
        autoScale: true,
        centerCircle: true,
        overCircle: true,
        circleColors: const [
          Colors.red,
        ],
        colors: [
          Colors.red.withOpacity(0.3),
          Colors.red.withOpacity(0.3),
        ],
        child: const Icon(
          PhosphorIconsBold.lockKey,
          color: Colors.white,
          size: 50.0,
        ),
      ),
    );
  }
}
