import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';

enum FloatingChatTab { home, chats, settings }

class FloatingChatBottomNavigation extends StatelessWidget {
  static const animationDuration = Duration(milliseconds: 400);
  static const animationCurve = Curves.easeInOutCubic;

  const FloatingChatBottomNavigation({
    super.key,
    required this.selectedTab,
    required this.onHome,
    required this.onChats,
    required this.onSettings,
    required this.keyPrefix,
  });

  final FloatingChatTab selectedTab;
  final VoidCallback onHome;
  final VoidCallback onChats;
  final VoidCallback onSettings;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return ColoredBox(
      color: colors.background,
      child: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Container(
            key: Key('$keyPrefix-bottom-navigation'),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 20,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / 3;
                final alignment = switch (selectedTab) {
                  FloatingChatTab.home => Alignment.centerLeft,
                  FloatingChatTab.chats => Alignment.center,
                  FloatingChatTab.settings => Alignment.centerRight,
                };
                return SizedBox(
                  height: 54,
                  child: Stack(
                    children: [
                      AnimatedAlign(
                        key: Key('$keyPrefix-navigation-highlight'),
                        alignment: alignment,
                        duration: animationDuration,
                        curve: animationCurve,
                        child: SizedBox(
                          key: Key('$keyPrefix-navigation-highlight-box'),
                          width: itemWidth,
                          height: 54,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFFDE57E), Color(0xFFFCD742)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _NavigationItem(
                              key: Key('$keyPrefix-nav-home'),
                              asset: 'assets/figma/home/home.svg',
                              label: 'Home',
                              active: selectedTab == FloatingChatTab.home,
                              onTap: onHome,
                            ),
                          ),
                          Expanded(
                            child: _NavigationItem(
                              key: Key('$keyPrefix-nav-chats'),
                              asset: 'assets/figma/home/chats.svg',
                              label: 'Chats',
                              active: selectedTab == FloatingChatTab.chats,
                              onTap: onChats,
                            ),
                          ),
                          Expanded(
                            child: _NavigationItem(
                              key: Key('$keyPrefix-nav-settings'),
                              asset: 'assets/figma/home/settings.svg',
                              label: 'Settings',
                              active: selectedTab == FloatingChatTab.settings,
                              onTap: onSettings,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    super.key,
    required this.asset,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String asset;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = ((constraints.maxWidth - 60) / 2)
            .clamp(0.0, 18.0)
            .toDouble();
        return InkWell(
          onTap: active ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            height: 54,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(
                    end: active
                        ? const Color(0xFF171717)
                        : colors.textSecondary,
                  ),
                  duration: FloatingChatBottomNavigation.animationDuration,
                  curve: FloatingChatBottomNavigation.animationCurve,
                  builder: (context, color, _) => SvgPicture.asset(
                    asset,
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(
                      color ??
                          (active
                              ? const Color(0xFF171717)
                              : colors.textSecondary),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active
                        ? const Color(0xFF171717)
                        : colors.textSecondary,
                  ),
                  duration: FloatingChatBottomNavigation.animationDuration,
                  curve: FloatingChatBottomNavigation.animationCurve,
                  child: Text(label, maxLines: 1, softWrap: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
