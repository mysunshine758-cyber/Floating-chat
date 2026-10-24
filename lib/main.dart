import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'display_over_other_apps_screen.dart';
import 'getting_started_screen.dart';
import 'home_screen.dart' as home;
import 'notification_access_screen.dart';
import 'native_event_hub.dart';
import 'splash_screen.dart';

void main() {
  runApp(const FloatingChatApp());
}

class FloatingChatApp extends StatefulWidget {
  const FloatingChatApp({super.key});

  @override
  State<FloatingChatApp> createState() => _FloatingChatAppState();
}

class _FloatingChatAppState extends State<FloatingChatApp> {
  late final FloatingChatThemeController _themeController;

  @override
  void initState() {
    super.initState();
    _themeController = FloatingChatThemeController();
    _themeController.load();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, _) => FloatingChatThemeScope(
        controller: _themeController,
        child: MaterialApp(
          title: 'Floating Chat Heads',
          debugShowCheckedModeBanner: false,
          theme: floatingChatTheme(Brightness.light),
          darkTheme: floatingChatTheme(Brightness.dark),
          themeMode: _themeController.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 250),
          themeAnimationCurve: Curves.easeInOut,
          home: Builder(
            builder: (context) => SplashScreen(
              onFinished: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => const _OnboardingScreen(),
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

class _OnboardingScreen extends StatelessWidget {
  const _OnboardingScreen();

  @override
  Widget build(BuildContext context) {
    return GettingStartedScreen(
      onGetStarted: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (notificationContext) => NotificationAccessScreen(
              onPermissionGranted: () async {
                await Navigator.of(notificationContext).push(
                  MaterialPageRoute<void>(
                    builder: (overlayContext) => DisplayOverOtherAppsScreen(
                      onBack: () => Navigator.of(overlayContext).pop(),
                      onPermissionGranted: () {
                        Navigator.of(overlayContext).pushAndRemoveUntil(
                          MaterialPageRoute<void>(
                            builder: (_) => const home.FloatingChatHomeScreen(),
                          ),
                          (_) => false,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class FloatingChatHomeScreen extends StatefulWidget {
  const FloatingChatHomeScreen({super.key});

  @override
  State<FloatingChatHomeScreen> createState() => _FloatingChatHomeScreenState();
}

class _FloatingChatHomeScreenState extends State<FloatingChatHomeScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel(
    'com.example.floating_chat/bubble',
  );

  bool _hasOverlayPermission = false;
  bool _hasNotificationPermission = false;
  bool _isBubbleActive = false;
  String? _errorMessage;

  // In-memory test display for Phase 2 notification detection
  final List<Map<String, dynamic>> _detectedNotifications = [];
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _notificationSubscription = FloatingChatNativeEvents.notifications.listen(
      _handleNativeNotification,
    );

    _checkAllStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllStatus();
    }
  }

  void _handleNativeNotification(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _detectedNotifications.removeWhere((item) => item['id'] == data['id']);
      _detectedNotifications.insert(0, data);
      if (_detectedNotifications.length > 20) {
        _detectedNotifications.removeLast();
      }
    });
  }

  Future<void> _checkAllStatus() async {
    try {
      final bool hasOverlay =
          await _channel.invokeMethod<bool>('checkOverlayPermission') ?? false;
      final bool hasNotif =
          await _channel.invokeMethod<bool>('checkNotificationPermission') ??
          false;
      final bool isRunning =
          await _channel.invokeMethod<bool>('isBubbleRunning') ?? false;

      // Sync recent notifications
      final List<dynamic>? recent = await _channel.invokeListMethod(
        'getRecentNotifications',
      );

      if (mounted) {
        setState(() {
          _hasOverlayPermission = hasOverlay;
          _hasNotificationPermission = hasNotif;
          _isBubbleActive = isRunning;
          _errorMessage = null;

          if (recent != null) {
            for (final item in recent) {
              if (item is Map) {
                final Map<String, dynamic> map = Map<String, dynamic>.from(
                  item,
                );
                if (!_detectedNotifications.any((n) => n['id'] == map['id'])) {
                  _detectedNotifications.add(map);
                }
              }
            }
            // Sort newest first
            _detectedNotifications.sort(
              (a, b) => ((b['timestamp'] as num?) ?? 0).compareTo(
                (a['timestamp'] as num?) ?? 0,
              ),
            );
          }
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Status check failed: ${e.message}';
        });
      }
    }
  }

  Future<void> _requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (e) {
      _showToast('Failed to open overlay settings: ${e.message}');
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } on PlatformException catch (e) {
      _showToast('Failed to open notification settings: ${e.message}');
    }
  }

  Future<void> _startBubble() async {
    if (!_hasOverlayPermission) {
      await _requestOverlayPermission();
      return;
    }

    try {
      await _channel.invokeMethod('startBubble');
      await _checkAllStatus();
      _showToast('Floating bubble active');
    } on PlatformException catch (e) {
      _showToast('Failed to start bubble: ${e.message}');
    }
  }

  Future<void> _stopBubble() async {
    try {
      await _channel.invokeMethod('stopBubble');
      await _checkAllStatus();
      _showToast('Floating bubble stopped');
    } on PlatformException catch (e) {
      _showToast('Failed to stop bubble: ${e.message}');
    }
  }

  Future<void> _clearTestNotifications() async {
    try {
      await _channel.invokeMethod('clearRecentNotifications');
      setState(() {
        _detectedNotifications.clear();
      });
      _showToast('Notification test list cleared');
    } on PlatformException catch (e) {
      _showToast('Failed to clear: ${e.message}');
    }
  }

  Future<void> _exportHistory() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'exportHistory',
      );
      if (result != null) _showToast('Local history backup exported');
    } on PlatformException catch (e) {
      _showToast('Export failed: ${e.message}');
    }
  }

  Future<void> _importHistory() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'importHistory',
      );
      if (result != null) {
        final messages = result['messages'] ?? 0;
        _showToast('Backup merged safely: $messages new messages');
      }
    } on PlatformException catch (e) {
      _showToast('Import rejected: ${e.message}');
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear local history?'),
        content: const Text(
          'This permanently removes messages observed by Floating Chat. '
          'It does not delete messages from WhatsApp, Telegram, Slack, or Messenger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _channel.invokeMethod('clearHistory');
      _showToast('Local observed-message history cleared');
    } on PlatformException catch (e) {
      _showToast('Could not clear history: ${e.message}');
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Floating Chat Heads',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        actions: [
          IconButton(
            tooltip: 'Refresh Status',
            icon: const Icon(Icons.refresh),
            onPressed: _checkAllStatus,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Permissions & Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _StatusRow(
                      label: 'Display over other apps',
                      isActive: _hasOverlayPermission,
                      activeText: 'Granted',
                      inactiveText: 'Required',
                    ),
                    const Divider(height: 18),
                    _StatusRow(
                      label: 'Notification Access',
                      isActive: _hasNotificationPermission,
                      activeText: 'Granted',
                      inactiveText: 'Required',
                    ),
                    const Divider(height: 18),
                    _StatusRow(
                      label: 'Floating Bubble Overlay',
                      isActive: _isBubbleActive,
                      activeText: 'Active',
                      inactiveText: 'Stopped',
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 16),

              // Permission action buttons
              if (!_hasOverlayPermission) ...[
                FilledButton.icon(
                  onPressed: _requestOverlayPermission,
                  icon: const Icon(Icons.layers_outlined),
                  label: const Text('Grant Overlay Permission'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              if (!_hasNotificationPermission) ...[
                FilledButton.tonalIcon(
                  onPressed: _requestNotificationPermission,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Grant Notification Access'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Bubble toggle buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isBubbleActive ? null : _startBubble,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Bubble'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1E88E5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isBubbleActive ? _stopBubble : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Bubble'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(
                          color: _isBubbleActive
                              ? Colors.red.shade300
                              : Colors.grey.shade300,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Local history',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Only messages observed from supported notifications are stored on this device. This is not complete source-app history.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _exportHistory,
                          icon: const Icon(Icons.upload_file, size: 18),
                          label: const Text('Export'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _importHistory,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Import'),
                        ),
                        TextButton.icon(
                          onPressed: _confirmClearHistory,
                          icon: const Icon(
                            Icons.delete_forever_outlined,
                            size: 18,
                          ),
                          label: const Text('Clear history'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Phase 2 Notification Test Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detected Chat Notifications',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Live monitor; supported messages are stored locally',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  if (_detectedNotifications.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearTestNotifications,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // Target Apps Pills
              const Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _AppPill(label: 'WhatsApp', color: Color(0xFF25D366)),
                  _AppPill(label: 'Telegram', color: Color(0xFF229ED9)),
                  _AppPill(label: 'Slack', color: Color(0xFF611F69)),
                  _AppPill(label: 'Messenger', color: Color(0xFF0084FF)),
                ],
              ),

              const SizedBox(height: 12),

              // Notifications List / Empty State
              if (_detectedNotifications.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 36,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.mark_chat_unread_outlined,
                        size: 44,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Waiting for notifications...',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _hasNotificationPermission
                            ? 'Send a test message from WhatsApp, Telegram, or Messenger to your phone to see it appear here.'
                            : 'Enable Notification Access above to allow notification detection.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _detectedNotifications.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = _detectedNotifications[index];
                    return _NotificationCard(item: item);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _NotificationCard({required this.item});

  Color _getAppColor(String appName) {
    switch (appName.toLowerCase()) {
      case 'whatsapp':
      case 'whatsapp business':
        return const Color(0xFF25D366);
      case 'telegram':
        return const Color(0xFF229ED9);
      case 'slack':
        return const Color(0xFF611F69);
      case 'messenger':
        return const Color(0xFF0084FF);
      default:
        return const Color(0xFF1E88E5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String appName = item['appName']?.toString() ?? 'App';
    final String title = item['title']?.toString() ?? '(No title)';
    final String text = item['text']?.toString() ?? '';
    final int timestamp = (item['timestamp'] as num?)?.toInt() ?? 0;
    final String timeStr = timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
              .toLocal()
              .toString()
              .split(' ')[1]
              .substring(0, 5)
        : '';

    final appColor = _getAppColor(appName);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: appColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: appColor.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: appColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    appName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: appColor,
                    ),
                  ),
                ],
              ),
              if (timeStr.isNotEmpty)
                Text(
                  timeStr,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Sender / Title
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),

          if (text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _AppPill extends StatelessWidget {
  final String label;
  final Color color;

  const _AppPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final bool isActive;
  final String activeText;
  final String inactiveText;

  const _StatusRow({
    required this.label,
    required this.isActive,
    required this.activeText,
    required this.inactiveText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        Row(
          children: [
            Icon(
              isActive ? Icons.check_circle : Icons.error_outline,
              size: 18,
              color: isActive ? Colors.green.shade600 : Colors.orange.shade700,
            ),
            const SizedBox(width: 6),
            Text(
              isActive ? activeText : inactiveText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? Colors.green.shade700
                    : Colors.orange.shade800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
