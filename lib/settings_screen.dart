import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.onDataChanged});

  final VoidCallback onDataChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _channel = MethodChannel('com.example.floating_chat/bubble');

  bool _loading = true;
  bool _showUnreadCount = true;
  int _maxVisibleBubbles = 3;
  String _bubbleSize = 'medium';
  bool _snapToEdges = true;
  bool _vibrationFeedback = true;
  FloatingChatThemePreference _theme = FloatingChatThemePreference.light;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getSettingsConfiguration',
      );
      final settings = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(raw);
      if (!mounted) return;
      setState(() {
        _theme = FloatingChatThemePreferenceLabel.fromStorage(
          settings['theme'],
        );
        _showUnreadCount = settings['showUnreadCount'] != false;
        _maxVisibleBubbles =
            ((settings['maxVisibleBubbles'] as num?)?.toInt() ?? 3)
                .clamp(1, 5)
                .toInt();
        _bubbleSize = switch (settings['bubbleSize']) {
          'small' => 'small',
          'large' => 'large',
          _ => 'medium',
        };
        _snapToEdges = settings['snapToEdges'] != false;
        _vibrationFeedback = settings['vibrationFeedback'] != false;
        _loading = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Could not load Settings: ${error.message}');
    }
  }

  Future<bool> _saveSetting(String key, Object value) async {
    try {
      await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'setSettingsConfiguration',
        <String, Object>{'key': key, 'value': value},
      );
      return true;
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not save this setting.');
      return false;
    }
  }

  Future<void> _setShowUnreadCount(bool value) async {
    if (await _saveSetting('showUnreadCount', value) && mounted) {
      setState(() => _showUnreadCount = value);
    }
  }

  Future<void> _setSnapToEdges(bool value) async {
    if (await _saveSetting('snapToEdges', value) && mounted) {
      setState(() => _snapToEdges = value);
    }
  }

  Future<void> _setVibrationFeedback(bool value) async {
    if (await _saveSetting('vibrationFeedback', value) && mounted) {
      setState(() => _vibrationFeedback = value);
    }
  }

  Future<void> _chooseTheme() async {
    final selected = await showModalBottomSheet<FloatingChatThemePreference>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.floatingColors.scrim,
      builder: (context) => _ThemeChoiceSheet(selectedValue: _theme),
    );
    if (selected == null || selected == _theme || !mounted) return;

    final controller = FloatingChatThemeScope.maybeOf(context);
    final saved = controller != null
        ? await controller.setPreference(selected)
        : await _saveSetting('theme', selected.storageValue);
    if (!mounted) return;
    if (saved) {
      setState(() => _theme = selected);
    } else {
      _showMessage('Could not save the selected theme.');
    }
  }

  Future<void> _chooseMaxVisibleBubbles() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.floatingColors.scrim,
      builder: (context) => _SettingsChoiceSheet<int>(
        iconAsset: 'assets/figma/settings/max_bubbles.svg',
        title: 'Max visible bubbles',
        description: 'Set how many floating bubbles can appear on your screen at the same time.',
        options: [for (var value = 1; value <= 5; value++) value],
        selectedValue: _maxVisibleBubbles,
        labelFor: (value) => '$value',
      ),
    );
    if (selected == null || selected == _maxVisibleBubbles) return;
    if (await _saveSetting('maxVisibleBubbles', selected) && mounted) {
      setState(() => _maxVisibleBubbles = selected);
    }
  }

  Future<void> _chooseBubbleSize() async {
    const sizes = <String, String>{
      'small': 'Small',
      'medium': 'Medium',
      'large': 'Large',
    };
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.floatingColors.scrim,
      builder: (context) => _SettingsChoiceSheet<String>(
        iconAsset: 'assets/figma/settings/bubble_size.svg',
        title: 'Bubble size',
        description: 'Choose the size of floating bubbles.',
        options: sizes.keys.toList(),
        selectedValue: _bubbleSize,
        labelFor: (value) => sizes[value]!,
      ),
    );
    if (selected == null || selected == _bubbleSize) return;
    if (await _saveSetting('bubbleSize', selected) && mounted) {
      setState(() => _bubbleSize = selected);
    }
  }

  Future<void> _exportHistory() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'exportHistory',
      );
      if (result != null) _showMessage('Backup exported successfully.');
    } on PlatformException catch (error) {
      _showMessage('Export failed: ${error.message}');
    }
  }

  Future<void> _importHistory() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'importHistory',
      );
      if (result == null) return;
      final messages = result['messages'] ?? 0;
      _showMessage('Backup imported: $messages new messages.');
      widget.onDataChanged();
      await _loadSettings();
    } on PlatformException catch (error) {
      _showMessage('Import failed: ${error.message}');
    }
  }

  Future<void> _clearHistory() async {
    final cleared = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: context.floatingColors.scrim,
      builder: (context) => _ClearHistoryDialog(
        onConfirm: () => _channel.invokeMethod<void>('clearHistory'),
      ),
    );
    if (cleared != true || !mounted) return;
    widget.onDataChanged();
    _showMessage('Conversation history cleared.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  String get _bubbleSizeLabel => switch (_bubbleSize) {
    'small' => 'Small',
    'large' => 'Large',
    _ => 'Medium',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 432),
          child: SingleChildScrollView(
            key: const Key('settings-scroll-view'),
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
            child: IgnorePointer(
              ignoring: _loading,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingsSection(
                    title: 'Appearance',
                    card: _SettingsCard(
                      key: const Key('settings-appearance-card'),
                      children: [
                        _SettingsRow(
                          key: const Key('settings-theme-row'),
                          asset: 'assets/figma/settings/theme.svg',
                          label: 'Theme',
                          value: _theme.label,
                          onTap: _chooseTheme,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SettingsSection(
                    title: 'Bubble Settings',
                    card: _SettingsCard(
                      key: const Key('settings-bubble-card'),
                      children: [
                        _SettingsRow(
                          asset: 'assets/figma/settings/unread_count.svg',
                          label: 'Show unread count',
                          trailing: _SettingsSwitch(
                            key: const Key('show-unread-count-switch'),
                            value: _showUnreadCount,
                            onChanged: _setShowUnreadCount,
                          ),
                        ),
                        _SettingsRow(
                          key: const Key('max-visible-bubbles-row'),
                          asset: 'assets/figma/settings/max_bubbles.svg',
                          label: 'Max visible bubbles',
                          value: '$_maxVisibleBubbles',
                          onTap: _chooseMaxVisibleBubbles,
                        ),
                        _SettingsRow(
                          key: const Key('bubble-size-row'),
                          asset: 'assets/figma/settings/bubble_size.svg',
                          label: 'Bubble size',
                          value: _bubbleSizeLabel,
                          onTap: _chooseBubbleSize,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SettingsSection(
                    title: 'Behavior',
                    card: _SettingsCard(
                      key: const Key('settings-behavior-card'),
                      children: [
                        _SettingsRow(
                          asset: 'assets/figma/settings/snap_edges.svg',
                          label: 'Snap to edges',
                          trailing: _SettingsSwitch(
                            key: const Key('snap-to-edges-switch'),
                            value: _snapToEdges,
                            onChanged: _setSnapToEdges,
                          ),
                        ),
                        _SettingsRow(
                          asset: 'assets/figma/settings/vibration.svg',
                          label: 'Vibration feedback',
                          trailing: _SettingsSwitch(
                            key: const Key('vibration-feedback-switch'),
                            value: _vibrationFeedback,
                            onChanged: _setVibrationFeedback,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SettingsSection(
                    title: 'Data',
                    card: _SettingsCard(
                      key: const Key('settings-data-card'),
                      children: [
                        _SettingsRow(
                          key: const Key('settings-export-row'),
                          asset: 'assets/figma/settings/backup_export.svg',
                          label: 'Backup & Export',
                          onTap: _exportHistory,
                        ),
                        _SettingsRow(
                          key: const Key('settings-import-row'),
                          asset: 'assets/figma/settings/import.svg',
                          label: 'Import',
                          onTap: _importHistory,
                        ),
                        _SettingsRow(
                          key: const Key('settings-clear-history-row'),
                          asset: 'assets/figma/settings/clear_history.svg',
                          label: 'Clear History',
                          onTap: _clearHistory,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearHistoryDialog extends StatefulWidget {
  const _ClearHistoryDialog({required this.onConfirm});

  final Future<void> Function() onConfirm;

  @override
  State<_ClearHistoryDialog> createState() => _ClearHistoryDialogState();
}

class _ClearHistoryDialogState extends State<_ClearHistoryDialog> {
  bool _deleting = false;
  String? _errorMessage;

  Future<void> _confirm() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _errorMessage = null;
    });

    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop(true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _errorMessage =
            error.message ?? 'Could not clear conversation history.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _errorMessage =
            'Could not clear conversation history. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return PopScope(
      canPop: !_deleting,
      child: Dialog(
        key: const Key('clear-history-dialog'),
        elevation: 8,
        shadowColor: colors.shadow,
        backgroundColor: colors.dialogSurface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 92,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Positioned(
                        left: 10,
                        top: 21,
                        child: _DialogAccentDot(size: 7),
                      ),
                      const Positioned(
                        right: 9,
                        top: 19,
                        child: _DialogAccentDot(size: 6),
                      ),
                      Positioned(
                        left: 24,
                        top: 5,
                        child: _DialogAccentDot(
                          size: 9,
                          color: colors.destructiveSurface,
                        ),
                      ),
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.destructiveSurface,
                          shape: BoxShape.circle,
                        ),
                        child: SvgPicture.asset(
                          'assets/figma/settings/clear_history.svg',
                          width: 28,
                          height: 28,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Clear conversation history?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This permanently removes locally stored conversations and messages. Your app selections and settings will stay unchanged.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    key: const Key('clear-history-error'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: colors.destructive,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          key: const Key('cancel-clear-history'),
                          onPressed: _deleting
                              ? null
                              : () => Navigator.pop(context, false),
                          style: FilledButton.styleFrom(
                            elevation: 0,
                            backgroundColor: colors.cancelSurface,
                            foregroundColor: colors.textSecondary,
                            disabledBackgroundColor: colors.cancelSurface,
                            disabledForegroundColor: colors.textSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          key: const Key('confirm-clear-history'),
                          onPressed: _deleting ? null : _confirm,
                          style: FilledButton.styleFrom(
                            elevation: 0,
                            backgroundColor: colors.destructiveButton,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: colors.destructiveButton,
                            disabledForegroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: _deleting
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Clear History',
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogAccentDot extends StatelessWidget {
  const _DialogAccentDot({required this.size, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? context.floatingColors.accent,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.card});

  final String title;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 17,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 10),
        card,
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: colors.shadow, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0)
                  Divider(height: 1, thickness: 1, color: colors.divider),
                children[index],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
    required this.asset,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
  }) : assert(value == null || trailing == null);

  final String asset;
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 28,
            child: Center(
              child: SvgPicture.asset(
                asset,
                colorFilter: ColorFilter.mode(
                  label == 'Clear History'
                      ? colors.destructive
                      : colors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 17.5,
                height: 1.5,
                letterSpacing: -0.4375,
                fontWeight: FontWeight.w400,
                color: colors.textPrimary,
              ),
            ),
          ),
          ?trailing,
          if (trailing == null && onTap != null) ...[
            if (value != null)
              Text(
                value!,
                key: Key(
                  'settings-value-${label.toLowerCase().replaceAll(' ', '-')}',
                ),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                  color: colors.textSecondary,
                ),
              ),
            const SizedBox(width: 6),
            SvgPicture.asset(
              'assets/figma/settings/chevron_right.svg',
              colorFilter: ColorFilter.mode(
                colors.textSecondary,
                BlendMode.srcIn,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: SizedBox(
          width: 53,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                width: 53,
                height: 32,
                decoration: BoxDecoration(
                  color: value ? colors.accent : colors.controlInactive,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 4,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                left: value ? 24 : 2,
                top: 2.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.switchThumb,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: 27),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeChoiceSheet extends StatelessWidget {
  const _ThemeChoiceSheet({required this.selectedValue});

  final FloatingChatThemePreference selectedValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    const options = <(FloatingChatThemePreference, IconData)>[
      (FloatingChatThemePreference.light, Icons.light_mode_outlined),
      (FloatingChatThemePreference.dark, Icons.dark_mode_outlined),
      (FloatingChatThemePreference.system, Icons.desktop_windows_outlined),
    ];
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('theme-choice-sheet'),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                child: Container(
                  key: const Key('theme-sheet-drag-handle'),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.handle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accentSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.light_mode_outlined,
                    size: 30,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Theme',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 23,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Choose how the app looks.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  height: 1.42,
                  fontWeight: FontWeight.w400,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 22),
              for (var index = 0; index < options.length; index++) ...[
                _ThemeChoiceTile(
                  preference: options[index].$1,
                  icon: options[index].$2,
                  selected: options[index].$1 == selectedValue,
                ),
                if (index != options.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeChoiceTile extends StatelessWidget {
  const _ThemeChoiceTile({
    required this.preference,
    required this.icon,
    required this.selected,
  });

  final FloatingChatThemePreference preference;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: Key('theme-choice-${preference.storageValue}'),
        onTap: () => Navigator.pop(context, preference),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          key: Key('theme-choice-surface-${preference.storageValue}'),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: selected ? colors.selectionSurface : colors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.selectionBorder : colors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 28, color: colors.textPrimary),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  preference.label,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              _SelectionIndicator(
                key: Key('theme-choice-indicator-${preference.storageValue}'),
                selected: selected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsChoiceSheet<T> extends StatelessWidget {
  const _SettingsChoiceSheet({
    required this.iconAsset,
    required this.title,
    required this.description,
    required this.options,
    required this.selectedValue,
    required this.labelFor,
  });

  final String iconAsset;
  final String title;
  final String description;
  final List<T> options;
  final T selectedValue;
  final String Function(T value) labelFor;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('settings-choice-sheet'),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 18,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                child: Container(
                  key: const Key('settings-sheet-drag-handle'),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.handle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accentSurface,
                    shape: BoxShape.circle,
                  ),
                  child: SvgPicture.asset(
                    iconAsset,
                    colorFilter: ColorFilter.mode(
                      colors.textPrimary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 23,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  height: 1.42,
                  fontWeight: FontWeight.w400,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 22),
              for (var index = 0; index < options.length; index++) ...[
                _ChoiceTile<T>(
                  option: options[index],
                  label: labelFor(options[index]),
                  selected: options[index] == selectedValue,
                ),
                if (index != options.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.option,
    required this.label,
    required this.selected,
  });

  final T option;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final optionKey = option.toString().toLowerCase();
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: Key('settings-choice-$optionKey'),
        onTap: () => Navigator.pop(context, option),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          key: Key('settings-choice-surface-$optionKey'),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: selected ? colors.selectionSurface : colors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.selectionBorder : colors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              _SelectionIndicator(
                key: Key('settings-choice-indicator-$optionKey'),
                selected: selected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeInOut,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: selected ? colors.accent : Colors.transparent,
        shape: BoxShape.circle,
        border: selected ? null : Border.all(color: colors.border, width: 2),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 19, color: Colors.white)
          : null,
    );
  }
}
