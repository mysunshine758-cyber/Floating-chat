import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_bottom_navigation.dart';
import 'app_theme.dart';
import 'chats_screen.dart';
import 'settings_screen.dart';

class FloatingChatHomeScreen extends StatefulWidget {
  const FloatingChatHomeScreen({super.key});

  @override
  State<FloatingChatHomeScreen> createState() => _FloatingChatHomeScreenState();
}

class _FloatingChatHomeScreenState extends State<FloatingChatHomeScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.example.floating_chat/bubble');

  bool _loading = true;
  bool _hasOverlayPermission = false;
  bool _hasNotificationPermission = false;
  bool _listenerConnected = false;
  bool _bubbleRunning = false;
  FloatingChatTab _selectedTab = FloatingChatTab.home;
  int _conversationRefreshToken = 0;
  String _sourceMode = 'all';
  final Set<String> _selectedPackages = <String>{};
  List<_InstalledApp> _installedApps = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadState();
    }
  }

  Future<void> _loadState() async {
    try {
      final hasOverlay =
          await _channel.invokeMethod<bool>('checkOverlayPermission') ?? false;
      final hasNotification =
          await _channel.invokeMethod<bool>('checkNotificationPermission') ??
          false;
      var isRunning =
          await _channel.invokeMethod<bool>('isBubbleRunning') ?? false;
      final rawConfiguration = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getHomeConfiguration',
      );
      final configuration = rawConfiguration == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(rawConfiguration);
      final selected =
          (configuration['selectedPackages'] as List<dynamic>?)
              ?.map((value) => value.toString())
              .toSet() ??
          <String>{};
      final desiredEnabled = configuration['serviceEnabled'] == true;

      if (desiredEnabled && !isRunning && hasOverlay && hasNotification) {
        await _channel.invokeMethod<void>('startBubble');
        isRunning =
            await _channel.invokeMethod<bool>('isBubbleRunning') ?? true;
      }

      var installedApps = _installedApps;
      if (selected.isNotEmpty && installedApps.isEmpty) {
        installedApps = await _fetchInstalledApps();
      }

      if (!mounted) return;
      setState(() {
        _hasOverlayPermission = hasOverlay;
        _hasNotificationPermission = hasNotification;
        _listenerConnected = configuration['listenerConnected'] == true;
        _bubbleRunning = isRunning && hasOverlay && hasNotification;
        _sourceMode =
            configuration['sourceMode'] == 'custom' && selected.isNotEmpty
            ? 'custom'
            : 'all';
        _selectedPackages
          ..clear()
          ..addAll(selected);
        _installedApps = installedApps;
        _loading = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Could not load Home settings: ${error.message}');
    }
  }

  Future<List<_InstalledApp>> _fetchInstalledApps() async {
    final raw = await _channel.invokeListMethod<dynamic>('getInstalledApps');
    if (raw == null) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          final rawIcon = map['icon'];
          final icon = rawIcon is Uint8List
              ? rawIcon
              : Uint8List.fromList(
                  rawIcon is List ? rawIcon.cast<int>() : const <int>[],
                );
          return _InstalledApp(
            packageName: map['packageName']?.toString() ?? '',
            label: map['label']?.toString() ?? '',
            icon: icon,
          );
        })
        .where((app) => app.packageName.isNotEmpty)
        .toList();
  }

  Future<void> _setBubbleEnabled(bool enabled) async {
    if (enabled && (!_hasOverlayPermission || !_hasNotificationPermission)) {
      _showMessage(
        'Overlay and notification access are required before Floating Chat can start.',
      );
      return;
    }
    try {
      await _channel.invokeMethod<void>(enabled ? 'startBubble' : 'stopBubble');
      final running =
          await _channel.invokeMethod<bool>('isBubbleRunning') ?? enabled;
      if (!mounted) return;
      setState(() => _bubbleRunning = running && enabled);
    } on PlatformException catch (error) {
      _showMessage('Could not update Floating Chat: ${error.message}');
      await _loadState();
    }
  }

  Future<void> _openNotificationAccessSettings() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } on PlatformException catch (error) {
      _showMessage(
        error.message ?? 'Could not open notification access settings.',
      );
    }
  }

  Future<void> _setSourceMode(String mode) async {
    if (mode == _sourceMode) {
      _showMessage('Choose the other notification source mode to switch.');
      return;
    }
    if (mode == 'custom' && _selectedPackages.isEmpty) {
      await _openAppPicker();
      return;
    }
    try {
      await _channel.invokeMethod<void>('setNotificationSourceMode', {
        'mode': mode,
      });
      if (!mounted) return;
      setState(() => _sourceMode = mode);
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not change notification mode.');
    }
  }

  Future<void> _openAppPicker() async {
    try {
      final colors = context.floatingColors;
      var apps = _installedApps;
      if (apps.isEmpty) {
        apps = await _fetchInstalledApps();
        if (mounted) setState(() => _installedApps = apps);
      }
      if (!mounted) return;
      final initialSelection = Set<String>.from(_selectedPackages);
      final selection = await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: colors.background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          final selected = Set<String>.from(initialSelection);
          return StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.78,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.handle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Choose apps',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: apps.isEmpty
                          ? const Center(
                              child: Text('No launchable apps were found.'),
                            )
                          : ListView.builder(
                              itemCount: apps.length,
                              itemBuilder: (context, index) {
                                final app = apps[index];
                                final checked = selected.contains(
                                  app.packageName,
                                );
                                return CheckboxListTile(
                                  value: checked,
                                  activeColor: colors.accent,
                                  checkColor: const Color(0xFF171717),
                                  secondary: _AppIcon(app: app, size: 42),
                                  title: Text(app.label),
                                  subtitle: Text(
                                    app.packageName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onChanged: (value) {
                                    setSheetState(() {
                                      if (value == true) {
                                        selected.add(app.packageName);
                                      } else {
                                        selected.remove(app.packageName);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () => Navigator.pop(sheetContext, selected),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: const Color(0xFF171717),
                            disabledBackgroundColor: colors.controlInactive,
                          ),
                          child: const Text(
                            'Add selected apps',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (selection == null) return;
      await _persistSelection(selection, activateCustom: true);
    } on PlatformException catch (error) {
      _showMessage('Could not load installed apps: ${error.message}');
    }
  }

  Future<void> _removeApp(String packageName) async {
    final selection = Set<String>.from(_selectedPackages)..remove(packageName);
    await _persistSelection(selection, activateCustom: false);
  }

  Future<void> _persistSelection(
    Set<String> selection, {
    required bool activateCustom,
  }) async {
    try {
      await _channel.invokeMethod<void>('setSelectedPackages', {
        'packageNames': selection.toList(),
      });
      var mode = _sourceMode;
      if (activateCustom && selection.isNotEmpty) {
        await _channel.invokeMethod<void>('setNotificationSourceMode', {
          'mode': 'custom',
        });
        mode = 'custom';
      } else if (selection.isEmpty) {
        mode = 'all';
      }
      if (!mounted) return;
      setState(() {
        _selectedPackages
          ..clear()
          ..addAll(selection);
        _sourceMode = mode;
      });
    } on PlatformException catch (error) {
      _showMessage('Could not save selected apps: ${error.message}');
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
      if (result != null) {
        final messages = result['messages'] ?? 0;
        _showMessage('Backup imported: $messages new messages.');
        await _loadState();
      }
    } on PlatformException catch (error) {
      _showMessage('Import failed: ${error.message}');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _selectTab(FloatingChatTab tab) {
    if (tab == _selectedTab) return;
    setState(() {
      _selectedTab = tab;
      if (tab == FloatingChatTab.chats) _conversationRefreshToken++;
    });
    if (tab == FloatingChatTab.home) _loadState();
  }

  void _handleSettingsDataChanged() {
    if (!mounted) return;
    setState(() => _conversationRefreshToken++);
    _loadState();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final overlayStyle = floatingChatSystemUiStyle(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: colors.background,
        body: IndexedStack(
          index: _selectedTab.index,
          children: [
            SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth = constraints.maxWidth.clamp(0.0, 432.0);
                  final heroHeight = contentWidth * 326 / 390;
                  final cardsTop = contentWidth * 223 / 390;
                  return SingleChildScrollView(
                    key: const Key('home-scroll-view'),
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Center(
                      child: SizedBox(
                        width: contentWidth,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            SizedBox(
                              key: const Key('home-hero'),
                              width: contentWidth,
                              height: heroHeight,
                              child: Image.asset(
                                'assets/figma/home/hero_original_latest.png',
                                fit: BoxFit.cover,
                                alignment: const Alignment(0, -0.83),
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(20, cardsTop, 20, 0),
                              child: Column(
                                children: [
                                  _GlobalControlCard(
                                    enabled: _bubbleRunning,
                                    loading: _loading,
                                    onChanged: _setBubbleEnabled,
                                  ),
                                  if (!_loading &&
                                      (!_hasNotificationPermission ||
                                          !_listenerConnected)) ...[
                                    const SizedBox(height: 14),
                                    _NotificationHealthCard(
                                      notificationAccess:
                                          _hasNotificationPermission,
                                      listenerConnected: _listenerConnected,
                                      onOpenSettings:
                                          _openNotificationAccessSettings,
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  _ModeCard(
                                    asset: 'assets/figma/home/listen_all.svg',
                                    title: 'Listen to all apps',
                                    description: 'Get notifications from all chatting apps on your device.',
                                    enabled: _sourceMode == 'all',
                                    onChanged: (_) => _setSourceMode('all'),
                                  ),
                                  const SizedBox(height: 14),
                                  _CustomAppsCard(
                                    enabled: _sourceMode == 'custom',
                                    selectedApps: _selectedApps,
                                    onChanged: (_) => _setSourceMode('custom'),
                                    onAdd: _openAppPicker,
                                    onRemove: _removeApp,
                                  ),
                                  const SizedBox(height: 14),
                                  _BackupCard(
                                    onExport: _exportHistory,
                                    onImport: _importHistory,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            ChatsScreen(
              key: const Key('embedded-chats-screen'),
              homeBuilder: (_) => const FloatingChatHomeScreen(),
              embedded: true,
              refreshToken: _conversationRefreshToken,
            ),
            SettingsScreen(
              key: const Key('embedded-settings-screen'),
              onDataChanged: _handleSettingsDataChanged,
            ),
          ],
        ),
        bottomNavigationBar: FloatingChatBottomNavigation(
          selectedTab: _selectedTab,
          onHome: () => _selectTab(FloatingChatTab.home),
          onChats: () => _selectTab(FloatingChatTab.chats),
          onSettings: () => _selectTab(FloatingChatTab.settings),
          keyPrefix: 'home',
        ),
      ),
    );
  }

  List<_InstalledApp> get _selectedApps {
    final byPackage = {for (final app in _installedApps) app.packageName: app};
    return _selectedPackages
        .map(
          (packageName) =>
              byPackage[packageName] ??
              _InstalledApp(
                packageName: packageName,
                label: packageName.split('.').last,
                icon: Uint8List(0),
              ),
        )
        .toList();
  }
}

class _NotificationHealthCard extends StatelessWidget {
  const _NotificationHealthCard({
    required this.notificationAccess,
    required this.listenerConnected,
    required this.onOpenSettings,
  });

  final bool notificationAccess;
  final bool listenerConnected;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final description = !notificationAccess
        ? 'Notification access is disabled. Floating Chat cannot receive messages.'
        : 'Notification access is enabled, but Android has not connected the listener. Open settings and re-enable Floating Chat.';
    return Container(
      key: const Key('notification-health-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            color: colors.textPrimary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notification capture unavailable',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    height: 18 / 13,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  key: const Key('open-notification-access-settings'),
                  onPressed: onOpenSettings,
                  child: const Text('Open notification settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<BoxShadow> _cardShadow(FloatingChatColors colors) => [
  BoxShadow(color: colors.shadow, blurRadius: 3, offset: const Offset(0, 1)),
  BoxShadow(color: colors.shadow, blurRadius: 10, offset: const Offset(0, 2)),
];

class _GlobalControlCard extends StatelessWidget {
  const _GlobalControlCard({
    required this.enabled,
    required this.loading,
    required this.onChanged,
  });

  final bool enabled;
  final bool loading;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      key: const Key('global-floating-chat-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.accentSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accentBorder),
        boxShadow: _cardShadow(colors),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
            child: SvgPicture.asset(
              'assets/figma/home/power.svg',
              width: 24,
              height: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: _ControlCopy(
              title: 'Floating chat',
              description:
                  'Turn on to enable floating chat\nand read notifications.',
              titleWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          _FigmaToggle(
            key: const Key('global-floating-chat-toggle'),
            value: enabled,
            onChanged: loading ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.asset,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

  final String asset;
  final String title;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Row(
        children: [
          SvgPicture.asset(asset, width: 50, height: 50),
          const SizedBox(width: 14),
          Expanded(
            child: _ControlCopy(title: title, description: description),
          ),
          const SizedBox(width: 8),
          _FigmaToggle(
            key: Key('${title.toLowerCase().replaceAll(' ', '-')}-toggle'),
            value: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _CustomAppsCard extends StatelessWidget {
  const _CustomAppsCard({
    required this.enabled,
    required this.selectedApps,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
  });

  final bool enabled;
  final List<_InstalledApp> selectedApps;
  final ValueChanged<bool> onChanged;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      containerKey: const Key('custom-apps-card'),
      child: Column(
        children: [
          Row(
            key: const Key('custom-apps-header'),
            children: [
              SvgPicture.asset(
                'assets/figma/home/custom_apps.svg',
                key: const Key('custom-apps-header-icon'),
                width: 50,
                height: 52,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: _ControlCopy(
                  title: 'Custom apps',
                  description:
                      'Get notifications only from your selected apps.',
                ),
              ),
              const SizedBox(width: 8),
              _FigmaToggle(
                key: const Key('custom-apps-toggle'),
                value: enabled,
                onChanged: onChanged,
              ),
            ],
          ),
          const SizedBox(height: 32),
          _CustomAppsGrid(
            selectedApps: selectedApps,
            onAdd: onAdd,
            onRemove: onRemove,
          ),
        ],
      ),
    );
  }
}

class _CustomAppsGrid extends StatelessWidget {
  const _CustomAppsGrid({
    required this.selectedApps,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_InstalledApp> selectedApps;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _AddAppButton(onTap: onAdd),
      for (final app in selectedApps)
        _SelectedApp(
          key: Key('selected-app-${app.packageName}'),
          app: app,
          onRemove: () => onRemove(app.packageName),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const itemSize = 54.0;
        final columnGap = ((constraints.maxWidth - (itemSize * 4)) / 3)
            .clamp(0.0, double.infinity)
            .toDouble();
        return SizedBox(
          key: const Key('custom-apps-grid'),
          width: constraints.maxWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(spacing: columnGap, runSpacing: 12, children: items),
          ),
        );
      },
    );
  }
}

class _ControlCopy extends StatelessWidget {
  const _ControlCopy({
    required this.title,
    required this.description,
    this.titleWeight = FontWeight.w600,
  });

  final String title;
  final String description;
  final FontWeight titleWeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            height: 23.38 / 17,
            fontWeight: titleWeight,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 1.125),
        Text(
          description,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            height: 16.25 / 12,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({this.containerKey, required this.child});

  final Key? containerKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      key: containerKey,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _cardShadow(colors),
      ),
      child: child,
    );
  }
}

class _FigmaToggle extends StatelessWidget {
  const _FigmaToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 52,
          height: 32,
          padding: const EdgeInsets.all(3.5),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value ? colors.accent : colors.controlInactive,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 25,
            height: 25,
            decoration: BoxDecoration(
              color: colors.switchThumb,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddAppButton extends StatelessWidget {
  const _AddAppButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Semantics(
      label: 'Add custom apps',
      button: true,
      child: InkWell(
        key: const Key('add-custom-app'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 54,
          height: 54,
          child: CustomPaint(
            painter: _DashedCirclePainter(colors.textSecondary),
            child: Center(
              child: SvgPicture.asset(
                'assets/figma/home/add.svg',
                width: 24,
                height: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Offset.zero & size;
    const dash = 0.23;
    const gap = 0.15;
    var start = 0.0;
    while (start < 6.2832) {
      canvas.drawArc(rect.deflate(1), start, dash, false, paint);
      start += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      color != oldDelegate.color;
}

class _SelectedApp extends StatelessWidget {
  const _SelectedApp({super.key, required this.app, required this.onRemove});

  final _InstalledApp app;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _AppIcon(app: app, size: 54),
          Positioned(
            right: -6,
            top: -6,
            child: Semantics(
              label: 'Remove ${app.label}',
              button: true,
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: Container(
                  key: Key('remove-app-${app.packageName}'),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colors.controlInactive,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(Icons.close, size: 14, color: colors.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app, required this.size});

  final _InstalledApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: ColoredBox(
          color: colors.surface,
          child: app.icon.isNotEmpty
              ? Image.memory(
                  app.icon,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                )
              : Container(
                  alignment: Alignment.center,
                  color: colors.accent,
                  child: Text(
                    app.label.isEmpty ? '?' : app.label.characters.first,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: size * 0.34,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF171717),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  const _BackupCard({required this.onExport, required this.onImport});

  final VoidCallback onExport;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      containerKey: const Key('backup-card'),
      child: Column(
        children: [
          _BackupRow(
            asset: 'assets/figma/home/export.svg',
            title: 'Backup & Export',
            description: 'Save your data to a file.',
            padding: const EdgeInsets.only(right: 8, bottom: 16),
            showDivider: true,
            onTap: onExport,
          ),
          _BackupRow(
            asset: 'assets/figma/home/import.svg',
            title: 'Import',
            description: 'Restore your data from a file.',
            padding: const EdgeInsets.only(top: 16, right: 8),
            onTap: onImport,
          ),
        ],
      ),
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.asset,
    required this.title,
    required this.description,
    required this.onTap,
    this.padding = EdgeInsets.zero,
    this.showDivider = false,
  });

  final String asset;
  final String title;
  final String description;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      padding: padding,
      decoration: showDivider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.divider)),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(asset, width: 24, height: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _ControlCopy(title: title, description: description),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstalledApp {
  const _InstalledApp({
    required this.packageName,
    required this.label,
    required this.icon,
  });

  final String packageName;
  final String label;
  final Uint8List icon;
}
