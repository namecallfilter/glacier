// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vod_chat_replay_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$VodChatReplayStore on VodChatReplayStoreBase, Store {
  Computed<bool>? _$hasMoreCommentsComputed;

  @override
  bool get hasMoreComments => (_$hasMoreCommentsComputed ??= Computed<bool>(
    () => super.hasMoreComments,
    name: 'VodChatReplayStoreBase.hasMoreComments',
  )).value;

  late final _$_commentsAtom = Atom(
    name: 'VodChatReplayStoreBase._comments',
    context: context,
  );

  ObservableList<VodComment> get comments {
    _$_commentsAtom.reportRead();
    return super._comments;
  }

  @override
  ObservableList<VodComment> get _comments => comments;

  @override
  set _comments(ObservableList<VodComment> value) {
    _$_commentsAtom.reportWrite(value, super._comments, () {
      super._comments = value;
    });
  }

  late final _$_isLoadingAtom = Atom(
    name: 'VodChatReplayStoreBase._isLoading',
    context: context,
  );

  bool get isLoading {
    _$_isLoadingAtom.reportRead();
    return super._isLoading;
  }

  @override
  bool get _isLoading => isLoading;

  @override
  set _isLoading(bool value) {
    _$_isLoadingAtom.reportWrite(value, super._isLoading, () {
      super._isLoading = value;
    });
  }

  late final _$_errorAtom = Atom(
    name: 'VodChatReplayStoreBase._error',
    context: context,
  );

  String? get error {
    _$_errorAtom.reportRead();
    return super._error;
  }

  @override
  String? get _error => error;

  @override
  set _error(String? value) {
    _$_errorAtom.reportWrite(value, super._error, () {
      super._error = value;
    });
  }

  late final _$_hasLoadedReplayAtom = Atom(
    name: 'VodChatReplayStoreBase._hasLoadedReplay',
    context: context,
  );

  bool get hasLoadedReplay {
    _$_hasLoadedReplayAtom.reportRead();
    return super._hasLoadedReplay;
  }

  @override
  bool get _hasLoadedReplay => hasLoadedReplay;

  @override
  set _hasLoadedReplay(bool value) {
    _$_hasLoadedReplayAtom.reportWrite(value, super._hasLoadedReplay, () {
      super._hasLoadedReplay = value;
    });
  }

  late final _$loadAtAsyncAction = AsyncAction(
    'VodChatReplayStoreBase.loadAt',
    context: context,
  );

  @override
  Future<void> loadAt(Duration position) {
    return _$loadAtAsyncAction.run(() => super.loadAt(position));
  }

  late final _$handleSeekAsyncAction = AsyncAction(
    'VodChatReplayStoreBase.handleSeek',
    context: context,
  );

  @override
  Future<void> handleSeek(Duration position) {
    return _$handleSeekAsyncAction.run(() => super.handleSeek(position));
  }

  late final _$loadNextPageAsyncAction = AsyncAction(
    'VodChatReplayStoreBase.loadNextPage',
    context: context,
  );

  @override
  Future<void> loadNextPage() {
    return _$loadNextPageAsyncAction.run(() => super.loadNextPage());
  }

  @override
  String toString() {
    return '''
hasMoreComments: ${hasMoreComments}
    ''';
  }
}
