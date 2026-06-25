import 'package:json_annotation/json_annotation.dart';

part 'twitch_video.g.dart';

@JsonEnum(fieldRename: FieldRename.snake)
enum TwitchVideoType { all, archive, highlight, upload }

@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class TwitchVideoMutedSegment {
  final int duration;
  final int offset;

  const TwitchVideoMutedSegment({required this.duration, required this.offset});

  factory TwitchVideoMutedSegment.fromJson(Map<String, dynamic> json) =>
      _$TwitchVideoMutedSegmentFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class TwitchVideo {
  final String id;
  final String streamId;
  final String userId;
  final String userLogin;
  final String userName;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime publishedAt;
  final String url;
  final String thumbnailUrl;
  final String viewable;
  final int viewCount;
  final String language;
  final TwitchVideoType type;
  final String duration;

  @JsonKey(defaultValue: <TwitchVideoMutedSegment>[])
  final List<TwitchVideoMutedSegment> mutedSegments;

  const TwitchVideo({
    required this.id,
    required this.streamId,
    required this.userId,
    required this.userLogin,
    required this.userName,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.publishedAt,
    required this.url,
    required this.thumbnailUrl,
    required this.viewable,
    required this.viewCount,
    required this.language,
    required this.type,
    required this.duration,
    required this.mutedSegments,
  });

  factory TwitchVideo.fromJson(Map<String, dynamic> json) =>
      _$TwitchVideoFromJson(json);

  String thumbnailUrlForSize({required int width, required int height}) {
    return thumbnailUrl
        .replaceAll('%{width}', width.toString())
        .replaceAll('%{height}', height.toString())
        .replaceAll('{width}', width.toString())
        .replaceAll('{height}', height.toString());
  }
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class TwitchVideos {
  final List<TwitchVideo> data;
  final Map<String, String> pagination;

  const TwitchVideos(this.data, this.pagination);

  factory TwitchVideos.fromJson(Map<String, dynamic> json) =>
      _$TwitchVideosFromJson(json);
}
