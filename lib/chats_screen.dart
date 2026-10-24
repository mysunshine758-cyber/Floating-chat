import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_bottom_navigation.dart';
import 'app_theme.dart';
import 'conversation_details_screen.dart';
import 'conversation_models.dart';
import 'native_event_hub.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    super.key,
    required this.homeBuilder,
    this.embedded = false,
    this.refreshToken = 0,
  });

  final WidgetBuilder homeBuilder;
  final bool embedded;
  final int refreshToken;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.example.floating_chat/bubble');

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<ConversationSummary> _conversations = const [];
  bool _loading = true;
  bool _searching = false;
  String _query = '';
  String? _error;
  int _loadGeneration = 0;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationSubscription = FloatingChatNativeEvents.notifications.listen(
      (_) => _loadConversations(showLoading: false),
    );
    _loadConversations();
  }

  @override
  void didUpdateWidget(covariant ChatsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadConversations(showLoading: false);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadConversations(showLoading: false);
    }
  }

  Future<void> _loadConversations({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final raw = await _channel.invokeListMethod<dynamic>(
        'getConversationSummaries',
      );
      final conversations =
          (raw ?? const <dynamic>[])
              .whereType<Map<dynamic, dynamic>>()
              .map(
                (item) => ConversationSummary.fromMap(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((conversation) => conversation.id.isNotEmpty)
              .toList()
            ..sort((a, b) => b.latestTimestamp.compareTo(a.latestTimestamp));

      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _conversations = conversations;
        _loading = false;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error.message ?? 'Could not load local conversations.';
      });
    }
  }

  List<ConversationSummary> get _visibleConversations {
    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) return _conversations;
    return _conversations
        .where(
          (conversation) =>
              conversation.title.toLowerCase().contains(normalized) ||
              conversation.latestText.toLowerCase().contains(normalized) ||
              conversation.appName.toLowerCase().contains(normalized),
        )
        .toList();
  }

  void _startSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  void _openHome() {
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute<void>(builder: widget.homeBuilder));
  }

  void _showSettingsUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings is not available in the current app yet.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openConversation(ConversationSummary conversation) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConversationDetailsScreen(conversation: conversation),
      ),
    );
    if (mounted) await _loadConversations(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    if (widget.embedded) return content;

    final colors = context.floatingColors;
    final overlayStyle = floatingChatSystemUiStyle(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: colors.background,
        body: content,
        bottomNavigationBar: FloatingChatBottomNavigation(
          selectedTab: FloatingChatTab.chats,
          onHome: _openHome,
          onChats: () {},
          onSettings: _showSettingsUnavailable,
          keyPrefix: 'chats',
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 432),
          child: Column(
            children: [
              _ChatsHeader(
                searching: _searching,
                controller: _searchController,
                focusNode: _searchFocus,
                onSearch: _startSearch,
                onCloseSearch: _closeSearch,
                onChanged: (value) => setState(() => _query = value),
                onRefresh: () => _loadConversations(showLoading: false),
              ),
              Expanded(child: _buildConversationList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList() {
    final colors = context.floatingColors;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_error != null) {
      return _StatusMessage(
        title: 'Could not load conversations',
        description: _error!,
        actionLabel: 'Try again',
        onAction: _loadConversations,
      );
    }

    final conversations = _visibleConversations;
    if (conversations.isEmpty) {
      return _StatusMessage(
        title: _query.trim().isEmpty
            ? 'No conversations yet'
            : 'No conversations found',
        description: _query.trim().isEmpty
            ? 'Messages observed from supported notifications will appear here.'
            : 'Try a different name, app, or message.',
      );
    }

    return RefreshIndicator(
      color: colors.accent,
      onRefresh: () => _loadConversations(showLoading: false),
      child: ListView.separated(
        key: const Key('conversation-list'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        itemCount: conversations.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _ConversationCard(
          conversation: conversations[index],
          onTap: () => _openConversation(conversations[index]),
        ),
      ),
    );
  }
}

class _ChatsHeader extends StatelessWidget {
  const _ChatsHeader({
    required this.searching,
    required this.controller,
    required this.focusNode,
    required this.onSearch,
    required this.onCloseSearch,
    required this.onChanged,
    required this.onRefresh,
  });

  final bool searching;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSearch;
  final VoidCallback onCloseSearch;
  final ValueChanged<String> onChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('chats-header'),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
      child: searching
          ? _buildSearchHeader(context)
          : _buildDefaultHeader(context),
    );
  }

  Widget _buildDefaultHeader(BuildContext context) {
    final colors = context.floatingColors;
    return Row(
      children: [
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'All conversations',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              height: 31 / 20,
              letterSpacing: -0.774,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
        Tooltip(
          message: 'Search conversations',
          child: InkWell(
            key: const Key('chats-search-button'),
            onTap: onSearch,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: SvgPicture.asset(
                'assets/figma/chats/search.svg',
                width: 28,
                height: 28,
                colorFilter: ColorFilter.mode(
                  colors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
        PopupMenuButton<String>(
          key: const Key('chats-overflow-button'),
          tooltip: 'More options',
          onSelected: (value) {
            if (value == 'refresh') onRefresh();
          },
          itemBuilder: (_) => const [
            PopupMenuItem<String>(
              value: 'refresh',
              child: Text('Refresh conversations'),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
            child: SvgPicture.asset(
              'assets/figma/chats/more.svg',
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                colors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchHeader(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      key: const Key('chats-search-container'),
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? colors.border
              : const Color(0x33000000),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: IconButton(
              key: const Key('chats-search-back'),
              onPressed: onCloseSearch,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(Icons.arrow_back_rounded, size: 28, weight: 700),
              color: colors.textPrimary,
              tooltip: 'Close search',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              key: const Key('chats-search-field'),
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search conversations',
                hintStyle: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: colors.textSecondary,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: 48)
                : IconButton(
                    key: const Key('chats-search-clear'),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                    color: colors.textPrimary,
                    tooltip: 'Clear search',
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.conversation, required this.onTap});

  final ConversationSummary conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Semantics(
      button: true,
      child: InkWell(
        key: Key('conversation-${conversation.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              _ConversationAvatar(conversation: conversation),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      conversation.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 19,
                        height: 23.75 / 19,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _MessagePreview(text: conversation.latestText),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTimestamp(context, conversation.latestTimestamp),
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        height: 19.5 / 13,
                        letterSpacing: -0.325,
                        color: colors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    if (conversation.unreadCount > 0)
                      Container(
                        key: Key('unread-${conversation.id}'),
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          conversation.unreadCount > 9
                              ? '9+'
                              : '${conversation.unreadCount}',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12,
                            height: 18 / 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF171717),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return SizedBox.square(
      dimension: 60,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipOval(
              child: conversation.avatar.isNotEmpty
                  ? Image.memory(
                      conversation.avatar,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    )
                  : Container(
                      color: colors.controlInactive,
                      alignment: Alignment.center,
                      child: Text(
                        conversation.fallbackInitial,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              key: Key('app-badge-${conversation.id}'),
              width: 24,
              height: 24,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: ClipOval(
                child: conversation.appIcon.isNotEmpty
                    ? Image.memory(
                        conversation.appIcon,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      )
                    : ColoredBox(
                        color: colors.accent,
                        child: Center(
                          child: Text(
                            conversation.appInitial,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF171717),
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

class _MessagePreview extends StatelessWidget {
  const _MessagePreview({required this.text});

  final String text;

  bool get _isPhoto {
    final normalized = text.trim().toLowerCase();
    return normalized == 'photo' ||
        normalized == 'image' ||
        normalized.startsWith('photo ') ||
        normalized.startsWith('image ') ||
        normalized.startsWith('📷');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final preview = text.trim().isEmpty ? 'No message preview available' : text;
    return Row(
      children: [
        if (_isPhoto) ...[
          SvgPicture.asset(
            'assets/figma/chats/photo.svg',
            width: 16,
            height: 16,
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 15,
              height: 22.5 / 15,
              fontWeight: FontWeight.w400,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                height: 1.45,
                color: colors.textSecondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatTimestamp(BuildContext context, int milliseconds) {
  if (milliseconds <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(date.year, date.month, date.day);
  final difference = today.difference(messageDay).inDays;

  if (difference == 0) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
  if (difference == 1) return 'Yesterday';
  if (difference > 1 && difference < 7) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[date.weekday - 1];
  }
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = (date.year % 100).toString().padLeft(2, '0');
  return '$day/$month/$year';
}
