/// Viewer-side representation of a Twitch pinned chat message.
///
/// Twitch's `GetPinnedChat` GQL operation is undocumented, so this parser is
/// intentionally defensive and accepts the field shapes observed across web
/// responses and related chat-message payloads.
class PinnedChatMessage {
  final String id;
  final String messageId;
  final String messageText;
  final String? senderId;
  final String? senderLogin;
  final String senderDisplayName;
  final String? pinnedById;
  final String? pinnedByLogin;
  final String? pinnedByDisplayName;
  final DateTime? startsAt;
  final DateTime? updatedAt;
  final DateTime? endsAt;
  final DateTime? sentAt;

  const PinnedChatMessage({
    required this.id,
    required this.messageId,
    required this.messageText,
    required this.senderDisplayName,
    this.senderId,
    this.senderLogin,
    this.pinnedById,
    this.pinnedByLogin,
    this.pinnedByDisplayName,
    this.startsAt,
    this.updatedAt,
    this.endsAt,
    this.sentAt,
  });

  bool get hasExpired {
    final expiry = endsAt;
    return expiry != null && !expiry.isAfter(DateTime.now().toUtc());
  }

  static List<PinnedChatMessage> listFromGqlResponse(
    Map<String, dynamic> json,
  ) {
    final data = _asMap(json['data']);
    final channel = _asMap(data?['channel']);
    final pinnedChatMessages = _asMap(channel?['pinnedChatMessages']);
    final edges = _asList(pinnedChatMessages?['edges']);
    if (edges == null) return const [];

    return edges
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map((edge) => _asMap(edge['node']))
        .whereType<Map<String, dynamic>>()
        .map(fromGqlNode)
        .whereType<PinnedChatMessage>()
        .toList();
  }

  static PinnedChatMessage? fromGqlNode(Map<String, dynamic> node) {
    final pinnedMessage = _asMap(node['pinnedMessage']);
    if (pinnedMessage == null) return null;

    final id = _asString(node['id']);
    final messageId = _asString(pinnedMessage['id']);
    if (id == null || messageId == null) return null;

    final sender = _asMap(pinnedMessage['sender']);
    final pinnedBy = _asMap(node['pinnedBy']);
    final messageText = _extractMessageText(pinnedMessage);
    final senderDisplayName =
        _asString(sender?['displayName']) ??
        _asString(sender?['display_name']) ??
        _asString(sender?['login']) ??
        'Unknown';

    return PinnedChatMessage(
      id: id,
      messageId: messageId,
      messageText: messageText,
      senderId: _asString(sender?['id']),
      senderLogin:
          _asString(sender?['login']) ?? _asString(sender?['userLogin']),
      senderDisplayName: senderDisplayName,
      pinnedById: _asString(pinnedBy?['id']),
      pinnedByLogin:
          _asString(pinnedBy?['login']) ?? _asString(pinnedBy?['userLogin']),
      pinnedByDisplayName:
          _asString(pinnedBy?['displayName']) ??
          _asString(pinnedBy?['display_name']),
      startsAt: _parseDate(node['startsAt']),
      updatedAt: _parseDate(node['updatedAt']),
      endsAt: _parseDate(node['endsAt']),
      sentAt: _parseDate(pinnedMessage['sentAt']),
    );
  }

  static String _extractMessageText(Map<String, dynamic> pinnedMessage) {
    final directText =
        _asString(pinnedMessage['text']) ??
        _asString(_asMap(pinnedMessage['message'])?['text']) ??
        _asString(_asMap(pinnedMessage['content'])?['text']);
    if (directText != null) return directText;

    final fragments =
        _asList(pinnedMessage['fragments']) ??
        _asList(_asMap(pinnedMessage['message'])?['fragments']) ??
        _asList(_asMap(pinnedMessage['content'])?['fragments']);
    if (fragments == null) return '';

    return fragments
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map((fragment) => _asString(fragment['text']) ?? '')
        .join();
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return null;
  }

  static List<dynamic>? _asList(Object? value) => value is List ? value : null;

  static String? _asString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static DateTime? _parseDate(Object? value) {
    final text = _asString(value);
    if (text == null) return null;
    return DateTime.tryParse(text)?.toUtc();
  }
}
