import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/apis/twitch_gql_api.dart';
import 'package:frosty/models/vod_comment.dart';
import 'package:frosty/screens/channel/vod/stores/vod_chat_replay_store.dart';
import 'package:mocktail/mocktail.dart';

class MockTwitchGqlApi extends Mock implements TwitchGqlApi {}

void main() {
  const videoId = '98765';

  late MockTwitchGqlApi api;

  VodComment comment({
    required String id,
    required int offset,
    String body = 'hello',
  }) {
    return VodComment(
      id: id,
      contentOffsetSeconds: offset,
      createdAt: DateTime.parse('2024-01-02T00:00:00Z'),
      commenter: const VodCommenter(
        id: 'user-1',
        login: 'viewer',
        displayName: 'Viewer',
        profileImageUrl: '',
      ),
      message: VodCommentMessage(
        body: body,
        userColor: '#8A2BE2',
        userBadges: const [],
        fragments: [VodCommentFragment(text: body)],
      ),
    );
  }

  VodChatReplayStore buildStore() =>
      VodChatReplayStore(twitchGqlApi: api, videoId: videoId);

  setUp(() {
    api = MockTwitchGqlApi();
  });

  group('loadAt', () {
    test('fetches comments by playback offset', () async {
      when(
        () => api.getVodCommentsByOffset(
          videoId: videoId,
          contentOffsetSeconds: 42,
        ),
      ).thenAnswer(
        (_) async => VodCommentPage(
          comments: [comment(id: 'comment-1', offset: 42)],
          hasNextPage: true,
        ),
      );

      final store = buildStore();
      await store.loadAt(const Duration(seconds: 42));

      expect(store.comments, hasLength(1));
      expect(store.comments.single.id, 'comment-1');
      expect(store.hasMoreComments, isTrue);
      expect(store.error, isNull);
    });

    test('dedupes comments when the next offset overlaps', () async {
      var offsetCalls = 0;
      when(
        () => api.getVodCommentsByOffset(
          videoId: videoId,
          contentOffsetSeconds: 42,
        ),
      ).thenAnswer((_) async {
        offsetCalls++;
        if (offsetCalls == 1) {
          return VodCommentPage(
            comments: [comment(id: 'comment-1', offset: 42)],
            hasNextPage: true,
          );
        }

        return VodCommentPage(
          comments: [
            comment(id: 'comment-1', offset: 42),
            comment(id: 'comment-2', offset: 44),
          ],
          hasNextPage: false,
        );
      });

      final store = buildStore();
      await store.loadAt(const Duration(seconds: 42));
      await store.loadNextPage();

      expect(store.comments.map((c) => c.id), ['comment-1', 'comment-2']);
      expect(store.hasMoreComments, isFalse);
      verify(
        () => api.getVodCommentsByOffset(
          videoId: videoId,
          contentOffsetSeconds: 42,
        ),
      ).called(2);
    });

    test('seek clears old comments and fetches the new offset', () async {
      when(
        () => api.getVodCommentsByOffset(
          videoId: videoId,
          contentOffsetSeconds: 10,
        ),
      ).thenAnswer(
        (_) async => VodCommentPage(
          comments: [comment(id: 'old', offset: 10)],
          hasNextPage: false,
        ),
      );
      when(
        () => api.getVodCommentsByOffset(
          videoId: videoId,
          contentOffsetSeconds: 120,
        ),
      ).thenAnswer(
        (_) async => VodCommentPage(
          comments: [comment(id: 'new', offset: 120)],
          hasNextPage: false,
        ),
      );

      final store = buildStore();
      await store.loadAt(const Duration(seconds: 10));
      await store.handleSeek(const Duration(seconds: 120));

      expect(store.comments.map((c) => c.id), ['new']);
    });

    test('marks empty replay responses as loaded', () async {
      when(
        () => api.getVodCommentsByOffset(
          videoId: videoId,
          contentOffsetSeconds: 0,
        ),
      ).thenAnswer((_) async => VodCommentPage.empty);

      final store = buildStore();
      await store.loadAt(Duration.zero);

      expect(store.comments, isEmpty);
      expect(store.hasMoreComments, isFalse);
      expect(store.hasLoadedReplay, isTrue);
      expect(store.error, isNull);
    });
  });
}
