import 'package:flutter/material.dart';

class SignalIndicator extends StatefulWidget {
  const SignalIndicator({
    super.key,
    required this.rssi,
    Color? color,
  }) : color = color ?? Colors.green;

  final int? rssi;
  final Color color;

  @override
  State<SignalIndicator> createState() => _SignalIndicatorState();
}

class _SignalIndicatorState extends State<SignalIndicator> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 2.0, 0.0),
              child: Container(
                width: 4.0,
                height: 7.0,
                decoration: BoxDecoration(
                  color: widget.rssi != -100 ? widget.color : Colors.black12,
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 2.0, 0.0),
              child: Container(
                width: 4.0,
                height: 11.0,
                decoration: BoxDecoration(
                  color: widget.rssi! >= -90 ? widget.color : Colors.black12,
                  borderRadius: BorderRadius.circular(10.0),
                  shape: BoxShape.rectangle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 2.0, 0.0),
              child: Container(
                width: 4.0,
                height: 14.0,
                decoration: BoxDecoration(
                  color: widget.rssi! >= -67 ? widget.color : Colors.black12,
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
            ),
            Container(
              width: 4.0,
              height: 17.0,
              decoration: BoxDecoration(
                color: widget.rssi! >= -55 ? widget.color : Colors.black12,
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
