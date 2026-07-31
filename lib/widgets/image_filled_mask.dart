import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';

class ImageFilledMask extends ConsumerStatefulWidget {
  final String imageUrl;
  final Color fillColor;
  final Color baseColor;
  final int percentage;

  const ImageFilledMask({
    super.key,
    required this.imageUrl,
    required this.fillColor,
    required this.baseColor,
    required this.percentage,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ImageFilledMaskState();
}

class _ImageFilledMaskState extends ConsumerState<ImageFilledMask> {
  Timer? timer;
  double maxPercentage = 0;
  double currentPercentage = 0;

  @override
  void initState() {
    maxPercentage = Platform.isIOS
        ? widget.percentage.toDouble()
        : widget.percentage.toDouble() / 100;

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      timer = Timer.periodic(
        const Duration(milliseconds: 5),
        (timer) {
          final nextPercentage = currentPercentage + 0.15;

          if (currentPercentage < maxPercentage) {
            setState(() {
              currentPercentage = min(nextPercentage, maxPercentage);
            });
          }
        },
      );
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
    return Stack(
      children: [
        SvgPicture.asset(
          widget.imageUrl,
          color: widget.baseColor,
          height: 200,
          fit: BoxFit.contain,
        ),
        ShaderMask(
          key: ValueKey(currentPercentage),
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              widget.fillColor,
              widget.fillColor.withOpacity(0),
            ],
            stops: [
              currentPercentage,
              currentPercentage / 100,
            ],
          ).createShader(bounds),
          child: SvgPicture.asset(
            widget.imageUrl,
            fit: BoxFit.contain,
            height: 200,
          ),
        ),
      ],
    );
  }
}
