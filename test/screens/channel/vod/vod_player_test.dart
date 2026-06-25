import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/models/twitch_video.dart';
import 'package:frosty/models/user.dart';
import 'package:frosty/models/vod_comment.dart';
import 'package:frosty/screens/channel/video/cast_button.dart';
import 'package:frosty/screens/channel/vod/stores/vod_player_store.dart';
import 'package:frosty/screens/channel/vod/vod_player.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/services/cast_state.dart';
import 'package:frosty/services/stream_proxy_bridge.dart';
import 'package:frosty/theme.dart';
import 'package:frosty/widgets/profile_picture.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockTwitchApi extends Mock implements TwitchApi {}

class MockVodPlayerStore extends Mock implements VodPlayerStore {}

void main() {
  late MockTwitchApi twitchApi;

  setUp(() {
    twitchApi = MockTwitchApi();
    when(
      () => twitchApi.getUser(userLogin: any(named: 'userLogin')),
    ).thenAnswer(
      (_) async => const UserTwitch(
        'user-1',
        'caseoh_',
        'caseoh_',
        'https://cdn.example.com/profile.png',
      ),
    );
  });

  tearDown(() {
    StreamProxyBridge.castState.value = const CastState.disconnected();
  });

  VodComment comment({int offset = 65}) {
    return VodComment(
      id: 'comment-1',
      contentOffsetSeconds: offset,
      createdAt: DateTime.parse('2024-01-02T00:00:00Z'),
      commenter: const VodCommenter(
        id: 'user-1',
        login: 'viewer',
        displayName: 'Viewer',
        profileImageUrl: '',
      ),
      message: const VodCommentMessage(
        body: 'hello chat',
        userColor: '#8A2BE2',
        userBadges: [],
        fragments: [VodCommentFragment(text: 'hello chat')],
      ),
    );
  }

  TwitchVideo video() {
    return TwitchVideo(
      id: '98765',
      streamId: 'stream-1',
      userId: 'user-1',
      userLogin: 'caseoh_',
      userName: 'caseoh_',
      title: 'Spooky Time',
      description: '',
      createdAt: DateTime.parse('2024-01-02T00:00:00Z'),
      publishedAt: DateTime.parse('2024-01-02T00:00:00Z'),
      url: 'https://www.twitch.tv/videos/98765',
      thumbnailUrl: '',
      viewable: 'public',
      viewCount: 65425,
      language: 'en',
      type: TwitchVideoType.archive,
      duration: '2h26m36s',
      mutedSegments: const [],
    );
  }

  Widget buildSubject(SettingsStore settingsStore) {
    return Provider<SettingsStore>.value(
      value: settingsStore,
      child: MaterialApp(
        theme: const FrostyThemes(colorSchemeSeed: Color(0xFF9146FF)).dark,
        home: Scaffold(body: VodCommentTile(comment: comment())),
      ),
    );
  }

  Widget buildOverlay({
    required SettingsStore settingsStore,
    required VodPlayerStore playerStore,
  }) {
    return MultiProvider(
      providers: [
        Provider<SettingsStore>.value(value: settingsStore),
        Provider<TwitchApi>.value(value: twitchApi),
      ],
      child: MaterialApp(
        theme: const FrostyThemes(colorSchemeSeed: Color(0xFF9146FF)).dark,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 225,
            child: VodVideoOverlay(
              video: video(),
              playerStore: playerStore,
              settingsStore: settingsStore,
            ),
          ),
        ),
      ),
    );
  }

  MockVodPlayerStore mockPlayerStore() {
    final store = MockVodPlayerStore();
    when(() => store.paused).thenReturn(true);
    when(() => store.currentPosition).thenReturn(Duration.zero);
    when(() => store.duration).thenReturn(const Duration(minutes: 7));
    when(() => store.availableStreamQualities).thenReturn(const []);
    when(() => store.streamQuality).thenReturn('Auto');
    return store;
  }

  testWidgets('hides VOD offsets when timestamps are disabled', (tester) async {
    final settingsStore = SettingsStore()
      ..timestampType = TimestampType.disabled
      ..showHistoricalTimestamps = false;

    await tester.pumpWidget(buildSubject(settingsStore));

    expect(find.textContaining('01:05', findRichText: true), findsNothing);
    expect(find.textContaining('Viewer', findRichText: true), findsOneWidget);
  });

  testWidgets('VOD overlay uses live-style header and cast controls', (
    tester,
  ) async {
    final settingsStore = SettingsStore();
    final playerStore = mockPlayerStore();

    await tester.pumpWidget(
      buildOverlay(settingsStore: settingsStore, playerStore: playerStore),
    );

    expect(find.byType(ProfilePicture), findsOneWidget);
    expect(find.text('caseoh_'), findsOneWidget);
    expect(find.text('Spooky Time'), findsOneWidget);
    expect(find.byType(CastButton), findsOneWidget);
    expect(find.byTooltip('Quality'), findsOneWidget);
  });

  testWidgets('VOD overlay shows connected cast status while casting', (
    tester,
  ) async {
    final settingsStore = SettingsStore();
    final playerStore = mockPlayerStore();
    StreamProxyBridge.castState.value = const CastState(
      isCasting: true,
      receiverName: 'Living Room TV',
    );

    await tester.pumpWidget(
      buildOverlay(settingsStore: settingsStore, playerStore: playerStore),
    );

    expect(find.byTooltip('Casting to Living Room TV'), findsOneWidget);
  });
}
