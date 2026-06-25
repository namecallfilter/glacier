// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vod_player_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$VodPlayerStore on VodPlayerStoreBase, Store {
  late final _$_currentPositionAtom = Atom(
    name: 'VodPlayerStoreBase._currentPosition',
    context: context,
  );

  Duration get currentPosition {
    _$_currentPositionAtom.reportRead();
    return super._currentPosition;
  }

  @override
  Duration get _currentPosition => currentPosition;

  @override
  set _currentPosition(Duration value) {
    _$_currentPositionAtom.reportWrite(value, super._currentPosition, () {
      super._currentPosition = value;
    });
  }

  late final _$_durationAtom = Atom(
    name: 'VodPlayerStoreBase._duration',
    context: context,
  );

  Duration? get duration {
    _$_durationAtom.reportRead();
    return super._duration;
  }

  @override
  Duration? get _duration => duration;

  @override
  set _duration(Duration? value) {
    _$_durationAtom.reportWrite(value, super._duration, () {
      super._duration = value;
    });
  }

  late final _$_loadingAtom = Atom(
    name: 'VodPlayerStoreBase._loading',
    context: context,
  );

  bool get loading {
    _$_loadingAtom.reportRead();
    return super._loading;
  }

  @override
  bool get _loading => loading;

  @override
  set _loading(bool value) {
    _$_loadingAtom.reportWrite(value, super._loading, () {
      super._loading = value;
    });
  }

  late final _$_pausedAtom = Atom(
    name: 'VodPlayerStoreBase._paused',
    context: context,
  );

  bool get paused {
    _$_pausedAtom.reportRead();
    return super._paused;
  }

  @override
  bool get _paused => paused;

  @override
  set _paused(bool value) {
    _$_pausedAtom.reportWrite(value, super._paused, () {
      super._paused = value;
    });
  }

  late final _$_overlayVisibleAtom = Atom(
    name: 'VodPlayerStoreBase._overlayVisible',
    context: context,
  );

  bool get overlayVisible {
    _$_overlayVisibleAtom.reportRead();
    return super._overlayVisible;
  }

  @override
  bool get _overlayVisible => overlayVisible;

  @override
  set _overlayVisible(bool value) {
    _$_overlayVisibleAtom.reportWrite(value, super._overlayVisible, () {
      super._overlayVisible = value;
    });
  }

  late final _$_availableStreamQualitiesAtom = Atom(
    name: 'VodPlayerStoreBase._availableStreamQualities',
    context: context,
  );

  List<String> get availableStreamQualities {
    _$_availableStreamQualitiesAtom.reportRead();
    return super._availableStreamQualities;
  }

  @override
  List<String> get _availableStreamQualities => availableStreamQualities;

  @override
  set _availableStreamQualities(List<String> value) {
    _$_availableStreamQualitiesAtom.reportWrite(
      value,
      super._availableStreamQualities,
      () {
        super._availableStreamQualities = value;
      },
    );
  }

  late final _$_streamQualityIndexAtom = Atom(
    name: 'VodPlayerStoreBase._streamQualityIndex',
    context: context,
  );

  int get streamQualityIndex {
    _$_streamQualityIndexAtom.reportRead();
    return super._streamQualityIndex;
  }

  @override
  int get _streamQualityIndex => streamQualityIndex;

  @override
  set _streamQualityIndex(int value) {
    _$_streamQualityIndexAtom.reportWrite(value, super._streamQualityIndex, () {
      super._streamQualityIndex = value;
    });
  }

  late final _$updateStreamQualitiesAsyncAction = AsyncAction(
    'VodPlayerStoreBase.updateStreamQualities',
    context: context,
  );

  @override
  Future<void> updateStreamQualities() {
    return _$updateStreamQualitiesAsyncAction.run(
      () => super.updateStreamQualities(),
    );
  }

  late final _$setStreamQualityAsyncAction = AsyncAction(
    'VodPlayerStoreBase.setStreamQuality',
    context: context,
  );

  @override
  Future<void> setStreamQuality(String newStreamQuality) {
    return _$setStreamQualityAsyncAction.run(
      () => super.setStreamQuality(newStreamQuality),
    );
  }

  late final _$_setStreamQualityIndexAsyncAction = AsyncAction(
    'VodPlayerStoreBase._setStreamQualityIndex',
    context: context,
  );

  @override
  Future<void> _setStreamQualityIndex(int newStreamQualityIndex) {
    return _$_setStreamQualityIndexAsyncAction.run(
      () => super._setStreamQualityIndex(newStreamQualityIndex),
    );
  }

  late final _$handleRefreshAsyncAction = AsyncAction(
    'VodPlayerStoreBase.handleRefresh',
    context: context,
  );

  @override
  Future<void> handleRefresh() {
    return _$handleRefreshAsyncAction.run(() => super.handleRefresh());
  }

  late final _$VodPlayerStoreBaseActionController = ActionController(
    name: 'VodPlayerStoreBase',
    context: context,
  );

  @override
  void handleVideoTap() {
    final _$actionInfo = _$VodPlayerStoreBaseActionController.startAction(
      name: 'VodPlayerStoreBase.handleVideoTap',
    );
    try {
      return super.handleVideoTap();
    } finally {
      _$VodPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void handleToggleOverlay() {
    final _$actionInfo = _$VodPlayerStoreBaseActionController.startAction(
      name: 'VodPlayerStoreBase.handleToggleOverlay',
    );
    try {
      return super.handleToggleOverlay();
    } finally {
      _$VodPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''

    ''';
  }
}
