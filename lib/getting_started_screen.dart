import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';

class GettingStartedScreen extends StatelessWidget {
  const GettingStartedScreen({required this.onGetStarted, super.key});

  final VoidCallback onGetStarted;

  static const _assetRoot = 'assets/figma/getting_started';

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
              center: Alignment(0, -0.44),
              radius: 0.88,
              colors: [
                colors.accent.withValues(alpha: 0.08),
                colors.accent.withValues(alpha: 0),
              ],
              stops: const [0, 0.7],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _Hero(),
                              const SizedBox(height: 8),
                              const _Heading(),
                              const SizedBox(height: 74),
                              const _FeatureList(),
                              const Spacer(),
                              _Footer(onGetStarted: onGetStarted),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AspectRatio(
        aspectRatio: 350 / 233,
        child: Image.asset(
          '${GettingStartedScreen._assetRoot}/hero.png',
          fit: BoxFit.cover,
          semanticLabel: 'Two cheerful floating chat bubbles',
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading();

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            'Floating Chat',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontFamily: 'Poppins',
              fontSize: 42,
              fontWeight: FontWeight.w600,
              height: 55 / 42,
              letterSpacing: -1.1004,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your conversations, always within reach.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontFamily: 'Manrope',
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.5,
              letterSpacing: 0.1008,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          _FeatureRow(
            iconName: 'quick_replies.svg',
            iconLabel: 'Quick replies',
            title: 'Quick replies',
            description: 'Respond without leaving your\ncurrent app.',
          ),
          SizedBox(height: 24),
          _FeatureRow(
            iconName: 'all_chats.svg',
            iconLabel: 'All your chats',
            title: 'All your chats',
            description: 'Keep multiple conversations\ntogether.',
          ),
          SizedBox(height: 24),
          _FeatureRow(
            iconName: 'private_local.svg',
            iconLabel: 'Private and local',
            title: 'Private & local',
            description: 'Your data stays on your device.',
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.iconName,
    required this.iconLabel,
    required this.title,
    required this.description,
  });

  final String iconName;
  final String iconLabel;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            '${GettingStartedScreen._assetRoot}/$iconName',
            width: 32,
            height: 32,
            semanticsLabel: iconLabel,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 26.13 / 19,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                  letterSpacing: 0.1008,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PageDot(isActive: true),
              SizedBox(width: 10),
              _PageDot(),
              SizedBox(width: 10),
              _PageDot(),
            ],
          ),
          const SizedBox(height: 28),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(9999),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(9999),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onGetStarted,
                child: SizedBox(
                  height: 62,
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Get Started',
                        style: TextStyle(
                          color: Color(0xFF121212),
                          fontFamily: 'Poppins',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SvgPicture.asset(
                        '${GettingStartedScreen._assetRoot}/arrow_right.svg',
                        width: 24,
                        height: 24,
                        semanticsLabel: 'Continue',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDot extends StatelessWidget {
  const _PageDot({this.isActive = false});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: isActive ? colors.textPrimary : colors.controlInactive,
        shape: BoxShape.circle,
      ),
    );
  }
}
