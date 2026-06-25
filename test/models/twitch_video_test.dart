import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/models/twitch_video.dart';

import '../fixtures/api_responses.dart';

void main() {
  group('TwitchVideo', () {
    test('fromJson deserializes video metadata', () {
      final video = TwitchVideo.fromJson(
        (twitchVideoResponse['data']! as List).first as Map<String, dynamic>,
      );

      expect(video.id, '98765');
      expect(video.streamId, 'stream-123');
      expect(video.userId, '12345');
      expect(video.userLogin, 'testuser');
      expect(video.userName, 'TestUser');
      expect(video.title, 'Past Broadcast');
      expect(video.description, 'A recent stream');
      expect(video.createdAt, DateTime.parse('2024-01-02T00:00:00Z'));
      expect(video.publishedAt, DateTime.parse('2024-01-02T00:05:00Z'));
      expect(video.url, 'https://www.twitch.tv/videos/98765');
      expect(video.viewCount, 321);
      expect(video.language, 'en');
      expect(video.type, TwitchVideoType.archive);
      expect(video.duration, '1h2m3s');
      expect(video.mutedSegments, hasLength(1));
      expect(video.mutedSegments.single.offset, 120);
      expect(video.mutedSegments.single.duration, 30);
    });

    test('thumbnailUrlForSize replaces Twitch thumbnail placeholders', () {
      final video = TwitchVideo.fromJson(
        (twitchVideoResponse['data']! as List).first as Map<String, dynamic>,
      );

      expect(
        video.thumbnailUrlForSize(width: 320, height: 180),
        contains('320x180'),
      );
      expect(
        video.thumbnailUrlForSize(width: 320, height: 180),
        isNot(contains('%{width}')),
      );
    });
  });

  group('TwitchVideos', () {
    test('fromJson deserializes data and pagination', () {
      final videos = TwitchVideos.fromJson(
        twitchVideoResponse as Map<String, dynamic>,
      );

      expect(videos.data, hasLength(1));
      expect(videos.data.first.id, '98765');
      expect(videos.pagination['cursor'], 'videos_cursor');
    });
  });
}
