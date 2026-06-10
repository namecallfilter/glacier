import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/services/cast_relay_bridge.dart';
import 'package:frosty/services/stream_proxy_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('frosty/cast_relay');
  final calls = <MethodCall>[];

  const config = StreamProxyConfig(
    mode: StreamProxyMode.ttvLolPro,
    currentChannelLogin: 'SomeChannel',
    proxyUrls: ['http://proxy.example.com:8080'],
    whitelistedChannels: ['other_channel'],
    debugLogging: false,
  );

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'start':
              return {'host': '192.168.1.10', 'port': 40123};
            case 'resolveStreams':
              return [
                {
                  'name': '1080p60 (source)',
                  'resolution': '1920x1080',
                  'bandwidth': 6000000,
                  'frameRate': 60.0,
                  'masterPath': '/master.m3u8?src=bWFzdGVy',
                  'mediaPath': '/media.m3u8?src=c291cmNl',
                },
                {
                  'name': '720p60',
                  'resolution': '1280x720',
                  'bandwidth': 3000000,
                  'frameRate': null,
                  'masterPath': '/master.m3u8?src=bWFzdGVy',
                  'mediaPath': '/media.m3u8?src=NzIwcDYw',
                },
              ];
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('CastRelayBridge', () {
    test(
      'start sends the stream proxy config and returns the endpoint',
      () async {
        final endpoint = await CastRelayBridge().start(config);

        expect(endpoint.host, '192.168.1.10');
        expect(endpoint.port, 40123);
        expect(calls.single.method, 'start');

        final arguments = calls.single.arguments as Map;
        expect(arguments['config'], config.toMethodChannelPayload());
      },
    );

    test('updateConfig forwards the stream proxy config', () async {
      await CastRelayBridge().updateConfig(config);

      expect(calls.single.method, 'updateConfig');
      final arguments = calls.single.arguments as Map;
      expect(arguments['config'], config.toMethodChannelPayload());
    });

    test('resolveStreams parses quality variants', () async {
      final variants = await CastRelayBridge().resolveStreams(
        'https://usher.ttvnw.net/api/channel/hls/somechannel.m3u8',
      );

      expect(calls.single.method, 'resolveStreams');
      expect(variants, hasLength(2));
      expect(variants[0].name, '1080p60 (source)');
      expect(variants[0].resolution, '1920x1080');
      expect(variants[0].bandwidth, 6000000);
      expect(variants[0].frameRate, 60.0);
      expect(variants[1].frameRate, isNull);
      expect(variants[1].mediaPath, '/media.m3u8?src=NzIwcDYw');
    });

    test('endpoint builds absolute relay URLs', () {
      const endpoint = CastRelayEndpoint(host: '192.168.1.10', port: 40123);

      expect(
        endpoint.urlForPath('/master.m3u8?src=abc'),
        'http://192.168.1.10:40123/master.m3u8?src=abc',
      );
    });
  });
}
