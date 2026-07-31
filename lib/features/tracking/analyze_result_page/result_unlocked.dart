import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gif_view/gif_view.dart';

class ResultUnlocked extends ConsumerWidget {
  const ResultUnlocked({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 260,
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage('assets/img_unlocking_bg.jpeg'),
          fit: BoxFit.cover,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GifView.asset(
                'assets/icon_padlock_animation.gif',
                width: 150,
              ),
              GifView.asset(
                'assets/icon_arrow_right_animation.gif',
                width: 80,
              ),
              GifView.asset(
                'assets/icon_snack_animation.gif',
                width: 150,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
