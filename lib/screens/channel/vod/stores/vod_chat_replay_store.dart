import 'package:frosty/apis/twitch_gql_api.dart';
import 'package:frosty/models/vod_comment.dart';
import 'package:mobx/mobx.dart';

part 'vod_chat_replay_store.g.dart';

class VodChatReplayStore = VodChatReplayStoreBase with _$VodChatReplayStore;

abstract class VodChatReplayStoreBase with Store {
  static const _commentLimit = 500;

  final TwitchGqlApi twitchGqlApi;
  final String videoId;

  int? _nextOffsetSeconds;
  final _seenCommentIds = <String>{};

  VodChatReplayStoreBase({required this.twitchGqlApi, required this.videoId});

  @readonly
  var _comments = ObservableList<VodComment>();

  @readonly
  var _isLoading = false;

  @readonly
  String? _error;

  @readonly
  var _hasLoadedReplay = false;

  @computed
  bool get hasMoreComments => _nextOffsetSeconds != null && !_isLoading;

  @action
  Future<void> loadAt(Duration position) async {
    await _loadFromOffset(position.inSeconds, reset: true);
  }

  @action
  Future<void> handleSeek(Duration position) async {
    await _loadFromOffset(position.inSeconds, reset: true);
  }

  @action
  Future<void> loadNextPage() async {
    final offsetSeconds = _nextOffsetSeconds;
    if (offsetSeconds == null || _isLoading) return;

    _isLoading = true;
    try {
      final page = await twitchGqlApi.getVodCommentsByOffset(
        videoId: videoId,
        contentOffsetSeconds: offsetSeconds,
      );
      _appendPage(page, requestedOffsetSeconds: offsetSeconds);
      _hasLoadedReplay = true;
      _error = null;
    } catch (e) {
      _nextOffsetSeconds = null;
      _hasLoadedReplay = true;
      _error = 'Chat replay unavailable';
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _loadFromOffset(
    int contentOffsetSeconds, {
    required bool reset,
  }) async {
    if (_isLoading) return;

    _isLoading = true;
    if (reset) {
      _nextOffsetSeconds = null;
      _hasLoadedReplay = false;
      _seenCommentIds.clear();
      _comments.clear();
    }

    try {
      final page = await twitchGqlApi.getVodCommentsByOffset(
        videoId: videoId,
        contentOffsetSeconds: contentOffsetSeconds,
      );
      _appendPage(page, requestedOffsetSeconds: contentOffsetSeconds);
      _hasLoadedReplay = true;
      _error = null;
    } catch (e) {
      _nextOffsetSeconds = null;
      _hasLoadedReplay = true;
      _error = 'Chat replay unavailable';
    } finally {
      _isLoading = false;
    }
  }

  void _appendPage(VodCommentPage page, {required int requestedOffsetSeconds}) {
    var addedCount = 0;

    for (final comment in page.comments) {
      if (!_seenCommentIds.add(comment.id)) continue;
      _comments.add(comment);
      addedCount++;
    }

    if (_comments.length > _commentLimit) {
      final removeCount = _comments.length - _commentLimit;
      final removed = _comments.take(removeCount).toList();
      _comments.removeRange(0, removeCount);
      for (final comment in removed) {
        _seenCommentIds.remove(comment.id);
      }
    }

    _comments.sort(
      (a, b) => a.contentOffsetSeconds.compareTo(b.contentOffsetSeconds),
    );

    if (!page.hasNextPage || page.comments.isEmpty) {
      _nextOffsetSeconds = null;
      return;
    }

    final maxOffsetSeconds = page.comments
        .map((comment) => comment.contentOffsetSeconds)
        .reduce((a, b) => a > b ? a : b);
    _nextOffsetSeconds =
        addedCount == 0 && maxOffsetSeconds <= requestedOffsetSeconds
        ? requestedOffsetSeconds + 1
        : maxOffsetSeconds;
  }
}
