import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/apis/twitch_gql_api.dart';
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
}
