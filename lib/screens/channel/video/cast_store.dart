import 'dart:async';
import 'dart:io';

import 'package:cast/cast.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/services/cast_relay_bridge.dart';
import 'package:frosty/services/stream_proxy_config.dart';
import 'package:mobx/mobx.dart';

part 'cast_store.g.dart';

class CastStore = CastStoreBase with _$CastStore;

enum CastConnectionState { disconnected, connecting, connected }

/// The quality label used for adaptive (master playlist) playback.
const kCastAutoQuality = 'Auto';

abstract class CastStoreBase with Store {
  final TwitchApi twitchApi;

  /// The user login of the channel to cast.
  final String userLogin;

  /// The display title used in the Cast media metadata.
  final String displayName;

  final SettingsStore settingsStore;

  final CastRelayBridge _relayBridge = CastRelayBridge();

  CastSession? _session;
  StreamSubscription<CastSessionState>? _sessionStateSubscription;
  CastRelayEndpoint? _relayEndpoint;
  var _mediaRequestId = 0;

  @readonly
  var _devices = ObservableList<CastDevice>();

  @readonly
  var _isSearching = false;

  @readonly
  var _connectionState = CastConnectionState.disconnected;

  @readonly
  String? _connectedDeviceName;

  @readonly
  var _variants = ObservableList<CastRelayVariant>();

  @readonly
  var _selectedQuality = kCastAutoQuality;

  @readonly
  String? _error;

  CastStoreBase({
    required this.twitchApi,
    required this.userLogin,
    required this.displayName,
    required this.settingsStore,
  });

  bool get isSupported => Platform.isAndroid;

  /// The quality options to present, with adaptive playback first.
  List<String> get qualityOptions => [
    kCastAutoQuality,
    ..._variants.map((variant) => variant.name),
  ];

  StreamProxyConfig get _streamProxyConfig => StreamProxyConfig.fromSettings(
    settingsStore: settingsStore,
    currentChannelLogin: userLogin,
  );

  @action
  Future<void> searchDevices() async {
    if (_isSearching) return;

    _isSearching = true;
    _error = null;
    try {
      final devices = await CastDiscoveryService().search();
      _devices = ObservableList.of(devices);
    } catch (e) {
      debugPrint('Cast discovery failed: $e');
      _error = 'Device discovery failed';
    } finally {
      runInAction(() => _isSearching = false);
    }
  }

  @action
  Future<void> connect(CastDevice device) async {
    if (_connectionState != CastConnectionState.disconnected) {
      await disconnect();
    }

    _connectionState = CastConnectionState.connecting;
    _connectedDeviceName = device.name;
    _error = null;

    try {
      final session = await CastSessionManager().startSession(device);
      _session = session;

      _sessionStateSubscription = session.stateStream.listen((state) {
        if (state == CastSessionState.connected) {
          unawaited(_startCasting());
        } else if (state == CastSessionState.closed) {
          _handleSessionClosed();
        }
      });

      // Launch the default media receiver; media is loaded once the session
      // reports connected.
      session.sendMessage(CastSession.kNamespaceReceiver, {
        'type': 'LAUNCH',
        'appId': 'CC1AD845',
      });
    } catch (e) {
      debugPrint('Cast connect failed: $e');
      await disconnect();
      runInAction(() => _error = 'Failed to connect to ${device.name}');
    }
  }

  /// Starts the relay server, resolves the channel's stream variants, and
  /// loads media on the connected Cast device.
  @action
  Future<void> _startCasting() async {
    try {
      _relayEndpoint = await _relayBridge.start(_streamProxyConfig);

      final usherUrl = await twitchApi.getStreamPlaybackUrl(
        userLogin: userLogin,
      );
      final variants = await _relayBridge.resolveStreams(usherUrl);

      runInAction(() {
        _variants = ObservableList.of(variants);
        _selectedQuality = kCastAutoQuality;
        _connectionState = CastConnectionState.connected;
      });

      _loadMedia();
    } catch (e) {
      debugPrint('Cast start failed: $e');
      await disconnect();
      runInAction(() => _error = 'Failed to start casting');
    }
  }

  @action
  void setQuality(String quality) {
    if (_connectionState != CastConnectionState.connected) return;
    if (quality != kCastAutoQuality &&
        !_variants.any((variant) => variant.name == quality)) {
      return;
    }

    _selectedQuality = quality;
    _loadMedia();
  }

  void _loadMedia() {
    final session = _session;
    final endpoint = _relayEndpoint;
    if (session == null || endpoint == null || _variants.isEmpty) return;

    final variant = _variants.firstWhereOrNull(
      (variant) => variant.name == _selectedQuality,
    );
    final path = variant?.mediaPath ?? _variants.first.masterPath;

    session.sendMessage(CastSession.kNamespaceMedia, {
      'type': 'LOAD',
      'requestId': ++_mediaRequestId,
      'autoplay': true,
      'media': {
        'contentId': endpoint.urlForPath(path),
        'contentType': 'application/vnd.apple.mpegurl',
        'streamType': 'LIVE',
        'metadata': {
          'metadataType': 0,
          'title': displayName.isNotEmpty ? displayName : userLogin,
        },
      },
    });
  }

  /// Pushes updated stream proxy settings to a running relay server.
  Future<void> updateStreamProxyConfig() async {
    if (_connectionState == CastConnectionState.disconnected) return;

    try {
      await _relayBridge.updateConfig(_streamProxyConfig);
    } catch (e) {
      debugPrint('Cast relay config update failed: $e');
    }
  }

  @action
  Future<void> disconnect() async {
    final session = _session;
    _session = null;
    await _sessionStateSubscription?.cancel();
    _sessionStateSubscription = null;

    if (session != null) {
      try {
        await CastSessionManager().endSession(session.sessionId);
      } catch (e) {
        debugPrint('Cast session close failed: $e');
      }
    }

    try {
      await _relayBridge.stop();
    } catch (e) {
      debugPrint('Cast relay stop failed: $e');
    }

    _relayEndpoint = null;
    _connectionState = CastConnectionState.disconnected;
    _connectedDeviceName = null;
    _variants = ObservableList();
    _selectedQuality = kCastAutoQuality;
  }

  @action
  void _handleSessionClosed() {
    _session = null;
    _sessionStateSubscription?.cancel();
    _sessionStateSubscription = null;
    _relayEndpoint = null;
    _connectionState = CastConnectionState.disconnected;
    _connectedDeviceName = null;
    _variants = ObservableList();
    _selectedQuality = kCastAutoQuality;
    unawaited(
      _relayBridge.stop().catchError((Object e) {
        debugPrint('Cast relay stop failed: $e');
      }),
    );
  }

  void dispose() {
    unawaited(disconnect());
  }
}
