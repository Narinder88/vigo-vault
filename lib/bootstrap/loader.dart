import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

void setupLoader() {
  EasyLoading.instance
    ..loadingStyle = EasyLoadingStyle.custom
    ..textColor = Colors.white
    ..backgroundColor = Colors.black.withAlpha(154)
    ..indicatorColor = Colors.white
    ..boxShadow = []
    ..maskType = EasyLoadingMaskType.black
    ..indicatorWidget = const SpinKitWaveSpinner(
      color: Colors.white,
      waveColor: Colors.white,
    );
}
