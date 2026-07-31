import 'package:flutter/material.dart';
import 'package:gif_view/gif_view.dart';

Future<void> showUnlockPadlockSuccessDialog(BuildContext context) async {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.white,
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GifView.asset(
                'assets/icon_dancing_animation.gif',
                width: 150,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Your smart lock just unlocked.\nEnjoy your snack!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            ],
          ),
        ),
      );
    },
  );
  // await Future.delayed(const Duration(milliseconds: 10000));

  // if (cachedDialogContext != null && cachedDialogContext!.mounted) {
  //   Navigator.of(cachedDialogContext!).pop();
  // }
}
