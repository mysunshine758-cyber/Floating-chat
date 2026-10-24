import 'dart:async';

import 'package:flutter/services.dart';

class FloatingChatNativeEvents {
  FloatingChatNativeEvents._();

  static const MethodChannel channel = MethodChannel(
    'com.example.floating_chat/bubble',
  );
  static final StreamController<Map<String, dynamic>> _notifications =
      StreamController<Map<String, dynamic>>.broadcast();
  static bool _initialized = false;

  static Stream<Map<String, dynamic>> get notifications {
    _ensureInitialized();
    return _notifications.stream;
  }

  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'onNotificationReceived') return null;
      final arguments = call.arguments;
      if (arguments is Map) {
        _notifications.add(Map<String, dynamic>.from(arguments));
      }
      return null;
    });
  }
}
