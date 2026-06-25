import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/models/channel.dart';
import 'package:frosty/models/stream.dart';
import 'package:frosty/models/twitch_video.dart';
import 'package:frosty/models/user.dart';
import 'package:frosty/screens/channel/profile/stores/channel_profile_store.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../fixtures/api_responses.dart';

class MockTwitchApi extends Mock implements TwitchApi {}

void main() {
  const userId = '12345';
  const userLogin = 'testuser';
  const displayName = 'TestUser';

  late MockTwitchApi api;

  StreamTwitch buildStream() => StreamTwitch.fromJson(
    (twitchStreamResponse['data']! as List).first as Map<String, dynamic>,
  );

  Channel buildChannel() => Channel.fromJson(
    (twitchChannelResponse['data']! as List).first as Map<String, dynamic>,
  );

  UserTwitch buildUser() => UserTwitch.fromJson(
    (twitchUserResponse['data']! as List).first as Map<String, dynamic>,
  );

  TwitchVideos buildVideos() =>
      TwitchVideos.fromJson(twitchVideoResponse as Map<String, dynamic>);

  ChannelProfileStore buildStore() => ChannelProfileStore(
    twitchApi: api,
    userId: userId,
    userLogin: userLogin,
    displayName: displayName,
  );

  setUp(() {
    api = MockTwitchApi();
    when(() => api.getUser(id: userId)).thenAnswer((_) async => buildUser());
    when(
      () => api.getChannel(userId: userId),
    ).thenAnswer((_) async => buildChannel());
    when(
      () => api.getVideos(userId: userId),
    ).thenAnswer((_) async => buildVideos());
  });

  group('init', () {
    test('loads live channel profile and archive videos', () async {
      when(
        () => api.getStream(userLogin: userLogin),
      ).thenAnswer((_) async => buildStream());

      final store = buildStore();
      await store.init();

      expect(store.user?.displayName, displayName);
      expect(store.channelInfo?.title, 'Test Stream');
      expect(store.streamInfo?.userLogin, userLogin);
      expect(store.isLive, isTrue);
      expect(store.primaryActionLabel, 'Live');
      expect(store.videos, hasLength(1));
      expect(store.hasMoreVideos, isTrue);
      expect(store.error, isNull);
    });

    test('loads offline profile and uses chat action', () async {
      when(
        () => api.getStream(userLogin: userLogin),
      ).thenThrow(Exception('offline'));

      final store = buildStore();
      await store.init();

      expect(store.isLive, isFalse);
      expect(store.streamInfo, isNull);
      expect(store.primaryActionLabel, 'Chat');
      expect(store.videos.single.id, '98765');
    });
  });

  group('video filters', () {
    test('selectVideoType resets pagination and loads selected type', () async {
      when(
        () => api.getStream(userLogin: userLogin),
      ).thenAnswer((_) async => buildStream());
      when(
        () => api.getVideos(userId: userId, type: TwitchVideoType.highlight),
      ).thenAnswer((_) async => const TwitchVideos([], <String, String>{}));

      final store = buildStore();
      await store.init();
      await store.selectVideoType(TwitchVideoType.highlight);

      expect(store.selectedVideoType, TwitchVideoType.highlight);
      expect(store.videos, isEmpty);
      expect(store.hasMoreVideos, isFalse);
      verify(
        () => api.getVideos(userId: userId, type: TwitchVideoType.highlight),
      ).called(1);
    });

    test('loadMoreVideos appends next page using cursor', () async {
      when(
        () => api.getStream(userLogin: userLogin),
      ).thenAnswer((_) async => buildStream());
      when(
        () => api.getVideos(userId: userId, cursor: 'videos_cursor'),
      ).thenAnswer((_) async => const TwitchVideos([], <String, String>{}));

      final store = buildStore();
      await store.init();
      await store.loadMoreVideos();

      verify(
        () => api.getVideos(userId: userId, cursor: 'videos_cursor'),
      ).called(1);
      expect(store.videos, hasLength(1));
      expect(store.hasMoreVideos, isFalse);
    });
  });
}
