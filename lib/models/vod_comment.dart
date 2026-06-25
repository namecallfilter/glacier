import 'package:flutter/foundation.dart';

class VodCommentPage {
  static const empty = VodCommentPage(
    comments: <VodComment>[],
    hasNextPage: false,
  );

  final List<VodComment> comments;
  final bool hasNextPage;

  const VodCommentPage({required this.comments, required this.hasNextPage});

  static VodCommentPage fromGqlResponse(Map<String, dynamic> response) {
    final data = _asMap(response['data']);
    final video = _asMap(data?['video']);
    final comments = _asMap(video?['comments']);
    final edges = _asList(comments?['edges']);
    final pageInfo = _asMap(comments?['pageInfo']);

    if (edges == null || edges.isEmpty) return empty;

    final parsedComments = <VodComment>[];

    for (final edgeValue in edges) {
      final edge = _asMap(edgeValue);
      if (edge == null) continue;

      final node = _asMap(edge['node']);
      final comment = node == null ? null : VodComment.fromGqlNode(node);
      if (comment == null) continue;

      parsedComments.add(comment);
    }

    if (parsedComments.isEmpty) return empty;

    return VodCommentPage(
      comments: parsedComments,
      hasNextPage: pageInfo?['hasNextPage'] == true,
    );
  }
}

class VodComment {
  final String id;
  final int contentOffsetSeconds;
  final DateTime? createdAt;
  final VodCommenter? commenter;
  final VodCommentMessage message;

  const VodComment({
    required this.id,
    required this.contentOffsetSeconds,
    required this.createdAt,
    required this.commenter,
    required this.message,
  });

  static VodComment? fromGqlNode(Map<String, dynamic> node) {
    final id = node['id'] as String?;
    final offset = _asInt(node['contentOffsetSeconds']);
    final message = _asMap(node['message']);

    if (id == null || offset == null || message == null) return null;

    return VodComment(
      id: id,
      contentOffsetSeconds: offset,
      createdAt: DateTime.tryParse(node['createdAt'] as String? ?? ''),
      commenter: VodCommenter.fromGql(_asMap(node['commenter'])),
      message: VodCommentMessage.fromGql(message),
    );
  }
}

class VodCommenter {
  final String id;
  final String login;
  final String displayName;
  final String profileImageUrl;

  const VodCommenter({
    required this.id,
    required this.login,
    required this.displayName,
    required this.profileImageUrl,
  });

  static VodCommenter? fromGql(Map<String, dynamic>? value) {
    if (value == null) return null;

    final id = value['id'] as String?;
    final login = value['login'] as String?;
    final displayName = value['displayName'] as String?;
    final profileImageUrl = value['profileImageURL'] as String?;

    if (id == null || login == null || displayName == null) return null;

    return VodCommenter(
      id: id,
      login: login,
      displayName: displayName,
      profileImageUrl: profileImageUrl ?? '',
    );
  }
}

class VodCommentMessage {
  final String body;
  final String userColor;
  final List<VodCommentBadge> userBadges;
  final List<VodCommentFragment> fragments;

  const VodCommentMessage({
    required this.body,
    required this.userColor,
    required this.userBadges,
    required this.fragments,
  });

  static VodCommentMessage fromGql(Map<String, dynamic> value) {
    final badges = _asList(value['userBadges']) ?? const <Object?>[];
    final fragments = _asList(value['fragments']) ?? const <Object?>[];
    final parsedFragments = fragments
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(VodCommentFragment.fromGql)
        .whereType<VodCommentFragment>()
        .toList();

    return VodCommentMessage(
      body:
          value['body'] as String? ??
          parsedFragments.map((fragment) => fragment.text).join(),
      userColor: value['userColor'] as String? ?? '#868686',
      userBadges: badges
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map(VodCommentBadge.fromGql)
          .whereType<VodCommentBadge>()
          .toList(),
      fragments: parsedFragments,
    );
  }
}

class VodCommentBadge {
  final String setId;
  final String version;

  const VodCommentBadge({required this.setId, required this.version});

  static VodCommentBadge? fromGql(Map<String, dynamic> value) {
    final setId = value['setID'] as String? ?? value['id'] as String?;
    final version = value['version'] as String?;
    if (setId == null || version == null) return null;

    return VodCommentBadge(setId: setId, version: version);
  }
}

class VodCommentFragment {
  final String text;
  final String? emoteId;

  const VodCommentFragment({required this.text, this.emoteId});

  static VodCommentFragment? fromGql(Map<String, dynamic> value) {
    final text = value['text'] as String?;
    if (text == null) return null;

    final emote = _asMap(value['emote']);

    return VodCommentFragment(
      text: text,
      emoteId: emote?['emoteID'] as String?,
    );
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

List<Object?>? _asList(Object? value) {
  if (value is List<Object?>) return value;
  if (value is List) return value.cast<Object?>();
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

@visibleForTesting
VodCommentPage parseVodCommentPageForTesting(Map<String, dynamic> response) =>
    VodCommentPage.fromGqlResponse(response);
