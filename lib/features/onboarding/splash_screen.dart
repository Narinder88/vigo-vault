import 'dart:async';

import 'package:fitness_snack_lock/constants/app_branding.dart';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const routeName = '/home';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _backgroundColor = Color(0xFF121212);

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _fadeController.forward();

    _navigationTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(SplashScreen.routeName);
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _MetallicLockEmblem(),
              const SizedBox(height: 36),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xFFB8B8B8),
                    Color(0xFFE8E8E8),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ).createShader(bounds),
                child: const Text(
                  kAppDisplayName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2.0,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetallicLockEmblem extends StatelessWidget {
  const _MetallicLockEmblem();

  static const _emblemSize = 210.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _emblemSize + 70,
      height: _emblemSize + 70,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: _emblemSize + 30,
            height: _emblemSize + 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.18),
                  blurRadius: 36,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.08),
                  blurRadius: 72,
                  spreadRadius: 14,
                ),
              ],
            ),
          ),
          Container(
            width: _emblemSize,
            height: _emblemSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(
                center: Alignment.center,
                startAngle: 0.6,
                endAngle: 6.4,
                colors: [
                  Color(0xFF1A1A1C),
                  Color(0xFF4A4A50),
                  Color(0xFF0E0E10),
                  Color(0xFF6E6E78),
                  Color(0xFF222226),
                  Color(0xFF3A3A40),
                  Color(0xFF141416),
                ],
                stops: [0.0, 0.16, 0.32, 0.48, 0.64, 0.82, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1.5,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.32, -0.42),
                      radius: 1.05,
                      colors: [
                        Colors.white.withValues(alpha: 0.18),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.42),
                      ],
                      stops: const [0.0, 0.42, 1.0],
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                ),
                Icon(
                  PhosphorIconsRegular.lockKey,
                  size: 85,
                  color: Colors.white.withValues(alpha: 0.94),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
