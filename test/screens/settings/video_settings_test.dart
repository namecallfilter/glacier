import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/screens/settings/video_settings.dart';

void main() {
  testWidgets('shows Casting section and persists selected cast mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settingsStore = SettingsStore.fromJson({});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VideoSettings(settingsStore: settingsStore)),
      ),
    );

    for (var index = 0; index < 3; index += 1) {
      await tester.drag(find.byType(Scrollable), const Offset(0, -600));
      await tester.pump();
      if (find.text('CASTING').evaluate().isNotEmpty) break;
    }

    expect(find.text('CASTING'), findsOneWidget);
    expect(find.text('Cast Mode'), findsOneWidget);
    expect(find.text('Stable HLS'), findsOneWidget);
    expect(find.text('Low Latency'), findsOneWidget);
    expect(
      find.text('Most reliable. Higher latency, lowest chance of buffering.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'WebRTC-based. Runs a local gateway on this phone for lower latency. Uses significantly more battery and may make the phone warm. Keep your phone plugged in for long casts.',
      ),
      findsOneWidget,
    );
    expect(find.text('WebRTC Gateway URL'), findsNothing);
    expect(find.text('Auto fallback to Stable HLS'), findsNothing);
    expect(settingsStore.castMode, CastMode.stableHls);

    await tester.tap(find.text('Low Latency'));
    await tester.pump();

    expect(settingsStore.castMode, CastMode.lowLatency);
    expect(find.text('WebRTC Gateway URL'), findsNothing);

    for (var index = 0; index < 3; index += 1) {
      await tester.drag(find.byType(Scrollable), const Offset(0, -600));
      await tester.pump();
      if (find.text('ADVANCED / DEBUG').evaluate().isNotEmpty) break;
    }

    expect(find.text('ADVANCED / DEBUG'), findsOneWidget);
    expect(find.text('External WebRTC Gateway URL override'), findsOneWidget);
    expect(find.text('WHEP URL override'), findsOneWidget);
    expect(find.text('Auto fallback to Stable HLS'), findsOneWidget);
  });
}
