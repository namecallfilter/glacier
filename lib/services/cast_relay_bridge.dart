import 'dart:io';

import 'package:flutter/services.dart';
import 'package:frosty/services/stream_proxy_config.dart';

/// The LAN address and port of the running cast relay server on the phone.
class CastRelayEndpoint {
  final String host;
  final int port;

  const CastRelayEndpoint({required this.host, required this.port});

  /// Builds an absolute URL a Cast device can use to reach the relay.
  String urlForPath(String path) => 'http://$host:$port$path';
}

/// A stream quality variant parsed from the channel's HLS master playlist.
class CastRelayVariant {
  final String name;
  final String? resolution;
  final int bandwidth;
  final double? frameRate;

  /// Relay path serving the full master playlist (adaptive quality).
  final String masterPath;

  /// Relay path serving only this variant's media playlist (fixed quality).
  final String mediaPath;

  const CastRelayVariant({
    required this.name,
    required this.resolution,
    required this.bandwidth,
    required this.frameRate,
    required this.masterPath,
    required this.mediaPath,
  });

  factory CastRelayVariant.fromMap(Map<Object?, Object?> map) {
    return CastRelayVariant(
      name: map['name'] as String,
      resolution: map['resolution'] as String?,
      bandwidth: (map['bandwidth'] as num?)?.toInt() ?? 0,
      frameRate: (map['frameRate'] as num?)?.toDouble(),
      masterPath: map['masterPath'] as String,
      mediaPath: map['mediaPath'] as String,
    );
  }
}

/// Bridge to the Android cast relay server, which serves HLS playlists and
/// segments to Cast devices through the same stream proxy core used for
/// WebView playback.
class CastRelayBridge {
  static const _channel = MethodChannel('frosty/cast_relay');

  bool get isSupported => Platform.isAndroid;

  /// Starts (or reuses) the relay server and returns its LAN endpoint.
  Future<CastRelayEndpoint> start(StreamProxyConfig config) async {
    final result = await _channel.invokeMapMethod<String, Object?>('start', {
      'config': config.toMethodChannelPayload(),
    });

    return CastRelayEndpoint(
      host: result!['host'] as String,
      port: (result['port'] as num).toInt(),
    );
  }

  Future<void> updateConfig(StreamProxyConfig config) async {
    await _channel.invokeMethod<void>('updateConfig', {
      'config': config.toMethodChannelPayload(),
    });
  }

  /// Fetches the master playlist at [usherUrl] through the relay's proxy core
  /// and returns the available quality variants.
  Future<List<CastRelayVariant>> resolveStreams(String usherUrl) async {
    final result = await _channel.invokeListMethod<Object?>('resolveStreams', {
      'url': usherUrl,
    });

    return result!
        .whereType<Map<Object?, Object?>>()
        .map(CastRelayVariant.fromMap)
        .toList();
  }

  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }
}
