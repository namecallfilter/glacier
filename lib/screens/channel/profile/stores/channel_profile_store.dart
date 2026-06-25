import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/models/channel.dart';
import 'package:frosty/models/stream.dart';
import 'package:frosty/models/twitch_video.dart';
import 'package:frosty/models/user.dart';
import 'package:mobx/mobx.dart';

part 'channel_profile_store.g.dart';

class ChannelProfileStore = ChannelProfileStoreBase with _$ChannelProfileStore;

abstract class ChannelProfileStoreBase with Store {
  final TwitchApi twitchApi;
  final String userId;
  final String userLogin;
  final String displayName;

  String? _videosCursor;

  ChannelProfileStoreBase({
    required this.twitchApi,
    required this.userId,
    required this.userLogin,
    required this.displayName,
  });

  @readonly
  UserTwitch? _user;

  @readonly
  Channel? _channelInfo;

  @readonly
  StreamTwitch? _streamInfo;

  @readonly
  var _videos = ObservableList<TwitchVideo>();

  @readonly
  var _isLoading = false;

  @readonly
  var _isVideosLoading = false;

  @readonly
  String? _error;

  @observable
  var selectedVideoType = TwitchVideoType.archive;

  @computed
  bool get isLive => _streamInfo != null;

  @computed
  bool get hasMoreVideos => _videosCursor != null && !_isVideosLoading;

  @computed
  String get primaryActionLabel => isLive ? 'Live' : 'Chat';

  @action
  Future<void> init() async {
    _isLoading = true;
    _error = null;

    try {
      _user = await twitchApi.getUser(id: userId);
      _channelInfo = await twitchApi.getChannel(userId: userId);
      await _refreshLiveState();
      await _loadVideos(reset: true);
    } catch (e) {
      _error = 'Unable to load channel profile';
    } finally {
      _isLoading = false;
    }
  }

  @action
  Future<void> refresh() async {
    _videosCursor = null;
    await init();
  }

  @action
  Future<void> selectVideoType(TwitchVideoType type) async {
    if (selectedVideoType == type && _videos.isNotEmpty) return;

    selectedVideoType = type;
    await _loadVideos(reset: true);
  }

  @action
  Future<void> loadMoreVideos() async {
    if (_videosCursor == null || _isVideosLoading) return;

    await _loadVideos(reset: false);
  }

  Future<void> _refreshLiveState() async {
    try {
      _streamInfo = await twitchApi.getStream(userLogin: userLogin);
    } catch (_) {
      _streamInfo = null;
    }
  }

  Future<void> _loadVideos({required bool reset}) async {
    if (_isVideosLoading) return;

    _isVideosLoading = true;
    if (reset) {
      _videosCursor = null;
      _videos.clear();
    }

    try {
      final TwitchVideos response;
      if (selectedVideoType == TwitchVideoType.archive) {
        response = _videosCursor == null
            ? await twitchApi.getVideos(userId: userId)
            : await twitchApi.getVideos(userId: userId, cursor: _videosCursor);
      } else {
        response = _videosCursor == null
            ? await twitchApi.getVideos(userId: userId, type: selectedVideoType)
            : await twitchApi.getVideos(
                userId: userId,
                type: selectedVideoType,
                cursor: _videosCursor,
              );
      }

      if (reset) {
        _videos = response.data.asObservable();
      } else {
        _videos.addAll(response.data);
      }
      _videosCursor = response.pagination['cursor'];
      _error = null;
    } catch (e) {
      _error = 'Unable to load videos';
    } finally {
      _isVideosLoading = false;
    }
  }
}
