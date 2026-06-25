import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:frosty/apis/base_api_client.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/models/pinned_chat.dart';
import 'package:frosty/models/vod_comment.dart';

/// Twitch GraphQL client for viewer-accessible, web-client-backed operations.
///
/// This uses Twitch's web client ID, not Glacier's Helix app client ID.
class TwitchGqlApi extends BaseApiClient {
  static const _getPinnedChatHash =
      '2d099d4c9b6af80a07d8440140c4f3dbb04d516b35c401aab7ce8f60765308d5';
  static const _videoCommentsByOffsetOrCursorHash =
      'b70a3591ff0f4e0313d126c6a1502d79a1c02baebb288227c582044aa76adf6a';

  TwitchGqlApi(Dio dio) : super(dio, 'https://gql.twitch.tv');

  Future<List<PinnedChatMessage>> getPinnedChats({
    required String channelId,
    int count = 5,
  }) async {
    final response = await post<JsonMap>(
      '/gql',
      headers: const {'Client-ID': twitchGqlClientId},
      data: {
        'operationName': 'GetPinnedChat',
        'variables': {'channelID': channelId, 'count': count},
        'extensions': {
          'persistedQuery': {'version': 1, 'sha256Hash': _getPinnedChatHash},
        },
      },
    );

    if (response['errors'] != null) {
      debugPrint('TwitchGqlApi.getPinnedChats errors: ${response['errors']}');
      return const [];
    }

    try {
      return PinnedChatMessage.listFromGqlResponse(response);
    } catch (e) {
      debugPrint('TwitchGqlApi.getPinnedChats parse error: $e');
      return const [];
    }
  }

  Future<VodCommentPage> getVodCommentsByOffset({
    required String videoId,
    required int contentOffsetSeconds,
  }) async {
    final response = await post<JsonMap>(
      '/gql',
      headers: const {'Client-ID': twitchGqlClientId},
      data: {
        'operationName': 'VideoCommentsByOffsetOrCursor',
        'variables': {
          'videoID': videoId,
          'contentOffsetSeconds': contentOffsetSeconds,
        },
        'extensions': {
          'persistedQuery': {
            'version': 1,
            'sha256Hash': _videoCommentsByOffsetOrCursorHash,
          },
        },
      },
    );

    if (response['errors'] != null) {
      debugPrint('TwitchGqlApi.getVodComments errors: ${response['errors']}');
      return VodCommentPage.empty;
    }

    try {
      return VodCommentPage.fromGqlResponse(response);
    } catch (e) {
      debugPrint('TwitchGqlApi.getVodComments parse error: $e');
      return VodCommentPage.empty;
    }
  }
}
