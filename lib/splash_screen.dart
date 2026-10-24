import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import 'app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const String _logoAnimation = 'assets/lottie/logo_vector_motion.json';
  static const Duration _leadInDuration = Duration(milliseconds: 500);
  static const Duration _postAnimationHold = Duration(milliseconds: 100);
  static const double _maximumLogoSize = 200;
  static const double _minimumScreenPadding = 24;

  late final AnimationController _controller;
  Timer? _leadInTimer;
  Timer? _postAnimationTimer;
  bool _hasLoaded = false;
  bool _hasStarted = false;
  bool _hasFinished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_handleAnimationStatus);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _postAnimationTimer != null) {
      return;
    }

    _postAnimationTimer = Timer(_postAnimationHold, _finishSplash);
  }

  void _playAnimation(LottieComposition composition) {
    if (_hasLoaded) {
      return;
    }

    _hasLoaded = true;
    _controller.duration = composition.duration;
    _leadInTimer = Timer(_leadInDuration, () {
      if (!mounted || _hasStarted) {
        return;
      }

      _hasStarted = true;
      _controller.forward(from: 0);
    });
  }

  void _finishSplash() {
    if (!mounted || _hasFinished) {
      return;
    }

    _hasFinished = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _leadInTimer?.cancel();
    _postAnimationTimer?.cancel();
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final background = Theme.of(context).brightness == Brightness.dark
        ? colors.background
        : const Color(0xFFFEFCF3);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: floatingChatSystemUiStyle(context)
          .copyWith(systemNavigationBarColor: background),
      child: Scaffold(
        backgroundColor: background,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.65,
              colors: [
                colors.accent.withValues(alpha: 0.10),
                colors.accent.withValues(alpha: 0),
              ],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox.expand(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableSize = math.max(
                    0.0,
                    constraints.biggest.shortestSide -
                        (_minimumScreenPadding * 2),
                  );
                  final logoSize = math.min(_maximumLogoSize, availableSize);

                  return Center(
                    child: SizedBox.square(
                      dimension: logoSize,
                      child: Lottie.asset(
                        _logoAnimation,
                        controller: _controller,
                        fit: BoxFit.contain,
                        repeat: false,
                        onLoaded: _playAnimation,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
