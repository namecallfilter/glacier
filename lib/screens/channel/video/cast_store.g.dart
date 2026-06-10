// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cast_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$CastStore on CastStoreBase, Store {
  late final _$_devicesAtom = Atom(
    name: 'CastStoreBase._devices',
    context: context,
  );

  ObservableList<CastDevice> get devices {
    _$_devicesAtom.reportRead();
    return super._devices;
  }

  @override
  ObservableList<CastDevice> get _devices => devices;

  @override
  set _devices(ObservableList<CastDevice> value) {
    _$_devicesAtom.reportWrite(value, super._devices, () {
      super._devices = value;
    });
  }

  late final _$_isSearchingAtom = Atom(
    name: 'CastStoreBase._isSearching',
    context: context,
  );

  bool get isSearching {
    _$_isSearchingAtom.reportRead();
    return super._isSearching;
  }

  @override
  bool get _isSearching => isSearching;

  @override
  set _isSearching(bool value) {
    _$_isSearchingAtom.reportWrite(value, super._isSearching, () {
      super._isSearching = value;
    });
  }

  late final _$_connectionStateAtom = Atom(
    name: 'CastStoreBase._connectionState',
    context: context,
  );

  CastConnectionState get connectionState {
    _$_connectionStateAtom.reportRead();
    return super._connectionState;
  }

  @override
  CastConnectionState get _connectionState => connectionState;

  @override
  set _connectionState(CastConnectionState value) {
    _$_connectionStateAtom.reportWrite(value, super._connectionState, () {
      super._connectionState = value;
    });
  }

  late final _$_connectedDeviceNameAtom = Atom(
    name: 'CastStoreBase._connectedDeviceName',
    context: context,
  );

  String? get connectedDeviceName {
    _$_connectedDeviceNameAtom.reportRead();
    return super._connectedDeviceName;
  }

  @override
  String? get _connectedDeviceName => connectedDeviceName;

  @override
  set _connectedDeviceName(String? value) {
    _$_connectedDeviceNameAtom.reportWrite(
      value,
      super._connectedDeviceName,
      () {
        super._connectedDeviceName = value;
      },
    );
  }

  late final _$_variantsAtom = Atom(
    name: 'CastStoreBase._variants',
    context: context,
  );

  ObservableList<CastRelayVariant> get variants {
    _$_variantsAtom.reportRead();
    return super._variants;
  }

  @override
  ObservableList<CastRelayVariant> get _variants => variants;

  @override
  set _variants(ObservableList<CastRelayVariant> value) {
    _$_variantsAtom.reportWrite(value, super._variants, () {
      super._variants = value;
    });
  }

  late final _$_selectedQualityAtom = Atom(
    name: 'CastStoreBase._selectedQuality',
    context: context,
  );

  String get selectedQuality {
    _$_selectedQualityAtom.reportRead();
    return super._selectedQuality;
  }

  @override
  String get _selectedQuality => selectedQuality;

  @override
  set _selectedQuality(String value) {
    _$_selectedQualityAtom.reportWrite(value, super._selectedQuality, () {
      super._selectedQuality = value;
    });
  }

  late final _$_errorAtom = Atom(
    name: 'CastStoreBase._error',
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

  late final _$searchDevicesAsyncAction = AsyncAction(
    'CastStoreBase.searchDevices',
    context: context,
  );

  @override
  Future<void> searchDevices() {
    return _$searchDevicesAsyncAction.run(() => super.searchDevices());
  }

  late final _$connectAsyncAction = AsyncAction(
    'CastStoreBase.connect',
    context: context,
  );

  @override
  Future<void> connect(CastDevice device) {
    return _$connectAsyncAction.run(() => super.connect(device));
  }

  late final _$_startCastingAsyncAction = AsyncAction(
    'CastStoreBase._startCasting',
    context: context,
  );

  @override
  Future<void> _startCasting() {
    return _$_startCastingAsyncAction.run(() => super._startCasting());
  }

  late final _$disconnectAsyncAction = AsyncAction(
    'CastStoreBase.disconnect',
    context: context,
  );

  @override
  Future<void> disconnect() {
    return _$disconnectAsyncAction.run(() => super.disconnect());
  }

  late final _$CastStoreBaseActionController = ActionController(
    name: 'CastStoreBase',
    context: context,
  );

  @override
  void setQuality(String quality) {
    final _$actionInfo = _$CastStoreBaseActionController.startAction(
      name: 'CastStoreBase.setQuality',
    );
    try {
      return super.setQuality(quality);
    } finally {
      _$CastStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void _handleSessionClosed() {
    final _$actionInfo = _$CastStoreBaseActionController.startAction(
      name: 'CastStoreBase._handleSessionClosed',
    );
    try {
      return super._handleSessionClosed();
    } finally {
      _$CastStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''

    ''';
  }
}
