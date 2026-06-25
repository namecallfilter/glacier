import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/apis/twitch_gql_api.dart';
import 'package:frosty/models/vod_comment.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter dioAdapter;
  late TwitchGqlApi api;
  Map<String, dynamic>? capturedBody;
  Map<String, dynamic>? capturedHeaders;

  setUp(() {
    dio = Dio(BaseOptions());
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedBody = (options.data as Map).cast<String, dynamic>();
          capturedHeaders = options.headers.cast<String, dynamic>();
          handler.next(options);
        },
      ),
    );
    dioAdapter = DioAdapter(dio: dio);
    api = TwitchGqlApi(dio);
  });

  group('getPinnedChats', () {
    test('sends GetPinnedChat persisted query and parses pins', () async {
      dioAdapter.onPost(
        'https://gql.twitch.tv/gql',
        (server) => server.reply(200, {
          'data': {
            'channel': {
              'pinnedChatMessages': {
                'edges': [
                  {
                    'node': {
                      'id': 'pin-1',
                      'pinnedBy': {'displayName': 'ModName'},
                      'pinnedMessage': {
                        'id': 'msg-1',
                        'text': 'Pinned message',
                        'sender': {'displayName': 'SenderName'},
                      },
                    },
                  },
                ],
              },
            },
          },
        }),
        data: Matchers.any,
      );

      final pins = await api.getPinnedChats(channelId: '12345', count: 3);

      expect(pins, hasLength(1));
      expect(pins.single.id, 'pin-1');
      expect(pins.single.messageText, 'Pinned message');
      expect(capturedHeaders?['Client-ID'], isNotEmpty);
      expect(capturedBody?['operationName'], 'GetPinnedChat');
      expect(capturedBody?['variables'], {'channelID': '12345', 'count': 3});
      expect(
        capturedBody?['extensions']?['persistedQuery']?['sha256Hash'],
        '2d099d4c9b6af80a07d8440140c4f3dbb04d516b35c401aab7ce8f60765308d5',
      );
    });

    test('returns empty list for GraphQL errors', () async {
      dioAdapter.onPost(
        'https://gql.twitch.tv/gql',
        (server) => server.reply(200, {
          'errors': [
            {'message': 'PersistedQueryNotFound'},
          ],
        }),
        data: Matchers.any,
      );

      final pins = await api.getPinnedChats(channelId: '12345');

      expect(pins, isEmpty);
    });

    test('returns empty list for malformed successful responses', () async {
      dioAdapter.onPost(
        'https://gql.twitch.tv/gql',
        (server) => server.reply(200, {
          'data': {'channel': null},
        }),
        data: Matchers.any,
      );

      final pins = await api.getPinnedChats(channelId: '12345');

      expect(pins, isEmpty);
    });
  });

  group('getVodCommentsByOffset', () {
    test(
      'sends VideoCommentsByOffsetOrCursor persisted query and parses page',
      () async {
        dioAdapter.onPost(
          'https://gql.twitch.tv/gql',
          (server) => server.reply(200, {
            'data': {
              'video': {
                'comments': {
                  'edges': [
                    {
                      'cursor': 'comment-cursor-1',
                      'node': {
                        'id': 'comment-1',
                        'contentOffsetSeconds': 42,
                        'createdAt': '2024-01-02T00:00:42Z',
                        'commenter': {
                          'id': 'user-1',
                          'login': 'viewer',
                          'displayName': 'Viewer',
                          'profileImageURL': 'https://cdn/viewer.png',
                        },
                        'message': {
                          'userColor': '#8A2BE2',
                          'userBadges': [
                            {
                              'id': 'subscriber',
                              'setID': 'subscriber',
                              'version': '12',
                            },
                          ],
                          'fragments': [
                            {'text': 'hello '},
                            {
                              'text': 'Kappa',
                              'emote': {'emoteID': '25'},
                            },
                          ],
                        },
                      },
                    },
                  ],
                  'pageInfo': {'hasNextPage': true},
                },
              },
            },
          }),
          data: Matchers.any,
        );

        final page = await api.getVodCommentsByOffset(
          videoId: '98765',
          contentOffsetSeconds: 42,
        );

        expect(page.comments, hasLength(1));
        expect(page.comments.single.id, 'comment-1');
        expect(page.comments.single.contentOffsetSeconds, 42);
        expect(page.comments.single.message.body, 'hello Kappa');
        expect(page.comments.single.message.fragments.last.emoteId, '25');
        expect(page.hasNextPage, isTrue);
        expect(capturedHeaders?['Client-ID'], isNotEmpty);
        expect(capturedBody?['operationName'], 'VideoCommentsByOffsetOrCursor');
        expect(capturedBody?['variables'], {
          'videoID': '98765',
          'contentOffsetSeconds': 42,
        });
        expect(
          capturedBody?['extensions']?['persistedQuery']?['sha256Hash'],
          'b70a3591ff0f4e0313d126c6a1502d79a1c02baebb288227c582044aa76adf6a',
        );
      },
    );

    test('returns empty page for GraphQL errors', () async {
      dioAdapter.onPost(
        'https://gql.twitch.tv/gql',
        (server) => server.reply(200, {
          'errors': [
            {'message': 'PersistedQueryNotFound'},
          ],
        }),
        data: Matchers.any,
      );

      final page = await api.getVodCommentsByOffset(
        videoId: '98765',
        contentOffsetSeconds: 0,
      );

      expect(page, VodCommentPage.empty);
    });
  });
}
