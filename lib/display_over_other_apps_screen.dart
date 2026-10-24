import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';

class DisplayOverOtherAppsScreen extends StatefulWidget {
  const DisplayOverOtherAppsScreen({
    required this.onPermissionGranted,
    this.onBack,
    super.key,
  });

  final VoidCallback onPermissionGranted;
  final VoidCallback? onBack;

  @override
  State<DisplayOverOtherAppsScreen> createState() =>
      _DisplayOverOtherAppsScreenState();
}

class _DisplayOverOtherAppsScreenState extends State<DisplayOverOtherAppsScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel(
    'com.example.floating_chat/bubble',
  );
  static const String _assetRoot = 'assets/figma/overlay_access';

  bool _isCheckingPermission = false;
  bool _didContinue = false;
  bool _isAwaitingSettingsReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isAwaitingSettingsReturn) {
      _isAwaitingSettingsReturn = false;
      _continueIfPermissionGranted();
    }
  }

  Future<void> _continueIfPermissionGranted() async {
    if (_isCheckingPermission || _didContinue) {
      return;
    }

    _isCheckingPermission = true;
    try {
      final isGranted =
          await _channel.invokeMethod<bool>('checkOverlayPermission') ?? false;
      if (mounted && isGranted && !_didContinue) {
        _didContinue = true;
        widget.onPermissionGranted();
      }
    } on PlatformException {
      // Keep the CTA available when the platform status cannot be read.
    } finally {
      _isCheckingPermission = false;
    }
  }

  Future<void> _openSettings() async {
    _isAwaitingSettingsReturn = true;
    try {
      await _channel.invokeMethod<void>('requestOverlayPermission');
    } on PlatformException catch (error) {
      _isAwaitingSettingsReturn = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open display settings: ${error.message}'),
        ),
      );
    }
  }

  void _goBack() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final background = Theme.of(context).brightness == Brightness.dark
        ? colors.background
        : const Color(0xFFFAF7EE);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: floatingChatSystemUiStyle(context)
          .copyWith(systemNavigationBarColor: background),
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        _HeaderContent(onBack: _goBack),
                        const Spacer(),
                        _HeroAndBottomContent(
                          width: constraints.maxWidth,
                          onOpenSettings: _openSettings,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeaderContent extends StatelessWidget {
  const _HeaderContent({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 23),
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: SvgPicture.asset(
                  '${_DisplayOverOtherAppsScreenState._assetRoot}/back_chevron.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    colors.textPrimary,
                    BlendMode.srcIn,
                  ),
                  semanticsLabel: 'Go back',
                ),
              ),
            ),
          ),
          Text(
            'Allow display over apps',
            style: TextStyle(
              color: colors.textPrimary,
              fontFamily: 'Poppins',
              fontSize: 26,
              fontWeight: FontWeight.w600,
              height: 34 / 26,
              letterSpacing: -0.8502,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'This permission lets Floating Chat show\n'
              'the chat bubble on top of other apps.',
              maxLines: 2,
              softWrap: false,
              style: TextStyle(
                color: colors.textSecondary,
                fontFamily: 'Manrope',
                fontSize: 17,
                fontWeight: FontWeight.w400,
                height: 23.38 / 17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroAndBottomContent extends StatelessWidget {
  const _HeroAndBottomContent({
    required this.width,
    required this.onOpenSettings,
  });

  final double width;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final heroWidth = width * 350 / 390;
    final heroHeight = width * 311 / 390;
    final heroToCardGap = width * 0.12 / 390;
    return Column(
      children: [
        SizedBox(
          height: heroHeight + heroToCardGap,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: heroWidth,
            maxWidth: heroWidth,
            minHeight: heroHeight,
            maxHeight: heroHeight,
            child: _CroppedHero(width: heroWidth, height: heroHeight),
          ),
        ),
        _BottomContent(onOpenSettings: onOpenSettings),
      ],
    );
  }
}

class _CroppedHero extends StatelessWidget {
  const _CroppedHero({required this.width, required this.height});

  static const double _cropWidth = 1;
  static const double _cropHeight = 0.7126749753952026;
  static const double _cropLeft = 0;
  static const double _cropTop = 0.07420717924833298;

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sourceWidth = width / _cropWidth;
    final sourceHeight = height / _cropHeight;
    return ClipRect(
      child: SizedBox(
        key: const Key('overlay-access-hero'),
        width: width,
        height: height,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: sourceWidth,
          maxWidth: sourceWidth,
          minHeight: sourceHeight,
          maxHeight: sourceHeight,
          child: Transform.translate(
            offset: Offset(-_cropLeft * sourceWidth, -_cropTop * sourceHeight),
            child: Image.asset(
              '${_DisplayOverOtherAppsScreenState._assetRoot}/hero_original_390.png',
              width: sourceWidth,
              height: sourceHeight,
              fit: BoxFit.fill,
              semanticLabel: 'Phone with a floating chat bubble',
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomContent extends StatelessWidget {
  const _BottomContent({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('overlay-access-benefits'),
            decoration: BoxDecoration(
              color: dark ? colors.surface : const Color(0xFFFCFBF7),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: dark ? colors.accentBorder : const Color(0x80FFF8E7),
              ),
              boxShadow: dark
                  ? [
                      BoxShadow(
                        color: colors.shadow,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                      BoxShadow(
                        color: colors.accent.withValues(alpha: 0.08),
                        blurRadius: 40,
                        spreadRadius: -10,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : const [
                      BoxShadow(
                        color: Color(0x05FFCE00),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                      BoxShadow(
                        color: Color(0x0DFFCE00),
                        blurRadius: 40,
                        spreadRadius: -10,
                        offset: Offset(0, 10),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 255.88),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const _FeaturePoint(
                        iconName: 'layers.svg',
                        iconLabel: 'Floating layers',
                        title: 'Floating bubble on any app',
                        description: 'Chat while using other apps.',
                        bottomPadding: 16,
                      ),
                      Divider(
                        height: 1,
                        color: dark ? colors.divider : const Color(0xFFF3EFE9),
                      ),
                      const _FeaturePoint(
                        iconName: 'move.svg',
                        iconLabel: 'Move and minimize',
                        title: 'Easy to move and minimize',
                        description: 'Drag to the side or bottom.',
                        topPadding: 16,
                        bottomPadding: 16,
                        descriptionLineHeight: 19.25 / 14,
                      ),
                      Divider(
                        height: 1,
                        color: dark ? colors.divider : const Color(0xFFF3EFE9),
                      ),
                      const _FeaturePoint(
                        iconName: 'settings.svg',
                        iconLabel: 'Android settings',
                        title: 'Turn this off anytime',
                        description: 'From Android settings.',
                        topPadding: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(9999),
                boxShadow: [
                  BoxShadow(
                    color: colors.accent.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(9999),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onOpenSettings,
                  child: const SizedBox(
                    key: Key('overlay-access-cta'),
                    height: 59,
                    child: Center(
                      child: Text(
                        'Open Settings',
                        style: TextStyle(
                          color: Colors.black,
                          fontFamily: 'Poppins',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 27 / 20,
                          letterSpacing: -0.45,
                        ),
                      ),
                    ),
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

class _FeaturePoint extends StatelessWidget {
  const _FeaturePoint({
    required this.iconName,
    required this.iconLabel,
    required this.title,
    required this.description,
    this.topPadding = 0,
    this.bottomPadding = 0,
    this.descriptionLineHeight = 17.5 / 14,
  });

  final String iconName;
  final String iconLabel;
  final String title;
  final String description;
  final double topPadding;
  final double bottomPadding;
  final double descriptionLineHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final iconBackground = Theme.of(context).brightness == Brightness.dark
        ? colors.accent
        : const Color(0xFFFFD626);
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: SvgPicture.asset(
              '${_DisplayOverOtherAppsScreenState._assetRoot}/$iconName',
              width: 24,
              height: 24,
              semanticsLabel: iconLabel,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      height: 23.38 / 18,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    description,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: descriptionLineHeight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
