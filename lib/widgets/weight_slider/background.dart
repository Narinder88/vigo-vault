import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WeightBackground extends StatelessWidget {
  final Widget? child;
  final double? height;

  const WeightBackground({super.key, this.child, this.height});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: <Widget>[
        Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(50.0),
          ),
          child: child,
        ),
        SvgPicture.asset(
          'assets/img_arrow.svg',
          color: Colors.teal,
        ),
      ],
    );
  }
}
