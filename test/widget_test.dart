import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floating_chat/chats_screen.dart';
import 'package:floating_chat/app_theme.dart';
import 'package:floating_chat/display_over_other_apps_screen.dart';
import 'package:floating_chat/getting_started_screen.dart';
import 'package:floating_chat/home_screen.dart' as home;
import 'package:floating_chat/main.dart';
import 'package:floating_chat/notification_access_screen.dart';
import 'package:floating_chat/settings_screen.dart';
import 'package:floating_chat/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.floating_chat/bubble');
  final testIcon = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  var notificationGranted = false;
  var overlayGranted = false;
  var notificationSettingsRequested = false;
  var overlaySettingsRequested = false;
  var bubbleRunning = false;
  var homeMode = 'all';
  var selectedPackages = <String>[];
  var conversationSummaries = <Map<String, dynamic>>[];
  var conversationMessages = <Map<String, dynamic>>[];
  var conversationSummaryLoads = 0;
  var conversationCanReply = false;
  var conversationCanOpen = false;
  var sentReplies = <String>[];
  var failConversationReply = false;
  Map<String, dynamic>? attachmentPickerResult;
  var sharedAttachments = <Map<String, dynamic>>[];
  var discardedAttachmentUris = <String>[];
  var voiceRecordingStarted = false;
  var showUnreadCount = true;
  var maxVisibleBubbles = 3;
  var bubbleSize = 'medium';
  var snapToEdges = true;
  var vibrationFeedback = true;
  var exportedHistory = false;
  var importedHistory = false;
  var clearedHistory = false;
  var failClearHistory = false;
  var themePreference = 'light';

  setUp(() {
    notificationGranted = false;
    overlayGranted = false;
    notificationSettingsRequested = false;
    overlaySettingsRequested = false;
    bubbleRunning = false;
    homeMode = 'all';
    selectedPackages = <String>[];
    conversationSummaries = <Map<String, dynamic>>[];
    conversationMessages = <Map<String, dynamic>>[];
    conversationSummaryLoads = 0;
    conversationCanReply = false;
    conversationCanOpen = false;
    sentReplies = <String>[];
    failConversationReply = false;
    attachmentPickerResult = null;
    sharedAttachments = <Map<String, dynamic>>[];
    discardedAttachmentUris = <String>[];
    voiceRecordingStarted = false;
    showUnreadCount = true;
    maxVisibleBubbles = 3;
    bubbleSize = 'medium';
    snapToEdges = true;
    vibrationFeedback = true;
    exportedHistory = false;
    importedHistory = false;
    clearedHistory = false;
    failClearHistory = false;
    themePreference = 'light';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'checkNotificationPermission':
              return notificationGranted;
            case 'requestNotificationPermission':
              notificationSettingsRequested = true;
              return null;
            case 'checkOverlayPermission':
              return overlayGranted;
            case 'requestOverlayPermission':
              overlaySettingsRequested = true;
              return null;
            case 'isBubbleRunning':
              return bubbleRunning;
            case 'getRecentNotifications':
              return <dynamic>[];
            case 'getConversationSummaries':
              conversationSummaryLoads++;
              return conversationSummaries;
            case 'getConversationDetails':
              return <String, dynamic>{
                'messages': conversationMessages,
                'canReply': conversationCanReply,
                'canOpenConversation': conversationCanOpen,
                'stateCode': conversationCanReply
                    ? 'READY_ACTIVE_NOTIFICATION'
                    : 'NO_CAPTURE_EVENT_FOR_SOURCE_APP',
                'notificationAccessGranted': true,
                'listenerConnected': true,
                'capturedSessionCount': conversationCanReply ? 1 : 0,
                'activeNotificationCount': conversationCanReply ? 1 : 0,
                'sourcePackageSessionCount': conversationCanReply ? 1 : 0,
                'matchedActiveSessions': conversationCanReply ? 1 : 0,
                'retainedReplySessionCount': 0,
                'replyActionDiscovered': conversationCanReply,
                'remoteInputDiscovered': conversationCanReply,
                'pendingIntentState': conversationCanReply
                    ? 'ACTIVE_UNVERIFIED'
                    : 'NOT_AVAILABLE',
                'lastSendAttempt': 'NOT_ATTEMPTED',
                'captureDiagnosticSchema': 'capture-v3',
                'captureStageCode': conversationCanReply
                    ? 'SESSION_STORED'
                    : 'NOT_OBSERVED',
                'captureReasonCode': conversationCanReply
                    ? 'FREE_FORM_REPLY_SESSION_STORED'
                    : 'NO_SOURCE_EVENT',
                'capturePackageName': 'com.example.chat',
                'captureActionCount': conversationCanReply ? 1 : -1,
                'captureRemoteInputActionCount': conversationCanReply ? 1 : -1,
                'captureFreeFormActionCount': conversationCanReply ? 1 : -1,
                'captureSessionStored': conversationCanReply,
                'replyUnavailableReason': conversationCanReply
                    ? ''
                    : 'The source notification is no longer active.',
              };
            case 'getConversationReplyCapability':
              return <String, dynamic>{
                'canReply': conversationCanReply,
                'canOpenConversation': conversationCanOpen,
                'stateCode': conversationCanReply
                    ? 'READY_ACTIVE_NOTIFICATION'
                    : 'NO_CAPTURE_EVENT_FOR_SOURCE_APP',
                'notificationAccessGranted': true,
                'listenerConnected': true,
                'capturedSessionCount': conversationCanReply ? 1 : 0,
                'activeNotificationCount': conversationCanReply ? 1 : 0,
                'sourcePackageSessionCount': conversationCanReply ? 1 : 0,
                'matchedActiveSessions': conversationCanReply ? 1 : 0,
                'retainedReplySessionCount': 0,
                'replyActionDiscovered': conversationCanReply,
                'remoteInputDiscovered': conversationCanReply,
                'pendingIntentState': conversationCanReply
                    ? 'ACTIVE_UNVERIFIED'
                    : 'NOT_AVAILABLE',
                'lastSendAttempt': 'NOT_ATTEMPTED',
                'captureDiagnosticSchema': 'capture-v3',
                'captureStageCode': conversationCanReply
                    ? 'SESSION_STORED'
                    : 'NOT_OBSERVED',
                'captureReasonCode': conversationCanReply
                    ? 'FREE_FORM_REPLY_SESSION_STORED'
                    : 'NO_SOURCE_EVENT',
                'capturePackageName': 'com.example.chat',
                'captureActionCount': conversationCanReply ? 1 : -1,
                'captureRemoteInputActionCount': conversationCanReply ? 1 : -1,
                'captureFreeFormActionCount': conversationCanReply ? 1 : -1,
                'captureSessionStored': conversationCanReply,
                'replyUnavailableReason': conversationCanReply
                    ? ''
                    : 'The source notification is no longer active.',
              };
            case 'sendConversationReply':
              if (failConversationReply) {
                throw PlatformException(
                  code: 'REPLY_FAILED',
                  message: 'The source app did not accept the reply.',
                );
              }
              final arguments = Map<String, dynamic>.from(
                call.arguments as Map,
              );
              final text = arguments['text'] as String;
              sentReplies.add(text);
              conversationMessages = <Map<String, dynamic>>[
                ...conversationMessages,
                <String, dynamic>{
                  'text': text,
                  'sender': null,
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                  'direction': 'outgoing',
                  'replyStatus': 'submitted; delivery unconfirmed',
                },
              ];
              return <String, dynamic>{'accepted': true};
            case 'openConversation':
              return true;
            case 'pickConversationAttachment':
              return attachmentPickerResult;
            case 'shareConversationAttachment':
              sharedAttachments.add(
                Map<String, dynamic>.from(call.arguments as Map),
              );
              return true;
            case 'discardConversationAttachment':
              discardedAttachmentUris.add(
                (call.arguments as Map)['uri'] as String,
              );
              return true;
            case 'startVoiceRecording':
              voiceRecordingStarted = true;
              return <String, dynamic>{'started': true};
            case 'stopVoiceRecording':
              voiceRecordingStarted = false;
              return <String, dynamic>{
                'uri': 'content://floating-chat/voice.m4a',
                'name': 'Voice message.m4a',
                'mimeType': 'audio/mp4',
                'kind': 'voice',
                'durationMs': 1200,
                'previewBytes': <int>[],
              };
            case 'cancelVoiceRecording':
              voiceRecordingStarted = false;
              return true;
            case 'playVoicePreview':
              return true;
            case 'getHomeConfiguration':
              return <String, dynamic>{
                'sourceMode': homeMode,
                'selectedPackages': selectedPackages,
                'serviceEnabled': bubbleRunning,
              };
            case 'getSettingsConfiguration':
              return <String, dynamic>{
                'theme': themePreference,
                'showUnreadCount': showUnreadCount,
                'maxVisibleBubbles': maxVisibleBubbles,
                'bubbleSize': bubbleSize,
                'snapToEdges': snapToEdges,
                'vibrationFeedback': vibrationFeedback,
              };
            case 'setSettingsConfiguration':
              final arguments = Map<String, dynamic>.from(
                call.arguments as Map,
              );
              switch (arguments['key']) {
                case 'theme':
                  themePreference = arguments['value'] as String;
                case 'showUnreadCount':
                  showUnreadCount = arguments['value'] as bool;
                case 'maxVisibleBubbles':
                  maxVisibleBubbles = arguments['value'] as int;
                case 'bubbleSize':
                  bubbleSize = arguments['value'] as String;
                case 'snapToEdges':
                  snapToEdges = arguments['value'] as bool;
                case 'vibrationFeedback':
                  vibrationFeedback = arguments['value'] as bool;
              }
              return <String, dynamic>{};
            case 'exportHistory':
              exportedHistory = true;
              return <String, dynamic>{'exported': true};
            case 'importHistory':
              importedHistory = true;
              return <String, dynamic>{'conversations': 1, 'messages': 2};
            case 'clearHistory':
              if (failClearHistory) {
                throw PlatformException(
                  code: 'CLEAR_FAILED',
                  message: 'Could not clear local history.',
                );
              }
              clearedHistory = true;
              return true;
            case 'setNotificationSourceMode':
              homeMode = (call.arguments as Map)['mode'] as String;
              return true;
            case 'setSelectedPackages':
              selectedPackages = List<String>.from(
                (call.arguments as Map)['packageNames'] as List,
              );
              if (selectedPackages.isEmpty && homeMode == 'custom') {
                homeMode = 'all';
              }
              return true;
            case 'getInstalledApps':
              return <Map<String, dynamic>>[
                <String, dynamic>{
                  'packageName': 'com.example.chat',
                  'label': 'Chat App',
                  'icon': testIcon,
                },
                <String, dynamic>{
                  'packageName': 'com.example.mail',
                  'label': 'Mail App',
                  'icon': Uint8List(0),
                },
                <String, dynamic>{
                  'packageName': 'com.example.social',
                  'label': 'Social App',
                  'icon': Uint8List(0),
                },
                <String, dynamic>{
                  'packageName': 'com.example.work',
                  'label': 'Work App',
                  'icon': Uint8List(0),
                },
                <String, dynamic>{
                  'packageName': 'com.example.team',
                  'label': 'Team App',
                  'icon': Uint8List(0),
                },
              ];
            case 'startBubble':
              bubbleRunning = true;
              return true;
            case 'stopBubble':
              bubbleRunning = false;
              return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('Floating Chat App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FloatingChatApp());

    // Verify that the app starts on the splash screen.
    expect(find.byType(SplashScreen), findsOneWidget);
    final splashSystemUi = tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(
            of: find.byType(SplashScreen),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          ),
        )
        .value;
    final splashSafeArea = tester.widget<SafeArea>(
      find.descendant(
        of: find.byType(SplashScreen),
        matching: find.byType(SafeArea),
      ),
    );
    expect(splashSystemUi.systemNavigationBarColor, const Color(0xFFFEFCF3));
    expect(splashSystemUi.systemNavigationBarIconBrightness, Brightness.dark);
    expect(splashSafeArea.bottom, isFalse);

    // Load the composition, then verify the splash cannot navigate before the
    // 500 ms lead-in and two-second composition playback have elapsed.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 499));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));

    // Advance ordinary display frames so controller completion and the
    // subsequent 100 ms hold are delivered in the same way as a running app.
    for (
      var frame = 0;
      frame < 220 && find.byType(SplashScreen).evaluate().isNotEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    // Verify that the splash advances to the onboarding screen.
    expect(find.byType(GettingStartedScreen), findsOneWidget);
    expect(find.text('Floating Chat'), findsOneWidget);
    expect(find.text('Quick replies'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    final onboardingSystemUi = tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(
            of: find.byType(GettingStartedScreen),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          ),
        )
        .value;
    final onboardingSafeArea = tester.widget<SafeArea>(
      find.descendant(
        of: find.byType(GettingStartedScreen),
        matching: find.byType(SafeArea),
      ),
    );
    expect(onboardingSystemUi, splashSystemUi);
    expect(onboardingSafeArea.bottom, splashSafeArea.bottom);

    // Continue to the notification-access screen.
    notificationGranted = true;
    await tester.ensureVisible(find.text('Get Started'));
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationAccessScreen), findsOneWidget);
    expect(find.text('Allow notification access'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);

    await tester.ensureVisible(find.text('Open Settings'));
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    expect(notificationSettingsRequested, isTrue);

    // Returning with notification access granted advances only to the overlay
    // permission screen.
    notificationGranted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(DisplayOverOtherAppsScreen), findsOneWidget);
    expect(find.text('Allow display over apps'), findsOneWidget);
    expect(find.text('Floating bubble on any app'), findsOneWidget);

    // The explicit back action returns to notification access and leaves that
    // screen able to continue again.
    await tester.tap(find.bySemanticsLabel('Go back'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationAccessScreen), findsOneWidget);

    await tester.ensureVisible(find.text('Open Settings'));
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(DisplayOverOtherAppsScreen), findsOneWidget);

    // Denying overlay access keeps the permission screen visible.
    await tester.ensureVisible(find.text('Open Settings'));
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    expect(overlaySettingsRequested, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(DisplayOverOtherAppsScreen), findsOneWidget);

    // Granting overlay access on a later attempt continues to the existing
    // home screen and preserves its status checks.
    overlayGranted = true;
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(home.FloatingChatHomeScreen), findsOneWidget);
    expect(find.text('Floating chat'), findsOneWidget);
    expect(find.text('Listen to all apps'), findsOneWidget);
    expect(find.text('Custom apps'), findsOneWidget);
    expect(find.text('Backup & Export'), findsOneWidget);
  });

  testWidgets('Home modes are exclusive and custom app selection persists', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: home.FloatingChatHomeScreen()),
    );
    await tester.pumpAndSettle();

    expect(homeMode, 'all');
    expect(selectedPackages, isEmpty);
    expect(find.byKey(const Key('add-custom-app')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('custom-apps-grid'))).height,
      62,
    );
    final emptyCardRect = tester.getRect(
      find.byKey(const Key('custom-apps-card')),
    );
    final emptyHeaderRect = tester.getRect(
      find.byKey(const Key('custom-apps-header')),
    );
    final emptyGridRect = tester.getRect(
      find.byKey(const Key('custom-apps-grid')),
    );
    final emptyAddRect = tester.getRect(
      find.byKey(const Key('add-custom-app')),
    );
    final headerIconRect = tester.getRect(
      find.byKey(const Key('custom-apps-header-icon')),
    );
    expect(emptyGridRect.top - emptyHeaderRect.bottom, 32);
    expect(emptyCardRect.bottom - emptyGridRect.bottom, 16);
    expect(emptyAddRect.left, closeTo(emptyGridRect.left, 0.01));
    expect(emptyAddRect.left, closeTo(headerIconRect.left, 0.01));

    await tester.ensureVisible(find.byKey(const Key('custom-apps-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-apps-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Choose apps'), findsOneWidget);

    await tester.tap(find.text('Chat App'));
    await tester.pump();
    await tester.tap(find.text('Add selected apps'));
    await tester.pumpAndSettle();

    expect(homeMode, 'custom');
    expect(selectedPackages, <String>['com.example.chat']);
    expect(
      find.byKey(const Key('selected-app-com.example.chat')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('listen-to-all-apps-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('listen-to-all-apps-toggle')));
    await tester.pumpAndSettle();
    expect(homeMode, 'all');
    expect(selectedPackages, <String>['com.example.chat']);
  });

  testWidgets('Custom Apps uses four evenly distributed grid slots per row', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    homeMode = 'custom';
    selectedPackages = <String>[
      'com.example.chat',
      'com.example.mail',
      'com.example.social',
      'com.example.work',
      'com.example.team',
    ];
    await tester.binding.setSurfaceSize(const Size(390, 970));
    await tester.pumpWidget(
      const MaterialApp(home: home.FloatingChatHomeScreen()),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('custom-apps-grid')));
    await tester.pumpAndSettle();

    final gridRect = tester.getRect(find.byKey(const Key('custom-apps-grid')));
    final addRect = tester.getRect(find.byKey(const Key('add-custom-app')));
    final firstRect = tester.getRect(
      find.byKey(const Key('selected-app-com.example.chat')),
    );
    final secondRect = tester.getRect(
      find.byKey(const Key('selected-app-com.example.mail')),
    );
    final thirdRect = tester.getRect(
      find.byKey(const Key('selected-app-com.example.social')),
    );
    final fourthRect = tester.getRect(
      find.byKey(const Key('selected-app-com.example.work')),
    );

    expect(addRect.size, const Size.square(54));
    expect(gridRect.height, 128);
    expect(firstRect.size, const Size.square(54));
    expect(
      tester.getSize(find.byKey(const Key('remove-app-com.example.chat'))),
      const Size.square(24),
    );
    expect(firstRect.top, closeTo(addRect.top, 0.01));
    expect(secondRect.top, closeTo(addRect.top, 0.01));
    expect(thirdRect.top, closeTo(addRect.top, 0.01));
    expect(fourthRect.top, greaterThan(addRect.top));

    final columnGap = (gridRect.width - (54 * 4)) / 3;
    expect(firstRect.left - addRect.right, closeTo(columnGap, 0.01));
    expect(secondRect.left - firstRect.right, closeTo(columnGap, 0.01));
    expect(thirdRect.left - secondRect.right, closeTo(columnGap, 0.01));
    expect(addRect.left, closeTo(gridRect.left, 0.01));
    expect(thirdRect.right, closeTo(gridRect.right, 0.01));
    expect(fourthRect.left, closeTo(gridRect.left, 0.01));
    expect(fourthRect.top - addRect.bottom, closeTo(12, 0.01));
    final firstAppImage = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('selected-app-com.example.chat')),
        matching: find.byType(Image),
      ),
    );
    expect(firstAppImage.fit, BoxFit.contain);
    expect(find.text('Chat App'), findsNothing);
    final customCard = tester.widget<Container>(
      find.byKey(const Key('custom-apps-card')),
    );
    final customDecoration = customCard.decoration! as BoxDecoration;
    expect(customDecoration.color, Colors.white);
    expect(customDecoration.border, isNull);
    expect(customDecoration.borderRadius, BorderRadius.circular(16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home body scrolls while bottom navigation stays fixed', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 970));
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(bottom: 24),
            viewPadding: EdgeInsets.only(bottom: 24),
          ),
          child: home.FloatingChatHomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('home-scroll-view')), findsOneWidget);
    expect(find.byKey(const Key('home-bottom-navigation')), findsOneWidget);
    final navigationRect = tester.getRect(
      find.byKey(const Key('home-bottom-navigation')),
    );
    final navigationTop = navigationRect.top;
    expect(navigationRect.width, 350);
    expect(navigationRect.height, 70);
    expect(970 - navigationRect.bottom, 24 + 24);
    final homeDestinationRect = tester.getRect(
      find.byKey(const Key('home-nav-home')),
    );
    final chatsDestinationRect = tester.getRect(
      find.byKey(const Key('home-nav-chats')),
    );
    final settingsDestinationRect = tester.getRect(
      find.byKey(const Key('home-nav-settings')),
    );
    expect(
      homeDestinationRect.width,
      closeTo(chatsDestinationRect.width, 0.01),
    );
    expect(
      chatsDestinationRect.width,
      closeTo(settingsDestinationRect.width, 0.01),
    );
    expect(homeDestinationRect.left, closeTo(navigationRect.left + 8, 0.01));
    expect(
      settingsDestinationRect.right,
      closeTo(navigationRect.right - 8, 0.01),
    );
    final navigationSafeArea = tester.widget<SafeArea>(
      find.ancestor(
        of: find.byKey(const Key('home-bottom-navigation')),
        matching: find.byType(SafeArea),
      ),
    );
    expect(navigationSafeArea.top, isFalse);
    expect(navigationSafeArea.maintainBottomViewPadding, isTrue);
    final heroRect = tester.getRect(find.byKey(const Key('home-hero')));
    expect(heroRect.width, 390);
    expect(heroRect.height, 326);

    await tester.drag(
      find.byKey(const Key('home-scroll-view')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('home-bottom-navigation'))).top,
      navigationTop,
    );
    await tester.ensureVisible(find.byKey(const Key('backup-card')));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('backup-card'))).bottom,
      lessThanOrEqualTo(navigationTop),
    );

    await tester.binding.setSurfaceSize(const Size(432, 970));
    await tester.pumpAndSettle();
    final wideNavigationRect = tester.getRect(
      find.byKey(const Key('home-bottom-navigation')),
    );
    expect(wideNavigationRect.width, 392);
    expect(
      tester.getRect(find.byKey(const Key('home-nav-home'))).width,
      closeTo(
        tester.getRect(find.byKey(const Key('home-nav-settings'))).width,
        0.01,
      ),
    );

    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const Key('home-bottom-navigation'))).width,
      320,
    );
  });

  testWidgets(
    'Chats renders persisted summaries, searches, refreshes, and navigates',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final yesterday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1)).add(const Duration(hours: 12));
      conversationSummaries = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'com.example.archive|archive',
          'appName': 'Archive App',
          'packageName': 'com.example.archive',
          'title': 'Archive',
          'latestText': 'Archived budget review',
          'latestTimestamp': yesterday.millisecondsSinceEpoch,
          'avatar': Uint8List(0),
          'appIcon': testIcon,
          'unreadCount': 0,
        },
        <String, dynamic>{
          'id': 'com.example.chat|jordan',
          'appName': 'Chat App',
          'packageName': 'com.example.chat',
          'title': 'Jordan',
          'latestText': 'Photo',
          'latestTimestamp': now
              .subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'avatar': testIcon,
          'appIcon': testIcon,
          'unreadCount': 2,
        },
      ];

      await tester.binding.setSurfaceSize(const Size(390, 888));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 24),
              viewPadding: EdgeInsets.only(bottom: 24),
            ),
            child: ChatsScreen(
              homeBuilder: (_) =>
                  const Scaffold(body: Text('Home destination')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All conversations'), findsOneWidget);
      expect(find.text('Jordan'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('conversation-com.example.chat|jordan')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(
                  const Key('conversation-com.example.archive|archive'),
                ),
              )
              .dy,
        ),
      );
      expect(
        tester
            .getSize(
              find.byKey(const Key('conversation-com.example.chat|jordan')),
            )
            .height,
        88,
      );
      expect(
        tester.getSize(
          find.byKey(const Key('app-badge-com.example.chat|jordan')),
        ),
        const Size.square(24),
      );
      expect(
        tester.getSize(find.byKey(const Key('unread-com.example.chat|jordan'))),
        const Size.square(20),
      );
      expect(find.text('Yesterday'), findsOneWidget);

      final navigationRect = tester.getRect(
        find.byKey(const Key('chats-bottom-navigation')),
      );
      expect(navigationRect.width, 350);
      expect(888 - navigationRect.bottom, 24 + 24);

      await tester.tap(find.byKey(const Key('chats-search-button')));
      await tester.pumpAndSettle();
      final searchContainer = find.byKey(const Key('chats-search-container'));
      final searchBack = find.byKey(const Key('chats-search-back'));
      final searchBackIconFinder = find.descendant(
        of: searchBack,
        matching: find.byIcon(Icons.arrow_back_rounded),
      );
      final searchBackIcon = tester.widget<Icon>(searchBackIconFinder);
      final searchContainerWidget = tester.widget<Container>(searchContainer);
      final searchDecoration =
          searchContainerWidget.decoration! as BoxDecoration;
      final searchBorder = searchDecoration.border! as Border;
      final searchContainerRect = tester.getRect(searchContainer);
      final searchBackIconRect = tester.getRect(searchBackIconFinder);
      expect(searchContainerRect.width, 350);
      expect(searchContainerRect.height, 56);
      expect(searchDecoration.borderRadius, BorderRadius.circular(16));
      expect(searchBorder.top.width, 1);
      expect(searchBorder.top.color, const Color(0x33000000));
      expect(tester.getSize(searchBack), const Size.square(48));
      expect(searchBackIcon.size, 28);
      expect(searchBackIcon.weight, 700);
      expect(
        searchBackIconRect.left -
            searchContainerRect.left -
            searchBorder.left.width,
        16,
      );
      expect(
        searchBackIconRect.center.dy,
        closeTo(searchContainerRect.center.dy, 0.01),
      );
      await tester.enterText(
        find.byKey(const Key('chats-search-field')),
        'budget',
      );
      await tester.pump();
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Jordan'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('chats-search-field')),
        'not stored',
      );
      await tester.pump();
      expect(find.text('No conversations found'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chats-search-clear')));
      await tester.pump();
      expect(find.text('Jordan'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chats-search-back')));
      await tester.pumpAndSettle();
      expect(find.text('All conversations'), findsOneWidget);

      final loadsBeforeRefresh = conversationSummaryLoads;
      await tester.tap(find.byKey(const Key('chats-overflow-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh conversations'));
      await tester.pumpAndSettle();
      expect(conversationSummaryLoads, loadsBeforeRefresh + 1);

      await tester.tap(find.byKey(const Key('chats-nav-home')));
      await tester.pumpAndSettle();
      expect(find.text('Home destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Conversation details renders stored directions and sends a real reply',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      conversationSummaries = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'com.example.chat|jordan',
          'appName': 'Chat App',
          'packageName': 'com.example.chat',
          'title': 'Jordan',
          'latestText': 'See you soon',
          'latestTimestamp': now.millisecondsSinceEpoch,
          'avatar': testIcon,
          'appIcon': testIcon,
          'unreadCount': 1,
        },
      ];
      conversationMessages = <Map<String, dynamic>>[
        <String, dynamic>{
          'text': 'Are we still meeting?',
          'sender': 'Jordan',
          'timestamp': now
              .subtract(const Duration(minutes: 2))
              .millisecondsSinceEpoch,
          'direction': 'incoming',
          'replyStatus': null,
        },
        <String, dynamic>{
          'text': 'Yes, see you soon',
          'sender': null,
          'timestamp': now
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
          'direction': 'outgoing',
          'replyStatus': 'submitted; delivery unconfirmed',
        },
      ];
      conversationCanReply = true;
      conversationCanOpen = true;

      await tester.binding.setSurfaceSize(const Size(390, 720));
      await tester.pumpWidget(
        MaterialApp(
          theme: floatingChatTheme(Brightness.light),
          home: ChatsScreen(
            homeBuilder: (_) => const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('conversation-com.example.chat|jordan')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jordan'), findsOneWidget);
      expect(find.text('Chat App'), findsOneWidget);
      expect(find.text('Are we still meeting?'), findsOneWidget);
      expect(find.text('Yes, see you soon'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('incoming-message-bubble'))).dx,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('outgoing-message-bubble')))
              .dx,
        ),
      );
      expect(
        find.byKey(const Key('conversation-reply-composer')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const Key('conversation-input-pill'))).height,
        54,
      );
      expect(
        tester
            .widget<Material>(
              find.byKey(const Key('conversation-send-surface')),
            )
            .color,
        isNot(const Color(0xFFFEDC43)),
      );
      await tester.tap(find.byKey(const Key('conversation-send-button')));
      await tester.pump();
      expect(sentReplies, isEmpty);
      final editableReply = tester.widget<TextField>(
        find.byKey(const Key('conversation-reply-field')),
      );
      expect(editableReply.readOnly, isFalse);
      await tester.tap(find.byKey(const Key('conversation-reply-field')));
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.enterText(
        find.byKey(const Key('conversation-reply-field')),
        'On my way',
      );
      await tester.pump();
      expect(
        tester
            .widget<Material>(
              find.byKey(const Key('conversation-send-surface')),
            )
            .color,
        const Color(0xFFFEDC43),
      );
      await tester.tap(find.byKey(const Key('conversation-send-button')));
      await tester.pumpAndSettle();

      expect(sentReplies, <String>['On my way']);
      expect(find.text('On my way'), findsOneWidget);
      final replyField = tester.widget<TextField>(
        find.byKey(const Key('conversation-reply-field')),
      );
      expect(replyField.controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Conversation reply failure preserves the typed draft', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().millisecondsSinceEpoch;
    conversationSummaries = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'com.example.chat|jordan',
        'appName': 'Chat App',
        'packageName': 'com.example.chat',
        'title': 'Jordan',
        'latestText': 'Hello',
        'latestTimestamp': now,
        'avatar': testIcon,
        'appIcon': testIcon,
        'unreadCount': 0,
      },
    ];
    conversationMessages = <Map<String, dynamic>>[
      <String, dynamic>{
        'text': 'Hello',
        'sender': 'Jordan',
        'timestamp': now,
        'direction': 'incoming',
        'replyStatus': null,
      },
    ];
    conversationCanReply = true;
    failConversationReply = true;

    await tester.binding.setSurfaceSize(const Size(390, 720));
    await tester.pumpWidget(
      MaterialApp(
        theme: floatingChatTheme(Brightness.light),
        home: ChatsScreen(
          homeBuilder: (_) => const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('conversation-com.example.chat|jordan')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('conversation-reply-field')),
      'Keep this draft',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-send-button')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('conversation-reply-field')),
    );
    expect(field.controller!.text, 'Keep this draft');
    expect(sentReplies, isEmpty);
    expect(
      find.text('The source app did not accept the reply.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Saved conversation keeps an editable draft when quick reply is unavailable',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now().millisecondsSinceEpoch;
      conversationSummaries = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'com.example.chat|jordan',
          'appName': 'Chat App',
          'packageName': 'com.example.chat',
          'title': 'Jordan',
          'latestText': 'Hello',
          'latestTimestamp': now,
          'avatar': testIcon,
          'appIcon': testIcon,
          'unreadCount': 0,
        },
      ];
      conversationMessages = <Map<String, dynamic>>[
        <String, dynamic>{
          'text': 'Hello',
          'sender': 'Jordan',
          'timestamp': now,
          'direction': 'incoming',
          'replyStatus': null,
        },
      ];

      await tester.binding.setSurfaceSize(const Size(390, 720));
      await tester.pumpWidget(
        MaterialApp(
          theme: floatingChatTheme(Brightness.light),
          home: ChatsScreen(
            homeBuilder: (_) => const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('conversation-com.example.chat|jordan')),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const Key('conversation-reply-field')),
      );
      expect(field.readOnly, isFalse);
      await tester.enterText(
        find.byKey(const Key('conversation-reply-field')),
        'Keep this persistent draft',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('conversation-send-button')));
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'Keep this persistent draft');
      expect(
        find.textContaining(
          'The source notification is no longer active. Your draft has been kept.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Status NO_CAPTURE_EVENT_FOR_SOURCE_APP'),
        findsWidgets,
      );
      expect(sentReplies, isEmpty);

      conversationCanReply = true;
      conversationMessages = <Map<String, dynamic>>[
        ...conversationMessages,
        <String, dynamic>{
          'text': 'A new notification restored quick reply',
          'sender': 'Jordan',
          'timestamp': now + 1000,
          'direction': 'incoming',
          'replyStatus': null,
        },
      ];
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onNotificationReceived', <String, dynamic>{
                'eventType': 'posted',
                'conversationId': 'com.example.chat|jordan',
                'hasReplyAction': true,
              }),
            ),
            (_) {},
          );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(
        find.text('A new notification restored quick reply'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('conversation-reply-unavailable-help')),
        findsNothing,
      );
      expect(field.controller!.text, 'Keep this persistent draft');
      await tester.tap(find.byKey(const Key('conversation-send-button')));
      await tester.pumpAndSettle();
      expect(sentReplies, <String>['Keep this persistent draft']);
      expect(field.controller!.text, isEmpty);
    },
  );

  testWidgets('Attachment preview uses an honest source-app handoff', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().millisecondsSinceEpoch;
    conversationSummaries = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'com.example.chat|jordan',
        'appName': 'Chat App',
        'packageName': 'com.example.chat',
        'title': 'Jordan',
        'latestText': 'Hello',
        'latestTimestamp': now,
        'avatar': testIcon,
        'appIcon': testIcon,
        'unreadCount': 0,
      },
    ];
    conversationMessages = <Map<String, dynamic>>[
      <String, dynamic>{
        'text': 'Hello',
        'sender': 'Jordan',
        'timestamp': now,
        'direction': 'incoming',
        'replyStatus': null,
      },
    ];
    attachmentPickerResult = <String, dynamic>{
      'uri': 'content://floating-chat/photo.jpg',
      'name': 'photo.jpg',
      'mimeType': 'image/jpeg',
      'kind': 'image',
      'durationMs': 0,
      'previewBytes': testIcon,
    };

    await tester.binding.setSurfaceSize(const Size(390, 720));
    await tester.pumpWidget(
      MaterialApp(
        theme: floatingChatTheme(Brightness.light),
        home: ChatsScreen(
          homeBuilder: (_) => const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('conversation-com.example.chat|jordan')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('conversation-attachment-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-option-images')));
    await tester.pumpAndSettle();

    expect(find.text('photo.jpg'), findsOneWidget);
    expect(
      find.byKey(const Key('conversation-attachment-preview')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('conversation-send-button')));
    await tester.pumpAndSettle();
    expect(find.text('Finish sharing in the source app'), findsOneWidget);
    await tester.tap(find.text('Open Chat App'));
    await tester.pumpAndSettle();

    expect(sharedAttachments, hasLength(1));
    expect(sharedAttachments.single['packageName'], 'com.example.chat');
    expect(sentReplies, isEmpty);
    expect(find.text('photo.jpg'), findsOneWidget);
  });

  testWidgets('Voice recording exposes stop, preview, and removal controls', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().millisecondsSinceEpoch;
    conversationSummaries = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'com.example.chat|jordan',
        'appName': 'Chat App',
        'packageName': 'com.example.chat',
        'title': 'Jordan',
        'latestText': 'Hello',
        'latestTimestamp': now,
        'avatar': testIcon,
        'appIcon': testIcon,
        'unreadCount': 0,
      },
    ];
    conversationMessages = <Map<String, dynamic>>[];

    await tester.binding.setSurfaceSize(const Size(390, 720));
    await tester.pumpWidget(
      MaterialApp(
        theme: floatingChatTheme(Brightness.light),
        home: ChatsScreen(
          homeBuilder: (_) => const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('conversation-com.example.chat|jordan')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('conversation-microphone-button')));
    await tester.pump();
    expect(voiceRecordingStarted, isTrue);
    expect(find.byKey(const Key('conversation-recording-bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('conversation-recording-stop')));
    await tester.pumpAndSettle();

    expect(voiceRecordingStarted, isFalse);
    expect(find.text('Voice message.m4a'), findsOneWidget);
    expect(
      find.byKey(const Key('conversation-voice-preview-play')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('conversation-attachment-remove')));
    await tester.pumpAndSettle();
    expect(find.text('Voice message.m4a'), findsNothing);
    expect(
      discardedAttachmentUris,
      contains('content://floating-chat/voice.m4a'),
    );
  });

  testWidgets('Home Chats tab opens the persisted conversation screen', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 888));
    await tester.pumpWidget(
      const MaterialApp(home: home.FloatingChatHomeScreen()),
    );
    await tester.pumpAndSettle();

    final navigationFinder = find.byKey(const Key('home-bottom-navigation'));
    final highlightFinder = find.byKey(
      const Key('home-navigation-highlight-box'),
    );
    final homeDestination = find.byKey(const Key('home-nav-home'));
    final chatsDestination = find.byKey(const Key('home-nav-chats'));
    final navigationBefore = tester.getRect(navigationFinder);
    final homeCenter = tester.getRect(homeDestination).center.dx;
    final chatsCenter = tester.getRect(chatsDestination).center.dx;

    expect(
      tester.getRect(highlightFinder).center.dx,
      closeTo(homeCenter, 0.01),
    );
    await tester.tap(find.byKey(const Key('home-nav-chats')));
    await tester.pump();
    expect(tester.getRect(navigationFinder), navigationBefore);

    await tester.pump(const Duration(milliseconds: 200));
    final highlightMidpoint = tester.getRect(highlightFinder).center.dx;
    expect(highlightMidpoint, greaterThan(homeCenter));
    expect(highlightMidpoint, lessThan(chatsCenter));
    expect(tester.getRect(navigationFinder), navigationBefore);

    await tester.pumpAndSettle();
    expect(find.byType(ChatsScreen), findsOneWidget);
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(
      tester.getRect(highlightFinder).center.dx,
      closeTo(chatsCenter, 0.01),
    );
    expect(tester.getRect(navigationFinder), navigationBefore);

    await tester.tap(find.byKey(const Key('home-nav-home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-scroll-view')), findsOneWidget);
    expect(
      tester.getRect(highlightFinder).center.dx,
      closeTo(homeCenter, 0.01),
    );
  });

  testWidgets('Settings persists controls and keeps navigation fixed', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 967));
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(bottom: 24),
            viewPadding: EdgeInsets.only(bottom: 24),
          ),
          child: home.FloatingChatHomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-nav-settings')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Bubble Settings'), findsOneWidget);
    expect(find.text('Behavior'), findsOneWidget);
    final navigationFinder = find.byKey(const Key('home-bottom-navigation'));
    final navigationRect = tester.getRect(navigationFinder);
    expect(967 - navigationRect.bottom, 48);
    expect(
      tester.getRect(find.byKey(const Key('settings-appearance-card'))).width,
      350,
    );

    await tester.tap(find.byKey(const Key('show-unread-count-switch')));
    await tester.pumpAndSettle();
    expect(showUnreadCount, isFalse);

    await tester.tap(find.byKey(const Key('max-visible-bubbles-row')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Set how many floating bubbles can appear on your screen at the same time.',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('settings-sheet-drag-handle'))),
      const Size(36, 4),
    );
    expect(
      tester.getSize(find.byKey(const Key('settings-choice-indicator-3'))),
      const Size.square(28),
    );
    final selectedMaxSurface = tester.widget<AnimatedContainer>(
      find.byKey(const Key('settings-choice-surface-3')),
    );
    expect(
      (selectedMaxSurface.decoration! as BoxDecoration).color,
      const Color(0xFFFFF8D9),
    );
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    expect(maxVisibleBubbles, 5);
    expect(find.text('5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bubble-size-row')));
    await tester.pumpAndSettle();
    expect(find.text('Choose the size of floating bubbles.'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('settings-choice-indicator-medium'))),
      const Size.square(28),
    );
    await tester.tap(find.text('Large').last);
    await tester.pumpAndSettle();
    expect(bubbleSize, 'large');
    expect(find.text('Large'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('settings-scroll-view')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(navigationFinder), navigationRect);
    expect(
      tester.getRect(find.byKey(const Key('settings-data-card'))).bottom,
      lessThanOrEqualTo(navigationRect.top),
    );

    await tester.tap(find.byKey(const Key('settings-export-row')));
    await tester.pump();
    expect(exportedHistory, isTrue);
    await tester.tap(find.byKey(const Key('settings-import-row')));
    await tester.pump();
    expect(importedHistory, isTrue);
    await tester.tap(find.byKey(const Key('settings-clear-history-row')));
    await tester.pumpAndSettle();
    expect(find.text('Clear conversation history?'), findsOneWidget);
    expect(find.byKey(const Key('clear-history-dialog')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('cancel-clear-history'))).height,
      48,
    );
    expect(
      tester.getSize(find.byKey(const Key('confirm-clear-history'))).height,
      48,
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clear-history-dialog')), findsNothing);
    expect(clearedHistory, isFalse);

    await tester.tap(find.byKey(const Key('settings-clear-history-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-clear-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clear-history-dialog')), findsNothing);
    expect(clearedHistory, isFalse);

    failClearHistory = true;
    await tester.tap(find.byKey(const Key('settings-clear-history-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-clear-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clear-history-dialog')), findsOneWidget);
    expect(find.byKey(const Key('clear-history-error')), findsOneWidget);
    expect(find.text('Could not clear local history.'), findsOneWidget);
    expect(clearedHistory, isFalse);

    failClearHistory = false;
    await tester.tap(find.byKey(const Key('confirm-clear-history')));
    await tester.pumpAndSettle();
    expect(clearedHistory, isTrue);
    expect(find.byKey(const Key('clear-history-dialog')), findsNothing);

    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpAndSettle();
    expect(tester.getRect(navigationFinder).width, 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Theme sheet applies and persists Light, Dark, and System', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 888));
    final controller = FloatingChatThemeController(channel: channel);
    await controller.load();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_ThemeHarness(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-nav-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-theme-row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-choice-sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('theme-choice-indicator-light')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('theme-choice-dark')));
    await tester.pumpAndSettle();
    expect(themePreference, 'dark');
    expect(controller.preference, FloatingChatThemePreference.dark);
    expect(
      Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
      Brightness.dark,
    );
    final darkNavigation = tester.widget<Container>(
      find.byKey(const Key('home-bottom-navigation')),
    );
    expect(
      (darkNavigation.decoration! as BoxDecoration).color,
      FloatingChatColors.dark.surface,
    );

    await tester.tap(find.byKey(const Key('settings-theme-row')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('theme-choice-indicator-dark')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('theme-choice-light')));
    await tester.pumpAndSettle();
    expect(themePreference, 'light');
    expect(controller.preference, FloatingChatThemePreference.light);

    await tester.tap(find.byKey(const Key('settings-theme-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-choice-system')));
    await tester.pumpAndSettle();
    expect(themePreference, 'system');
    expect(controller.preference, FloatingChatThemePreference.system);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    final restoredController = FloatingChatThemeController(channel: channel);
    await restoredController.load();
    expect(restoredController.preference, FloatingChatThemePreference.system);
    restoredController.dispose();
  });

  testWidgets('Notification access layout adapts to phone heights', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(const Size(432, 960));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.noScaling),
          child: NotificationAccessScreen(onPermissionGranted: () async {}),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final heroRect = tester.getRect(
      find.byKey(const Key('notification-access-hero')),
    );
    final benefitsRect = tester.getRect(
      find.byKey(const Key('notification-access-benefits')),
    );
    final ctaRect = tester.getRect(
      find.byKey(const Key('notification-access-cta')),
    );
    final benefitsCard = tester.widget<Container>(
      find.byKey(const Key('notification-access-benefits')),
    );
    final benefitsDecoration = benefitsCard.decoration! as BoxDecoration;
    final goldenIconCircles = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              decoration.shape == BoxShape.circle &&
              decoration.color == const Color(0xFFFFD626);
        });

    expect(benefitsDecoration.color, const Color(0xFFFCFBF7));
    expect(benefitsDecoration.border, isA<Border>());
    expect(benefitsDecoration.boxShadow, const [
      BoxShadow(color: Color(0x05FFCE00), blurRadius: 3, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x0DFFCE00),
        blurRadius: 40,
        spreadRadius: -10,
        offset: Offset(0, 10),
      ),
    ]);
    expect(goldenIconCircles, hasLength(3));
    for (final divider in tester.widgetList<Divider>(find.byType(Divider))) {
      expect(divider.color, const Color(0xFFF3EFE9));
    }
    expect(heroRect.width, 432);
    expect(heroRect.height, closeTo(432 * 322 / 390, 0.01));
    expect(heroRect.bottom - benefitsRect.top, closeTo(16, 0.01));
    expect(960 - ctaRect.bottom, closeTo(32, 0.01));

    await tester.binding.setSurfaceSize(const Size(390, 890));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Open Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Display over other apps layout matches the Figma geometry', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(const Size(390, 890));
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.noScaling),
          child: DisplayOverOtherAppsScreen(onPermissionGranted: _noop),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final heroRect = tester.getRect(
      find.byKey(const Key('overlay-access-hero')),
    );
    final benefitsRect = tester.getRect(
      find.byKey(const Key('overlay-access-benefits')),
    );
    final ctaRect = tester.getRect(find.byKey(const Key('overlay-access-cta')));

    expect(heroRect.left, closeTo(20, 0.01));
    expect(heroRect.top, closeTo(210, 0.25));
    expect(heroRect.width, 350);
    expect(heroRect.height, closeTo(311, 0.01));
    expect(benefitsRect.top - heroRect.bottom, closeTo(0.12, 0.01));
    expect(benefitsRect.width, 358);
    expect(benefitsRect.height, closeTo(257.88, 0.25));
    expect(890 - ctaRect.bottom, closeTo(32, 0.01));

    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _ThemeHarness extends StatelessWidget {
  const _ThemeHarness({required this.controller});

  final FloatingChatThemeController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => FloatingChatThemeScope(
        controller: controller,
        child: MaterialApp(
          theme: floatingChatTheme(Brightness.light),
          darkTheme: floatingChatTheme(Brightness.dark),
          themeMode: controller.themeMode,
          home: const home.FloatingChatHomeScreen(),
        ),
      ),
    );
  }
}

void _noop() {}
