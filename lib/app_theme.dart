import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum FloatingChatThemePreference { light, dark, system }

extension FloatingChatThemePreferenceLabel on FloatingChatThemePreference {
  String get storageValue => name;

  String get label => switch (this) {
    FloatingChatThemePreference.light => 'Light',
    FloatingChatThemePreference.dark => 'Dark',
    FloatingChatThemePreference.system => 'System',
  };

  ThemeMode get themeMode => switch (this) {
    FloatingChatThemePreference.light => ThemeMode.light,
    FloatingChatThemePreference.dark => ThemeMode.dark,
    FloatingChatThemePreference.system => ThemeMode.system,
  };

  static FloatingChatThemePreference fromStorage(Object? value) =>
      switch (value) {
        'dark' => FloatingChatThemePreference.dark,
        'system' => FloatingChatThemePreference.system,
        _ => FloatingChatThemePreference.light,
      };
}

class FloatingChatThemeController extends ChangeNotifier {
  FloatingChatThemeController({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.example.floating_chat/bubble');

  final MethodChannel _channel;
  FloatingChatThemePreference _preference = FloatingChatThemePreference.light;

  FloatingChatThemePreference get preference => _preference;
  ThemeMode get themeMode => _preference.themeMode;

  Future<void> load() async {
    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getSettingsConfiguration',
      );
      applyPersistedPreference(
        FloatingChatThemePreferenceLabel.fromStorage(raw?['theme']),
      );
    } on PlatformException {
      // Keep the safe light default if the native bridge is unavailable.
    }
  }

  Future<bool> setPreference(FloatingChatThemePreference preference) async {
    if (preference == _preference) return true;
    try {
      await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'setSettingsConfiguration',
        <String, Object>{'key': 'theme', 'value': preference.storageValue},
      );
      applyPersistedPreference(preference);
      return true;
    } on PlatformException {
      return false;
    }
  }

  void applyPersistedPreference(FloatingChatThemePreference preference) {
    if (_preference == preference) return;
    _preference = preference;
    notifyListeners();
  }
}

class FloatingChatThemeScope
    extends InheritedNotifier<FloatingChatThemeController> {
  const FloatingChatThemeScope({
    super.key,
    required FloatingChatThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static FloatingChatThemeController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FloatingChatThemeScope>()
        ?.notifier;
  }
}

@immutable
class FloatingChatColors extends ThemeExtension<FloatingChatColors> {
  const FloatingChatColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.divider,
    required this.accent,
    required this.accentSurface,
    required this.accentBorder,
    required this.controlInactive,
    required this.switchThumb,
    required this.handle,
    required this.destructive,
    required this.destructiveButton,
    required this.destructiveSurface,
    required this.cancelSurface,
    required this.dialogSurface,
    required this.selectionSurface,
    required this.selectionBorder,
    required this.scrim,
    required this.shadow,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color divider;
  final Color accent;
  final Color accentSurface;
  final Color accentBorder;
  final Color controlInactive;
  final Color switchThumb;
  final Color handle;
  final Color destructive;
  final Color destructiveButton;
  final Color destructiveSurface;
  final Color cancelSurface;
  final Color dialogSurface;
  final Color selectionSurface;
  final Color selectionBorder;
  final Color scrim;
  final Color shadow;

  static const light = FloatingChatColors(
    background: Color(0xFFFEFCF5),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFEFA),
    textPrimary: Color(0xFF171717),
    textSecondary: Color(0xFF686661),
    border: Color(0xFFE8E6E0),
    divider: Color(0xFFF2F0EA),
    accent: Color(0xFFFCD742),
    accentSurface: Color(0xFFFEF6CA),
    accentBorder: Color(0xFFFDE686),
    controlInactive: Color(0xFFE2DFD8),
    switchThumb: Color(0xFFFFFFFF),
    handle: Color(0xFF62666A),
    destructive: Color(0xFFE53935),
    destructiveButton: Color(0xFFFF2A2A),
    destructiveSurface: Color(0xFFFFEBEA),
    cancelSurface: Color(0xFFF0F0EE),
    dialogSurface: Color(0xFFFFFEFA),
    selectionSurface: Color(0xFFFFF8D9),
    selectionBorder: Color(0xFFFFE69C),
    scrim: Color(0x99000000),
    shadow: Color(0x0A000000),
  );

  static const dark = FloatingChatColors(
    background: Color(0xFF171611),
    surface: Color(0xFF23221D),
    surfaceElevated: Color(0xFF2B2A24),
    textPrimary: Color(0xFFF8F6EE),
    textSecondary: Color(0xFFB9B5A9),
    border: Color(0xFF454239),
    divider: Color(0xFF36342D),
    accent: Color(0xFFFCD742),
    accentSurface: Color(0xFF3E3715),
    accentBorder: Color(0xFF6D5F19),
    controlInactive: Color(0xFF4A4840),
    switchThumb: Color(0xFFF7F4EA),
    handle: Color(0xFFAAA79F),
    destructive: Color(0xFFFF7771),
    destructiveButton: Color(0xFFE94A45),
    destructiveSurface: Color(0xFF432725),
    cancelSurface: Color(0xFF393832),
    dialogSurface: Color(0xFF292821),
    selectionSurface: Color(0xFF3E3715),
    selectionBorder: Color(0xFF6D5F19),
    scrim: Color(0xB3000000),
    shadow: Color(0x52000000),
  );

  @override
  FloatingChatColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? divider,
    Color? accent,
    Color? accentSurface,
    Color? accentBorder,
    Color? controlInactive,
    Color? switchThumb,
    Color? handle,
    Color? destructive,
    Color? destructiveButton,
    Color? destructiveSurface,
    Color? cancelSurface,
    Color? dialogSurface,
    Color? selectionSurface,
    Color? selectionBorder,
    Color? scrim,
    Color? shadow,
  }) {
    return FloatingChatColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      accentSurface: accentSurface ?? this.accentSurface,
      accentBorder: accentBorder ?? this.accentBorder,
      controlInactive: controlInactive ?? this.controlInactive,
      switchThumb: switchThumb ?? this.switchThumb,
      handle: handle ?? this.handle,
      destructive: destructive ?? this.destructive,
      destructiveButton: destructiveButton ?? this.destructiveButton,
      destructiveSurface: destructiveSurface ?? this.destructiveSurface,
      cancelSurface: cancelSurface ?? this.cancelSurface,
      dialogSurface: dialogSurface ?? this.dialogSurface,
      selectionSurface: selectionSurface ?? this.selectionSurface,
      selectionBorder: selectionBorder ?? this.selectionBorder,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  FloatingChatColors lerp(covariant FloatingChatColors? other, double t) {
    if (other == null) return this;
    return FloatingChatColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSurface: Color.lerp(accentSurface, other.accentSurface, t)!,
      accentBorder: Color.lerp(accentBorder, other.accentBorder, t)!,
      controlInactive: Color.lerp(controlInactive, other.controlInactive, t)!,
      switchThumb: Color.lerp(switchThumb, other.switchThumb, t)!,
      handle: Color.lerp(handle, other.handle, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      destructiveButton: Color.lerp(
        destructiveButton,
        other.destructiveButton,
        t,
      )!,
      destructiveSurface: Color.lerp(
        destructiveSurface,
        other.destructiveSurface,
        t,
      )!,
      cancelSurface: Color.lerp(cancelSurface, other.cancelSurface, t)!,
      dialogSurface: Color.lerp(dialogSurface, other.dialogSurface, t)!,
      selectionSurface: Color.lerp(
        selectionSurface,
        other.selectionSurface,
        t,
      )!,
      selectionBorder: Color.lerp(selectionBorder, other.selectionBorder, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension FloatingChatThemeContext on BuildContext {
  FloatingChatColors get floatingColors {
    return Theme.of(this).extension<FloatingChatColors>() ??
        (Theme.of(this).brightness == Brightness.dark
            ? FloatingChatColors.dark
            : FloatingChatColors.light);
  }
}

ThemeData floatingChatTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? FloatingChatColors.dark
      : FloatingChatColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: const Color(0xFF171717),
    secondary: colors.accent,
    onSecondary: const Color(0xFF171717),
    error: colors.destructive,
    onError: Colors.white,
    surface: colors.surface,
    onSurface: colors.textPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.background,
    fontFamily: 'Manrope',
    extensions: <ThemeExtension<dynamic>>[colors],
    dividerColor: colors.divider,
    disabledColor: colors.controlInactive,
    dialogTheme: DialogThemeData(
      backgroundColor: colors.dialogSurface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.background,
      modalBackgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: colors.scrim,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surfaceElevated,
      contentTextStyle: TextStyle(color: colors.textPrimary),
      actionTextColor: colors.accent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: colors.textPrimary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: colors.textSecondary),
    ),
  );
}

SystemUiOverlayStyle floatingChatSystemUiStyle(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final colors = context.floatingColors;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: colors.background,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  );
}
