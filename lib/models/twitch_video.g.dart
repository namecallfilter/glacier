// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'twitch_video.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TwitchVideoMutedSegment _$TwitchVideoMutedSegmentFromJson(
  Map<String, dynamic> json,
) => TwitchVideoMutedSegment(
  duration: (json['duration'] as num).toInt(),
  offset: (json['offset'] as num).toInt(),
);

TwitchVideo _$TwitchVideoFromJson(Map<String, dynamic> json) => TwitchVideo(
  id: json['id'] as String,
  streamId: json['stream_id'] as String,
  userId: json['user_id'] as String,
  userLogin: json['user_login'] as String,
  userName: json['user_name'] as String,
  title: json['title'] as String,
  description: json['description'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  publishedAt: DateTime.parse(json['published_at'] as String),
  url: json['url'] as String,
  thumbnailUrl: json['thumbnail_url'] as String,
  viewable: json['viewable'] as String,
  viewCount: (json['view_count'] as num).toInt(),
  language: json['language'] as String,
  type: $enumDecode(_$TwitchVideoTypeEnumMap, json['type']),
  duration: json['duration'] as String,
  mutedSegments:
      (json['muted_segments'] as List<dynamic>?)
          ?.map(
            (e) => TwitchVideoMutedSegment.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      [],
);

const _$TwitchVideoTypeEnumMap = {
  TwitchVideoType.all: 'all',
  TwitchVideoType.archive: 'archive',
  TwitchVideoType.highlight: 'highlight',
  TwitchVideoType.upload: 'upload',
};

TwitchVideos _$TwitchVideosFromJson(Map<String, dynamic> json) => TwitchVideos(
  (json['data'] as List<dynamic>)
      .map((e) => TwitchVideo.fromJson(e as Map<String, dynamic>))
      .toList(),
  Map<String, String>.from(json['pagination'] as Map),
);
