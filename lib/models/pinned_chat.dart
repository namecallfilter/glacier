import 'package:frosty/models/badges.dart';

const _twitchEmoteBaseUrl = 'https://static-cdn.jtvnw.net/emoticons/v2';
const _twitchEmoteModeSuffix = '/default/dark/3.0';

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
  final String? senderColor;
  final String senderDisplayName;
  final List<PinnedChatBadge> senderBadges;
  final List<PinnedChatFragment> fragments;
  final String? pinnedById;
  final String? pinnedByLogin;
  final String? pinnedByColor;
  final String? pinnedByDisplayName;
  final List<PinnedChatBadge> pinnedByBadges;
  final DateTime? startsAt;
  final DateTime? updatedAt;
  final DateTime? endsAt;
  final DateTime? sentAt;

  const PinnedChatMessage({
    required this.id,
    required this.messageId,
    required this.messageText,
    required this.senderDisplayName,
    this.senderBadges = const [],
    this.fragments = const [],
    this.senderId,
    this.senderLogin,
    this.senderColor,
    this.pinnedById,
    this.pinnedByLogin,
    this.pinnedByColor,
    this.pinnedByDisplayName,
    this.pinnedByBadges = const [],
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
    final fragments = _extractFragments(pinnedMessage);
    final messageText = _extractMessageText(pinnedMessage, fragments);
    final senderBadges = _extractFirstBadges([
      pinnedMessage['badges'],
      pinnedMessage['displayBadges'],
      pinnedMessage['chatBadges'],
      pinnedMessage['badgeInfo'],
      pinnedMessage['senderBadges'],
      sender?['badges'],
      sender?['displayBadges'],
      sender?['chatBadges'],
      sender?['badgeInfo'],
    ]);
    final directPinnedByBadges = _extractFirstBadges([
      pinnedBy?['badges'],
      pinnedBy?['displayBadges'],
      pinnedBy?['chatBadges'],
      pinnedBy?['badgeInfo'],
    ]);
    final pinnedByBadges = directPinnedByBadges.isNotEmpty
        ? directPinnedByBadges
        : _inferPinnedByBadges(
            node: node,
            pinnedBy: pinnedBy,
            sender: sender,
            senderBadges: senderBadges,
          );
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
      senderColor: _extractChatColor(sender),
      senderDisplayName: senderDisplayName,
      senderBadges: senderBadges,
      fragments: fragments,
      pinnedById: _asString(pinnedBy?['id']),
      pinnedByLogin:
          _asString(pinnedBy?['login']) ?? _asString(pinnedBy?['userLogin']),
      pinnedByColor: _extractChatColor(pinnedBy),
      pinnedByDisplayName:
          _asString(pinnedBy?['displayName']) ??
          _asString(pinnedBy?['display_name']),
      pinnedByBadges: pinnedByBadges,
      startsAt: _parseDate(node['startsAt']),
      updatedAt: _parseDate(node['updatedAt']),
      endsAt: _parseDate(node['endsAt']),
      sentAt: _parseDate(pinnedMessage['sentAt']),
    );
  }

  static String _extractMessageText(
    Map<String, dynamic> pinnedMessage,
    List<PinnedChatFragment> fragments,
  ) {
    final directText =
        _asString(pinnedMessage['text']) ??
        _asString(_asMap(pinnedMessage['message'])?['text']) ??
        _asString(_asMap(pinnedMessage['content'])?['text']);
    if (directText != null) return directText;

    if (fragments.isEmpty) return '';

    return fragments.map((fragment) => fragment.text).join();
  }

  static List<PinnedChatFragment> _extractFragments(
    Map<String, dynamic> pinnedMessage,
  ) {
    final fragments =
        _asList(pinnedMessage['fragments']) ??
        _asList(_asMap(pinnedMessage['message'])?['fragments']) ??
        _asList(_asMap(pinnedMessage['content'])?['fragments']);
    if (fragments == null) return const [];

    return fragments
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(_parseFragment)
        .whereType<PinnedChatFragment>()
        .toList();
  }

  static PinnedChatFragment? _parseFragment(Map<String, dynamic> fragment) {
    final text = _asString(fragment['text']) ?? '';
    final emote = _extractEmote(fragment, text);
    if (text.isEmpty && emote == null) return null;
    return PinnedChatFragment(text: text, emote: emote);
  }

  static PinnedChatEmote? _extractEmote(
    Map<String, dynamic> fragment,
    String text,
  ) {
    final candidates = [
      _asMap(fragment['emote']),
      _asMap(fragment['content']),
      fragment,
    ].whereType<Map<String, dynamic>>();

    for (final candidate in candidates) {
      final id =
          _asString(candidate['emoteID']) ??
          _asString(candidate['emoteId']) ??
          _asString(candidate['id']);
      if (id == null) continue;

      return PinnedChatEmote(
        id: id,
        text:
            _asString(candidate['token']) ??
            _asString(candidate['name']) ??
            text,
        imageUrl: _extractImageUrl(candidate),
      );
    }

    return null;
  }

  static List<PinnedChatBadge> _extractFirstBadges(Iterable<Object?> values) {
    for (final value in values) {
      final badges = _extractBadges(value);
      if (badges.isNotEmpty) return badges;
    }

    return const [];
  }

  static List<PinnedChatBadge> _extractBadges(Object? value) {
    final list = _asList(value);
    if (list != null) {
      return _dedupeBadges(list.expand(_extractBadges));
    }

    final map = _asMap(value);
    if (map == null) return const [];

    final parsedBadge = _parseBadge(map);
    if (parsedBadge != null) return [parsedBadge];

    final badges = <PinnedChatBadge>[];
    for (final key in const [
      'edges',
      'nodes',
      'items',
      'badges',
      'displayBadges',
      'chatBadges',
      'badgeInfo',
    ]) {
      badges.addAll(_extractBadges(map[key]));
    }

    for (final key in const ['node', 'badge']) {
      badges.addAll(_extractBadges(map[key]));
    }

    if (badges.isNotEmpty) return _dedupeBadges(badges);

    for (final entry in map.entries) {
      final entryValue = _asMap(entry.value);
      if (entryValue == null) continue;

      final candidate = Map<String, dynamic>.from(entryValue);
      if (!_hasBadgeSetId(candidate)) {
        candidate.putIfAbsent('id', () => entry.key);
      }
      badges.addAll(_extractBadges(candidate));
    }

    return _dedupeBadges(badges);
  }

  static List<PinnedChatBadge> _inferPinnedByBadges({
    required Map<String, dynamic> node,
    required Map<String, dynamic>? pinnedBy,
    required Map<String, dynamic>? sender,
    required List<PinnedChatBadge> senderBadges,
  }) {
    final typeBadge = _authorityBadgeForPinnedType(_asString(node['type']));
    if (typeBadge != null) return [typeBadge];

    if (!_isSameUser(pinnedBy, sender)) return const [];
    return senderBadges.where(_isAuthorityBadge).toList(growable: false);
  }

  static PinnedChatBadge? _authorityBadgeForPinnedType(String? type) {
    final label = _normalizeBadgeLabel(type ?? '');
    if (label == 'mod' || label == 'moderator') {
      return const PinnedChatBadge(
        setId: 'moderator',
        version: '1',
        title: 'Moderator',
      );
    }

    if (label == 'headmod' || label == 'headmoderator') {
      return const PinnedChatBadge(
        setId: 'head-moderator',
        version: '1',
        title: 'Head Mod',
      );
    }

    if (label == 'broadcaster' || label == 'channelowner') {
      return const PinnedChatBadge(
        setId: 'broadcaster',
        version: '1',
        title: 'Broadcaster',
      );
    }

    return null;
  }

  static bool _isSameUser(
    Map<String, dynamic>? first,
    Map<String, dynamic>? second,
  ) {
    final firstId = _asString(first?['id']);
    final secondId = _asString(second?['id']);
    if (firstId != null && secondId != null) return firstId == secondId;

    final firstLogin =
        _asString(first?['login']) ?? _asString(first?['userLogin']);
    final secondLogin =
        _asString(second?['login']) ?? _asString(second?['userLogin']);
    if (firstLogin != null && secondLogin != null) {
      return firstLogin.toLowerCase() == secondLogin.toLowerCase();
    }

    final firstName =
        _asString(first?['displayName']) ?? _asString(first?['display_name']);
    final secondName =
        _asString(second?['displayName']) ?? _asString(second?['display_name']);
    if (firstName != null && secondName != null) {
      return firstName.toLowerCase() == secondName.toLowerCase();
    }

    return false;
  }

  static bool _isAuthorityBadge(PinnedChatBadge badge) {
    return [
      badge.setId,
      badge.title,
    ].map(_normalizeBadgeLabel).any(_isAuthorityBadgeLabel);
  }

  static String _normalizeBadgeLabel(String label) {
    return label.toLowerCase().replaceAll(RegExp(r'[\s_\-/]'), '');
  }

  static bool _isAuthorityBadgeLabel(String label) {
    return label == 'mod' ||
        label == 'moderator' ||
        label == 'headmod' ||
        label == 'headmoderator' ||
        label == 'broadcaster';
  }

  static List<PinnedChatBadge> _dedupeBadges(Iterable<PinnedChatBadge> badges) {
    final seen = <String>{};
    final result = <PinnedChatBadge>[];
    for (final badge in badges) {
      if (seen.add(badge.key)) result.add(badge);
    }
    return result;
  }

  static PinnedChatBadge? _parseBadge(Map<String, dynamic> badge) {
    if (!_hasBadgeIdentity(badge)) return null;

    var setId = _extractBadgeSetId(badge);
    var version = _extractBadgeVersion(badge);
    final imageUrl = _extractImageUrl(badge);
    final rawId = _asString(badge['id']);

    if (setId == null && rawId != null && rawId.contains('/')) {
      setId = rawId;
    }

    if (setId != null && setId.contains('/') && version == null) {
      final parts = setId.split('/');
      setId = parts.first;
      version = parts.length > 1 ? parts[1] : null;
    }

    final title =
        _asString(badge['title']) ??
        _asString(badge['name']) ??
        setId ??
        'Twitch badge';

    if (setId == null && imageUrl == null) return null;

    return PinnedChatBadge(
      setId: setId ?? title,
      version: version ?? '1',
      title: title,
      imageUrl: imageUrl,
    );
  }

  static bool _hasBadgeIdentity(Map<String, dynamic> badge) {
    if (_hasBadgeSetId(badge) || _extractBadgeVersion(badge) != null) {
      return true;
    }

    final id = _asString(badge['id']);
    return (id != null && id.contains('/')) || _extractImageUrl(badge) != null;
  }

  static bool _hasBadgeSetId(Map<String, dynamic> badge) {
    return _extractBadgeSetId(badge) != null;
  }

  static String? _extractBadgeSetId(Map<String, dynamic> badge) {
    return _asString(badge['setID']) ??
        _asString(badge['setId']) ??
        _asString(badge['set_id']) ??
        _asString(badge['badgeSetID']) ??
        _asString(badge['badgeSetId']) ??
        _asString(badge['badge_set_id']) ??
        _asString(badge['badgeSet']) ??
        _asString(badge['set']);
  }

  static String? _extractBadgeVersion(Map<String, dynamic> badge) {
    return _asString(badge['version']) ??
        _asString(badge['versionID']) ??
        _asString(badge['versionId']) ??
        _asString(badge['version_id']) ??
        _asString(badge['badgeVersion']) ??
        _asString(badge['badgeVersionID']) ??
        _asString(badge['badgeVersionId']) ??
        _asString(badge['badge_version']);
  }

  static String? _extractImageUrl(Map<String, dynamic> value) {
    for (final key in const [
      'imageURL4x',
      'imageUrl4x',
      'image_url_4x',
      'image4x',
      'url4x',
      'imageURL2x',
      'imageUrl2x',
      'image_url_2x',
      'image2x',
      'url2x',
      'imageURL1x',
      'imageUrl1x',
      'image_url_1x',
      'image1x',
      'url1x',
      'imageURL',
      'imageUrl',
      'image_url',
      'url',
    ]) {
      final url = _asString(value[key]);
      if (url != null) return _normalizeImageUrl(url);
    }

    for (final key in const ['image', 'images', 'urls']) {
      final nestedMap = _asMap(value[key]);
      if (nestedMap != null) {
        final url = _extractImageUrl(nestedMap);
        if (url != null) return url;
      }

      final nestedList = _asList(value[key]);
      if (nestedList != null) {
        for (final nested in nestedList.reversed) {
          final nestedUrl = _extractImageUrl(_asMap(nested) ?? const {});
          if (nestedUrl != null) return nestedUrl;
        }
      }
    }

    return null;
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return null;
  }

  static List<dynamic>? _asList(Object? value) => value is List ? value : null;

  static String? _asString(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is num) return value.toString();
    return null;
  }

  static DateTime? _parseDate(Object? value) {
    final text = _asString(value);
    if (text == null) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static String? _extractChatColor(Map<String, dynamic>? user) {
    if (user == null) return null;

    for (final key in const [
      'chatColor',
      'chat_color',
      'color',
      'nameColor',
      'name_color',
    ]) {
      final color = _asString(user[key]);
      if (color != null) return color;
    }

    return null;
  }

  static String _normalizeImageUrl(String url) =>
      url.startsWith('//') ? 'https:$url' : url;
}

class PinnedChatFragment {
  final String text;
  final PinnedChatEmote? emote;

  const PinnedChatFragment({required this.text, this.emote});
}

class PinnedChatEmote {
  final String id;
  final String text;
  final String? _imageUrl;

  const PinnedChatEmote({
    required this.id,
    required this.text,
    String? imageUrl,
  }) : _imageUrl = imageUrl;

  String get imageUrl =>
      _imageUrl ?? '$_twitchEmoteBaseUrl/$id$_twitchEmoteModeSuffix';
}

class PinnedChatBadge {
  final String setId;
  final String version;
  final String title;
  final String? imageUrl;

  const PinnedChatBadge({
    required this.setId,
    required this.version,
    required this.title,
    this.imageUrl,
  });

  String get key => '$setId/$version';

  ChatBadge? resolve(Map<String, ChatBadge> twitchBadges) {
    final directImageUrl = imageUrl;
    if (directImageUrl != null) {
      return ChatBadge(
        name: title,
        url: directImageUrl,
        type: BadgeType.twitch,
      );
    }

    return twitchBadges[key];
  }
}
