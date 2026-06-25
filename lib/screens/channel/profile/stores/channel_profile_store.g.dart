// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'channel_profile_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ChannelProfileStore on ChannelProfileStoreBase, Store {
  Computed<bool>? _$isLiveComputed;

  @override
  bool get isLive => (_$isLiveComputed ??= Computed<bool>(
    () => super.isLive,
    name: 'ChannelProfileStoreBase.isLive',
  )).value;
  Computed<bool>? _$hasMoreVideosComputed;

  @override
  bool get hasMoreVideos => (_$hasMoreVideosComputed ??= Computed<bool>(
    () => super.hasMoreVideos,
    name: 'ChannelProfileStoreBase.hasMoreVideos',
  )).value;
  Computed<String>? _$primaryActionLabelComputed;

  @override
  String get primaryActionLabel =>
      (_$primaryActionLabelComputed ??= Computed<String>(
        () => super.primaryActionLabel,
        name: 'ChannelProfileStoreBase.primaryActionLabel',
      )).value;

  late final _$_userAtom = Atom(
    name: 'ChannelProfileStoreBase._user',
    context: context,
  );

  UserTwitch? get user {
    _$_userAtom.reportRead();
    return super._user;
  }

  @override
  UserTwitch? get _user => user;

  @override
  set _user(UserTwitch? value) {
    _$_userAtom.reportWrite(value, super._user, () {
      super._user = value;
    });
  }

  late final _$_channelInfoAtom = Atom(
    name: 'ChannelProfileStoreBase._channelInfo',
    context: context,
  );

  Channel? get channelInfo {
    _$_channelInfoAtom.reportRead();
    return super._channelInfo;
  }

  @override
  Channel? get _channelInfo => channelInfo;

  @override
  set _channelInfo(Channel? value) {
    _$_channelInfoAtom.reportWrite(value, super._channelInfo, () {
      super._channelInfo = value;
    });
  }

  late final _$_streamInfoAtom = Atom(
    name: 'ChannelProfileStoreBase._streamInfo',
    context: context,
  );

  StreamTwitch? get streamInfo {
    _$_streamInfoAtom.reportRead();
    return super._streamInfo;
  }

  @override
  StreamTwitch? get _streamInfo => streamInfo;

  @override
  set _streamInfo(StreamTwitch? value) {
    _$_streamInfoAtom.reportWrite(value, super._streamInfo, () {
      super._streamInfo = value;
    });
  }

  late final _$_videosAtom = Atom(
    name: 'ChannelProfileStoreBase._videos',
    context: context,
  );

  ObservableList<TwitchVideo> get videos {
    _$_videosAtom.reportRead();
    return super._videos;
  }

  @override
  ObservableList<TwitchVideo> get _videos => videos;

  @override
  set _videos(ObservableList<TwitchVideo> value) {
    _$_videosAtom.reportWrite(value, super._videos, () {
      super._videos = value;
    });
  }

  late final _$_isLoadingAtom = Atom(
    name: 'ChannelProfileStoreBase._isLoading',
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

  late final _$_isVideosLoadingAtom = Atom(
    name: 'ChannelProfileStoreBase._isVideosLoading',
    context: context,
  );

  bool get isVideosLoading {
    _$_isVideosLoadingAtom.reportRead();
    return super._isVideosLoading;
  }

  @override
  bool get _isVideosLoading => isVideosLoading;

  @override
  set _isVideosLoading(bool value) {
    _$_isVideosLoadingAtom.reportWrite(value, super._isVideosLoading, () {
      super._isVideosLoading = value;
    });
  }

  late final _$_errorAtom = Atom(
    name: 'ChannelProfileStoreBase._error',
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

  late final _$selectedVideoTypeAtom = Atom(
    name: 'ChannelProfileStoreBase.selectedVideoType',
    context: context,
  );

  @override
  TwitchVideoType get selectedVideoType {
    _$selectedVideoTypeAtom.reportRead();
    return super.selectedVideoType;
  }

  @override
  set selectedVideoType(TwitchVideoType value) {
    _$selectedVideoTypeAtom.reportWrite(value, super.selectedVideoType, () {
      super.selectedVideoType = value;
    });
  }

  late final _$initAsyncAction = AsyncAction(
    'ChannelProfileStoreBase.init',
    context: context,
  );

  @override
  Future<void> init() {
    return _$initAsyncAction.run(() => super.init());
  }

  late final _$refreshAsyncAction = AsyncAction(
    'ChannelProfileStoreBase.refresh',
    context: context,
  );

  @override
  Future<void> refresh() {
    return _$refreshAsyncAction.run(() => super.refresh());
  }

  late final _$selectVideoTypeAsyncAction = AsyncAction(
    'ChannelProfileStoreBase.selectVideoType',
    context: context,
  );

  @override
  Future<void> selectVideoType(TwitchVideoType type) {
    return _$selectVideoTypeAsyncAction.run(() => super.selectVideoType(type));
  }

  late final _$loadMoreVideosAsyncAction = AsyncAction(
    'ChannelProfileStoreBase.loadMoreVideos',
    context: context,
  );

  @override
  Future<void> loadMoreVideos() {
    return _$loadMoreVideosAsyncAction.run(() => super.loadMoreVideos());
  }

  @override
  String toString() {
    return '''
selectedVideoType: ${selectedVideoType},
isLive: ${isLive},
hasMoreVideos: ${hasMoreVideos},
primaryActionLabel: ${primaryActionLabel}
    ''';
  }
}
