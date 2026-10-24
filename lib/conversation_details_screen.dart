import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';
import 'conversation_models.dart';
import 'native_event_hub.dart';

String _replyCapabilityDiagnostic(Map<String, dynamic> details) {
  String yesNo(Object? value) => value == true ? 'yes' : 'no';
  final code = details['stateCode']?.toString() ?? 'UNKNOWN';
  final captured = details['capturedSessionCount'] ?? 0;
  final active = details['activeNotificationCount'] ?? 0;
  final source = details['sourcePackageSessionCount'] ?? 0;
  final matched = details['matchedActiveSessions'] ?? 0;
  final retained = details['retainedReplySessionCount'] ?? 0;
  final pending = details['pendingIntentState']?.toString() ?? 'UNKNOWN';
  final lastSend = details['lastSendAttempt']?.toString() ?? 'NOT_ATTEMPTED';
  final captureSchema =
      details['captureDiagnosticSchema']?.toString() ?? 'capture-unknown';
  final captureStage =
      details['captureStageCode']?.toString() ?? 'NOT_OBSERVED';
  final captureReason =
      details['captureReasonCode']?.toString() ?? 'NO_SOURCE_EVENT';
  final capturePackage =
      details['capturePackageName']?.toString() ?? 'unknown-package';
  final captureActions = details['captureActionCount'] ?? -1;
  final captureRemoteInputs = details['captureRemoteInputActionCount'] ?? -1;
  final captureFreeForm = details['captureFreeFormActionCount'] ?? -1;
  return 'Status $code · access ${yesNo(details['notificationAccessGranted'])} · '
      'listener ${yesNo(details['listenerConnected'])} · '
      'sessions matched/source/captured $matched/$source/$captured · '
      'active $active · retained $retained · '
      'action ${yesNo(details['replyActionDiscovered'])} · '
      'RemoteInput ${yesNo(details['remoteInputDiscovered'])} · '
      'PendingIntent $pending · last send $lastSend · '
      '$captureSchema capture $captureStage/$captureReason · '
      'package $capturePackage · actions/RemoteInput/free-form '
      '$captureActions/$captureRemoteInputs/$captureFreeForm · '
      'stored ${yesNo(details['captureSessionStored'])}';
}

class ConversationDetailsScreen extends StatefulWidget {
  const ConversationDetailsScreen({super.key, required this.conversation});

  final ConversationSummary conversation;

  @override
  State<ConversationDetailsScreen> createState() =>
      _ConversationDetailsScreenState();
}

class _ConversationDetailsScreenState extends State<ConversationDetailsScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.example.floating_chat/bubble');

  final _replyController = TextEditingController();
  final _replyFocusNode = FocusNode();
  final _scrollController = ScrollController();

  List<ConversationMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _canReply = false;
  bool _canOpenConversation = false;
  bool _selectingAttachment = false;
  bool _recordingVoice = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  _ComposerAttachment? _attachment;
  String _replyUnavailableReason =
      'This notification does not currently provide a quick-reply action.';
  String _replyDiagnostic = 'Status UNKNOWN';
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationSubscription = FloatingChatNativeEvents.notifications.listen((
      event,
    ) {
      final eventConversationId = event['conversationId']?.toString();
      if (eventConversationId != null &&
          eventConversationId.isNotEmpty &&
          eventConversationId != widget.conversation.id) {
        return;
      }
      final wasNearBottom =
          !_scrollController.hasClients ||
          _scrollController.position.maxScrollExtent -
                  _scrollController.position.pixels <
              80;
      _loadMessages(showLoading: false, scrollToBottom: wasNearBottom);
    });
    _loadMessages(scrollToBottom: true);
  }

  @override
  void dispose() {
    _loadGeneration++;
    _recordingTimer?.cancel();
    _notificationSubscription?.cancel();
    if (_recordingVoice) {
      unawaited(_channel.invokeMethod<void>('cancelVoiceRecording'));
    }
    final attachment = _attachment;
    if (attachment != null) {
      unawaited(
        _channel.invokeMethod<void>('discardConversationAttachment', {
          'uri': attachment.uri,
        }),
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    _replyController.dispose();
    _replyFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMessages(showLoading: false, scrollToBottom: false);
    }
  }

  Future<void> _loadMessages({
    bool showLoading = true,
    bool scrollToBottom = false,
  }) async {
    final generation = ++_loadGeneration;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getConversationDetails',
        <String, Object>{'conversationId': widget.conversation.id},
      );
      final details = Map<String, dynamic>.from(raw ?? const {});
      final messages =
          (details['messages'] as List<dynamic>? ?? const [])
              .whereType<Map<dynamic, dynamic>>()
              .map(
                (item) => ConversationMessage.fromMap(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((message) => message.text.trim().isNotEmpty)
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _messages = messages;
        _canReply = details['canReply'] == true;
        _canOpenConversation = details['canOpenConversation'] == true;
        _replyUnavailableReason =
            details['replyUnavailableReason']?.toString() ?? 'This notification does not currently provide a quick-reply action.';
        _replyDiagnostic = _replyCapabilityDiagnostic(details);
        _loading = false;
        _error = null;
      });
      if (scrollToBottom) _scheduleScrollToBottom();
    } on PlatformException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error.message ?? 'Could not load this conversation.';
      });
    }
  }

  Future<void> _sendReply() async {
    if (_attachment != null) {
      await _offerExternalAttachmentShare();
      return;
    }
    final text = _replyController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final capability = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getConversationReplyCapability',
        <String, Object>{'conversationId': widget.conversation.id},
      );
      final capabilityDetails = Map<String, dynamic>.from(
        capability ?? const <dynamic, dynamic>{},
      );
      final canReplyNow = capabilityDetails['canReply'] == true;
      final canOpenNow = capabilityDetails['canOpenConversation'] == true;
      final unavailableReason =
          capabilityDetails['replyUnavailableReason']?.toString() ??
          'No active Android quick-reply action is available.';
      if (mounted) {
        setState(() {
          _canReply = canReplyNow;
          _canOpenConversation = canOpenNow;
          _replyUnavailableReason = unavailableReason;
          _replyDiagnostic = _replyCapabilityDiagnostic(capabilityDetails);
        });
      }
      if (!canReplyNow) {
        _showReplyUnavailableReason();
        return;
      }
      await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'sendConversationReply',
        <String, Object>{
          'conversationId': widget.conversation.id,
          'text': text,
        },
      );
      if (!mounted) return;
      _replyController.clear();
      await _loadMessages(showLoading: false, scrollToBottom: true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ??
                'The notification reply action is no longer available.',
          ),
        ),
      );
      await _loadMessages(showLoading: false, scrollToBottom: false);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showAttachmentOptions() async {
    if (_selectingAttachment || _recordingVoice || _sending) return;
    final colors = context.floatingColors;
    final selection = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: colors.background,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add attachment',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose an item to preview before opening the source app to share it.',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                height: 20 / 14,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              key: const Key('attachment-option-images'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photos and images'),
              onTap: () => Navigator.pop(context, 'image/*'),
            ),
            ListTile(
              key: const Key('attachment-option-files'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: const Text('Files and documents'),
              onTap: () => Navigator.pop(context, '*/*'),
            ),
          ],
        ),
      ),
    );
    if (selection != null) await _pickAttachment(selection);
  }

  Future<void> _pickAttachment(String mimeType) async {
    setState(() => _selectingAttachment = true);
    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'pickConversationAttachment',
        <String, Object>{'mimeType': mimeType},
      );
      if (!mounted || raw == null) return;
      final attachment = _ComposerAttachment.fromMap(
        Map<String, dynamic>.from(raw),
      );
      await _replaceAttachment(attachment);
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not open the attachment picker.');
    } finally {
      if (mounted) setState(() => _selectingAttachment = false);
    }
  }

  Future<void> _startVoiceRecording() async {
    if (_recordingVoice || _selectingAttachment || _sending) return;
    try {
      await _channel.invokeMethod<Map<dynamic, dynamic>>('startVoiceRecording');
      if (!mounted) return;
      setState(() {
        _recordingVoice = true;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordingDuration += const Duration(seconds: 1));
        }
      });
    } on PlatformException catch (error) {
      _showMessage(
        error.code == 'MICROPHONE_DENIED'
            ? 'Microphone permission is required to record a voice message.'
            : error.message ?? 'Could not start voice recording.',
      );
    }
  }

  Future<void> _stopVoiceRecording() async {
    if (!_recordingVoice) return;
    _recordingTimer?.cancel();
    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'stopVoiceRecording',
      );
      if (!mounted || raw == null) return;
      await _replaceAttachment(
        _ComposerAttachment.fromMap(Map<String, dynamic>.from(raw)),
      );
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not finish the voice recording.');
    } finally {
      if (mounted) {
        setState(() {
          _recordingVoice = false;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordingTimer?.cancel();
    try {
      await _channel.invokeMethod<void>('cancelVoiceRecording');
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not cancel the recording.');
    } finally {
      if (mounted) {
        setState(() {
          _recordingVoice = false;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  Future<void> _playVoicePreview() async {
    final attachment = _attachment;
    if (attachment == null || attachment.kind != 'voice') return;
    try {
      await _channel.invokeMethod<bool>('playVoicePreview', {
        'uri': attachment.uri,
      });
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not play the recording.');
    }
  }

  Future<void> _replaceAttachment(_ComposerAttachment attachment) async {
    final previous = _attachment;
    if (mounted) setState(() => _attachment = attachment);
    if (previous != null && previous.uri != attachment.uri) {
      await _discardAttachment(previous, updateUi: false);
    }
  }

  Future<void> _discardAttachment(
    _ComposerAttachment attachment, {
    bool updateUi = true,
  }) async {
    if (updateUi && mounted) setState(() => _attachment = null);
    try {
      await _channel.invokeMethod<void>('discardConversationAttachment', {
        'uri': attachment.uri,
      });
    } on PlatformException {
      // The app cache will still be reclaimed by Android.
    }
  }

  Future<void> _offerExternalAttachmentShare() async {
    final attachment = _attachment;
    if (attachment == null || _sending) return;
    final colors = context.floatingColors;
    final appName = widget.conversation.appName.trim().isEmpty
        ? 'the source app'
        : widget.conversation.appName.trim();
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish sharing in the source app'),
        content: Text(
          'Android notification replies cannot send ${attachment.kind == 'voice' ? 'voice recordings' : 'attachments'}. Open $appName to choose the conversation and finish sharing. Floating Chat will not mark it as sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: const Color(0xFF171717),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Open $appName'),
          ),
        ],
      ),
    );
    if (shouldOpen != true || !mounted) return;

    setState(() => _sending = true);
    try {
      await _channel.invokeMethod<bool>('shareConversationAttachment', {
        'conversationId': widget.conversation.id,
        'packageName': widget.conversation.packageName,
        'uri': attachment.uri,
        'mimeType': attachment.mimeType,
        'text': _replyController.text.trim(),
      });
      _showMessage(
        '$appName opened. Choose the recipient and send there; delivery cannot be confirmed here.',
      );
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not open $appName for sharing.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showReplyUnavailableReason() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$_replyUnavailableReason Your draft has been kept.\n$_replyDiagnostic',
        ),
        duration: const Duration(seconds: 5),
        action: _canOpenConversation
            ? SnackBarAction(
                label: 'OPEN APP',
                onPressed: () => unawaited(_openConversation()),
              )
            : null,
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _openConversation() async {
    try {
      await _channel.invokeMethod<bool>('openConversation', <String, Object>{
        'conversationId': widget.conversation.id,
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Could not open the source app.'),
        ),
      );
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: floatingChatSystemUiStyle(context),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: colors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 432),
              child: Column(
                children: [
                  _ConversationHeader(
                    conversation: widget.conversation,
                    canOpenConversation: _canOpenConversation,
                    onBack: () => Navigator.of(context).pop(),
                    onRefresh: () => _loadMessages(showLoading: false),
                    onOpenConversation: _openConversation,
                  ),
                  Expanded(child: _buildTimeline()),
                  _ReplyComposer(
                    controller: _replyController,
                    focusNode: _replyFocusNode,
                    canReply: _canReply,
                    sending: _sending,
                    selectingAttachment: _selectingAttachment,
                    recordingVoice: _recordingVoice,
                    recordingDuration: _recordingDuration,
                    attachment: _attachment,
                    replyUnavailableReason: _replyUnavailableReason,
                    replyDiagnostic: _replyDiagnostic,
                    onSend: _sendReply,
                    onShowReplyUnavailable: _showReplyUnavailableReason,
                    onAddAttachment: _showAttachmentOptions,
                    onStartVoiceRecording: _startVoiceRecording,
                    onStopVoiceRecording: _stopVoiceRecording,
                    onCancelVoiceRecording: _cancelVoiceRecording,
                    onPlayVoicePreview: _playVoicePreview,
                    onRemoveAttachment: () {
                      final attachment = _attachment;
                      if (attachment != null) {
                        unawaited(_discardAttachment(attachment));
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    final colors = context.floatingColors;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_error != null) {
      return _ConversationStatus(
        title: 'Could not load conversation',
        description: _error!,
        actionLabel: 'Try again',
        onAction: _loadMessages,
      );
    }
    if (_messages.isEmpty) {
      return const _ConversationStatus(
        title: 'No stored messages yet',
        description:
            'Messages observed from supported notifications will appear here.',
      );
    }

    return ListView.builder(
      key: const Key('conversation-timeline'),
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final previous = index == 0 ? null : _messages[index - 1];
        final showDate =
            previous == null ||
            !_isSameLocalDay(previous.timestamp, message.timestamp);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDate)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 4 : 16, bottom: 0),
                child: _DateBadge(timestamp: message.timestamp),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _MessageBubble(
                key: Key('conversation-message-$index'),
                message: message,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.conversation,
    required this.canOpenConversation,
    required this.onBack,
    required this.onRefresh,
    required this.onOpenConversation,
  });

  final ConversationSummary conversation;
  final bool canOpenConversation;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onOpenConversation;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      key: const Key('conversation-details-header'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          InkResponse(
            key: const Key('conversation-details-back'),
            onTap: onBack,
            radius: 24,
            child: SizedBox.square(
              dimension: 36,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SvgPicture.asset(
                  'assets/figma/conversation_details/back_chevron.svg',
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
          const SizedBox(width: 4),
          _HeaderAvatar(conversation: conversation),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 20,
                    height: 25 / 20,
                    letterSpacing: -0.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _HeaderAppBadge(conversation: conversation),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        conversation.appName.isEmpty
                            ? conversation.packageName
                            : conversation.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 14,
                          height: 20 / 14,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: const Key('conversation-details-menu'),
            tooltip: 'Conversation actions',
            onSelected: (value) {
              if (value == 'refresh') onRefresh();
              if (value == 'open') onOpenConversation();
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'refresh',
                child: Text('Refresh conversation'),
              ),
              if (canOpenConversation)
                const PopupMenuItem<String>(
                  value: 'open',
                  child: Text('Open in app'),
                ),
            ],
            child: SizedBox.square(
              dimension: 40,
              child: Center(
                child: SvgPicture.asset(
                  'assets/figma/conversation_details/overflow_menu.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    colors.textPrimary,
                    BlendMode.srcIn,
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

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      width: 56,
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.controlInactive,
        shape: BoxShape.circle,
        border: Border.all(color: colors.shadow),
      ),
      child: conversation.avatar.isNotEmpty
          ? Image.memory(
              conversation.avatar,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            )
          : Center(
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
    );
  }
}

class _HeaderAppBadge extends StatelessWidget {
  const _HeaderAppBadge({required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      width: 20,
      height: 20,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: colors.surface, width: 2),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipOval(
        child: conversation.appIcon.isNotEmpty
            ? Image.memory(
                conversation.appIcon,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              )
            : ColoredBox(
                color: colors.accent,
                child: Center(
                  child: Text(
                    conversation.appInitial,
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF171717),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.timestamp});

  final int timestamp;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.center,
      child: Container(
        key: Key('conversation-date-$timestamp'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: dark ? colors.surfaceElevated : const Color(0xFFECEAE4),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _formatDateLabel(timestamp),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({super.key, required this.message});

  final ConversationMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final outgoing = message.isOutgoing;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = outgoing
        ? colors.accent
        : dark
        ? colors.surfaceElevated
        : const Color(0xFFF2F2F2);
    final textColor = outgoing ? const Color(0xFF030712) : colors.textPrimary;
    final timestampColor = outgoing
        ? const Color(0xFF4B5563)
        : colors.textSecondary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = math.min(300.0, constraints.maxWidth * 0.82);
        return Align(
          alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: DecoratedBox(
              key: Key(
                outgoing
                    ? 'outgoing-message-bubble'
                    : 'incoming-message-bubble',
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(outgoing ? 16 : 2),
                  topRight: Radius.circular(outgoing ? 2 : 16),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: const Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: outgoing
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.text,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        height: 22 / 16,
                        fontWeight: FontWeight.w400,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatMessageTime(context, message.timestamp),
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 11,
                            height: 16.5 / 11,
                            letterSpacing: -0.275,
                            color: timestampColor,
                          ),
                        ),
                        if (outgoing && message.replyStatus != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: timestampColor,
                            semanticLabel: 'Reply handed to the source app; delivery unconfirmed',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.focusNode,
    required this.canReply,
    required this.sending,
    required this.selectingAttachment,
    required this.recordingVoice,
    required this.recordingDuration,
    required this.attachment,
    required this.replyUnavailableReason,
    required this.replyDiagnostic,
    required this.onSend,
    required this.onShowReplyUnavailable,
    required this.onAddAttachment,
    required this.onStartVoiceRecording,
    required this.onStopVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.onPlayVoicePreview,
    required this.onRemoveAttachment,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canReply;
  final bool sending;
  final bool selectingAttachment;
  final bool recordingVoice;
  final Duration recordingDuration;
  final _ComposerAttachment? attachment;
  final String replyUnavailableReason;
  final String replyDiagnostic;
  final VoidCallback onSend;
  final VoidCallback onShowReplyUnavailable;
  final VoidCallback onAddAttachment;
  final VoidCallback onStartVoiceRecording;
  final VoidCallback onStopVoiceRecording;
  final VoidCallback onCancelVoiceRecording;
  final VoidCallback onPlayVoicePreview;
  final VoidCallback onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconFilter = isDark
        ? ColorFilter.mode(colors.textPrimary, BlendMode.srcIn)
        : null;
    return Container(
      key: const Key('conversation-reply-composer'),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      color: colors.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recordingVoice)
            _VoiceRecordingBar(
              duration: recordingDuration,
              onCancel: onCancelVoiceRecording,
              onStop: onStopVoiceRecording,
            )
          else if (attachment != null)
            _AttachmentPreview(
              attachment: attachment!,
              onPlayVoice: onPlayVoicePreview,
              onRemove: onRemoveAttachment,
            ),
          if (recordingVoice || attachment != null) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  key: const Key('conversation-input-pill'),
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isDark ? colors.border : const Color(0xFFF3F4F6),
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x0D000000), blurRadius: 1),
                    ],
                  ),
                  child: Row(
                    children: [
                      _ComposerIconControl(
                        key: const Key('conversation-emoji-button'),
                        tooltip: 'Open keyboard emoji picker',
                        onTap: !sending && !recordingVoice
                            ? () {
                                focusNode.requestFocus();
                                SystemChannels.textInput.invokeMethod<void>(
                                  'TextInput.show',
                                );
                              }
                            : null,
                        asset: 'assets/figma/conversation_details/composer_emoji.svg',
                        colorFilter: iconFilter,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            key: const Key('conversation-reply-field'),
                            controller: controller,
                            focusNode: focusNode,
                            enabled: !sending && !recordingVoice,
                            readOnly: false,
                            enableInteractiveSelection: true,
                            onSubmitted: (_) => onSend(),
                            textInputAction: TextInputAction.send,
                            textAlignVertical: TextAlignVertical.center,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 16,
                              color: colors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Type a reply...',
                              hintStyle: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 16,
                                color: isDark
                                    ? colors.textSecondary
                                    : const Color(0xFF6B7280),
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                      _ComposerIconControl(
                        key: const Key('conversation-microphone-button'),
                        tooltip: 'Record a voice message',
                        onTap: sending || selectingAttachment
                            ? null
                            : onStartVoiceRecording,
                        asset: 'assets/figma/conversation_details/composer_microphone.svg',
                        colorFilter: iconFilter,
                      ),
                      const SizedBox(width: 4),
                      if (selectingAttachment)
                        SizedBox.square(
                          key: const Key('conversation-attachment-button'),
                          dimension: 24,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.textPrimary,
                            ),
                          ),
                        )
                      else
                        _ComposerIconControl(
                          key: const Key('conversation-attachment-button'),
                          tooltip: 'Add attachment',
                          onTap: sending || recordingVoice
                              ? null
                              : onAddAttachment,
                          asset: 'assets/figma/conversation_details/composer_attachment.svg',
                          colorFilter: iconFilter,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final hasPayload =
                      attachment != null || value.text.trim().isNotEmpty;
                  final enabled = !recordingVoice && !sending && hasPayload;
                  final visuallyActive = hasPayload || sending;
                  return SizedBox.square(
                    dimension: 48,
                    child: Material(
                      key: const Key('conversation-send-surface'),
                      color: visuallyActive
                          ? const Color(0xFFFEDC43)
                          : colors.controlInactive,
                      shape: const CircleBorder(),
                      child: InkWell(
                        key: const Key('conversation-send-button'),
                        customBorder: const CircleBorder(),
                        overlayColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.pressed)) {
                            return const Color(0x1F000000);
                          }
                          return null;
                        }),
                        onTap: enabled ? onSend : null,
                        child: Center(
                          child: sending
                              ? SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.textPrimary,
                                  ),
                                )
                              : SvgPicture.asset(
                                  'assets/figma/conversation_details/composer_send.svg',
                                  width: 20,
                                  height: 20,
                                  colorFilter: ColorFilter.mode(
                                    visuallyActive
                                        ? const Color(0xFF171717)
                                        : colors.textSecondary,
                                    BlendMode.srcIn,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          if (!canReply && !recordingVoice) ...[
            const SizedBox(height: 6),
            InkWell(
              key: const Key('conversation-reply-unavailable-help'),
              onTap: onShowReplyUnavailable,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$replyUnavailableReason Your draft is safe; Send will check again.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 11,
                              height: 15 / 11,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            replyDiagnostic,
                            key: const Key('conversation-reply-diagnostic'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 9,
                              height: 12 / 9,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComposerIconControl extends StatelessWidget {
  const _ComposerIconControl({
    super.key,
    required this.tooltip,
    required this.onTap,
    required this.asset,
    required this.colorFilter,
  });

  final String tooltip;
  final VoidCallback? onTap;
  final String asset;
  final ColorFilter? colorFilter;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 24,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: onTap,
            radius: 20,
            containedInkWell: false,
            child: Opacity(
              opacity: onTap == null ? 0.45 : 1,
              child: SvgPicture.asset(asset, colorFilter: colorFilter),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceRecordingBar extends StatelessWidget {
  const _VoiceRecordingBar({
    required this.duration,
    required this.onCancel,
    required this.onStop,
  });

  final Duration duration;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      key: const Key('conversation-recording-bar'),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: colors.destructive,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Recording ${_formatDuration(duration)}',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          TextButton(
            key: const Key('conversation-recording-cancel'),
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('conversation-recording-stop'),
            onPressed: onStop,
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: const Color(0xFF171717),
            ),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.onPlayVoice,
    required this.onRemove,
  });

  final _ComposerAttachment attachment;
  final VoidCallback onPlayVoice;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.floatingColors;
    return Container(
      key: const Key('conversation-attachment-preview'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox.square(
              dimension: 46,
              child: attachment.previewBytes.isNotEmpty
                  ? Image.memory(
                      attachment.previewBytes,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    )
                  : ColoredBox(
                      color: colors.accentSurface,
                      child: Icon(
                        attachment.kind == 'voice'
                            ? Icons.graphic_eq_rounded
                            : Icons.description_outlined,
                        color: colors.textPrimary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  attachment.kind == 'voice'
                      ? 'Voice recording · ${_formatDuration(attachment.duration)}'
                      : 'Opens in the source app to finish sharing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (attachment.kind == 'voice')
            IconButton(
              key: const Key('conversation-voice-preview-play'),
              tooltip: 'Play recording',
              onPressed: onPlayVoice,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          IconButton(
            key: const Key('conversation-attachment-remove'),
            tooltip: 'Remove attachment',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _ComposerAttachment {
  const _ComposerAttachment({
    required this.uri,
    required this.name,
    required this.mimeType,
    required this.kind,
    required this.previewBytes,
    required this.duration,
  });

  factory _ComposerAttachment.fromMap(Map<String, dynamic> map) {
    final preview = map['previewBytes'];
    return _ComposerAttachment(
      uri: map['uri']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Attachment',
      mimeType: map['mimeType']?.toString() ?? 'application/octet-stream',
      kind: map['kind']?.toString() ?? 'file',
      previewBytes: preview is Uint8List
          ? preview
          : preview is List
          ? Uint8List.fromList(preview.cast<int>())
          : Uint8List(0),
      duration: Duration(
        milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  final String uri;
  final String name;
  final String mimeType;
  final String kind;
  final Uint8List previewBytes;
  final Duration duration;
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _ConversationStatus extends StatelessWidget {
  const _ConversationStatus({
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

bool _isSameLocalDay(int firstMilliseconds, int secondMilliseconds) {
  final first = DateTime.fromMillisecondsSinceEpoch(firstMilliseconds)
      .toLocal();
  final second = DateTime.fromMillisecondsSinceEpoch(secondMilliseconds)
      .toLocal();
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String _formatDateLabel(int milliseconds) {
  if (milliseconds <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final dayDifference = today.difference(target).inDays;
  if (dayDifference == 0) return 'Today';
  if (dayDifference == 1) return 'Yesterday';
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final suffix = date.year == now.year ? '' : ', ${date.year}';
  return '${months[date.month - 1]} ${date.day}$suffix';
}

String _formatMessageTime(BuildContext context, int milliseconds) {
  if (milliseconds <= 0) return '';
  final time = TimeOfDay.fromDateTime(
    DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal(),
  );
  return MaterialLocalizations.of(context).formatTimeOfDay(time);
}
