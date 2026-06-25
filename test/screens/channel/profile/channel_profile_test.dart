import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/models/channel.dart';
import 'package:frosty/models/stream.dart';
import 'package:frosty/models/twitch_video.dart';
import 'package:frosty/models/user.dart';
import 'package:frosty/screens/channel/profile/channel_profile.dart';
import 'package:frosty/theme.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../../../fixtures/api_responses.dart';

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

  Widget buildSubject() {
    return Provider<TwitchApi>.value(
      value: api,
      child: MaterialApp(
        theme: FrostyThemes(colorSchemeSeed: Colors.purple).dark,
        home: const ChannelProfile(
          userId: userId,
          userName: displayName,
          userLogin: userLogin,
        ),
      ),
    );
  }

  setUp(() {
    api = MockTwitchApi();
    when(() => api.getUser(id: userId)).thenAnswer((_) async => buildUser());
    when(
      () => api.getUser(userLogin: userLogin),
    ).thenAnswer((_) async => buildUser());
    when(
      () => api.getChannel(userId: userId),
    ).thenAnswer((_) async => buildChannel());
    when(
      () => api.getVideos(userId: userId),
    ).thenAnswer((_) async => buildVideos());
  });

  testWidgets('shows live status, live action, and VODs', (tester) async {
    when(
      () => api.getStream(userLogin: userLogin),
    ).thenAnswer((_) async => buildStream());

    await tester.pumpWidget(buildSubject());
    await tester.pump();
    await tester.pump();

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Live'), findsOneWidget);
    expect(find.text('Past Broadcast'), findsOneWidget);
  });

  testWidgets('shows chat action when offline', (tester) async {
    when(
      () => api.getStream(userLogin: userLogin),
    ).thenThrow(Exception('offline'));

    await tester.pumpWidget(buildSubject());
    await tester.pump();
    await tester.pump();

    expect(find.text('LIVE'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Chat'), findsOneWidget);
    expect(find.text('Past Broadcast'), findsOneWidget);
  });
}
