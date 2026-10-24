import 'dart:typed_data';

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.appName,
    required this.packageName,
    required this.title,
    required this.latestText,
    required this.latestTimestamp,
    required this.avatar,
    required this.appIcon,
    required this.unreadCount,
  });

  factory ConversationSummary.fromMap(Map<String, dynamic> map) {
    return ConversationSummary(
      id: map['id']?.toString() ?? '',
      appName: map['appName']?.toString() ?? '',
      packageName: map['packageName']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      latestText: map['latestText']?.toString() ?? '',
      latestTimestamp: (map['latestTimestamp'] as num?)?.toInt() ?? 0,
      avatar: _bytes(map['avatar']),
      appIcon: _bytes(map['appIcon']),
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String appName;
  final String packageName;
  final String title;
  final String latestText;
  final int latestTimestamp;
  final Uint8List avatar;
  final Uint8List appIcon;
  final int unreadCount;

  String get displayTitle => title.trim().isNotEmpty
      ? title.trim()
      : appName.trim().isNotEmpty
      ? appName.trim()
      : 'Unknown conversation';

  String get fallbackInitial =>
      String.fromCharCode(displayTitle.runes.first).toUpperCase();

  String get appInitial {
    final source = appName.trim().isNotEmpty ? appName.trim() : packageName;
    return source.isEmpty
        ? '?'
        : String.fromCharCode(source.runes.first).toUpperCase();
  }

  static Uint8List _bytes(dynamic value) {
    if (value is Uint8List) return value;
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return Uint8List(0);
  }
}

class ConversationMessage {
  const ConversationMessage({
    required this.text,
    required this.sender,
    required this.timestamp,
    required this.direction,
    required this.replyStatus,
  });

  factory ConversationMessage.fromMap(Map<String, dynamic> map) {
    return ConversationMessage(
      text: map['text']?.toString() ?? '',
      sender: map['sender']?.toString(),
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      direction: map['direction']?.toString() ?? 'unknown',
      replyStatus: map['replyStatus']?.toString(),
    );
  }

  final String text;
  final String? sender;
  final int timestamp;
  final String direction;
  final String? replyStatus;

  bool get isOutgoing => direction == 'outgoing';
}
