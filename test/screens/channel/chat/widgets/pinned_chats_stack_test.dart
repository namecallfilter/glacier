import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/models/pinned_chat.dart';
import 'package:frosty/screens/channel/chat/widgets/pinned_chats_stack.dart';
import 'package:frosty/theme.dart';

void main() {
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  MethodCall? urlLauncherCall;

  setUp(() {
    urlLauncherCall = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async {
          if (call.method == 'launch') {
            urlLauncherCall = call;
            return true;
          }
          return false;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, null);
  });

  testWidgets('shows collapsed pinned chat stack with count', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(id: 'pin-1', messageText: 'First pinned message'),
            _pin(id: 'pin-2', messageText: 'Second pinned message'),
          ],
          launchExternal: false,
          onDismiss: (_) {},
          onDismissMany: (_) {},
        ),
      ),
    );

    expect(find.text('Pinned by ModName'), findsOneWidget);
    expect(find.text('First pinned message'), findsOneWidget);
    expect(find.text('2 pinned'), findsOneWidget);
  });

  testWidgets('opens sheet and dismisses selected pins', (tester) async {
    final dismissedIds = <String>[];

    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(id: 'pin-1', messageText: 'First pinned message'),
            _pin(id: 'pin-2', messageText: 'Second pinned message'),
          ],
          launchExternal: false,
          onDismiss: (_) {},
          onDismissMany: dismissedIds.addAll,
        ),
      ),
    );

    await tester.tap(find.text('First pinned message'));
    await tester.pumpAndSettle();

    expect(find.text('Pinned chats'), findsOneWidget);
    expect(find.text('Dismiss selected'), findsOneWidget);
    expect(find.text('Dismiss all'), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss selected'));
    await tester.pumpAndSettle();

    expect(dismissedIds, ['pin-1', 'pin-2']);
  });

  testWidgets('styles and launches links in pinned chat text', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(id: 'pin-1', messageText: 'Join discord.gg/Rtf6DuQAag now'),
          ],
          launchExternal: false,
          onDismiss: (_) {},
          onDismissMany: (_) {},
        ),
      ),
    );

    final theme = Theme.of(tester.element(find.byType(PinnedChatsStack)));
    final linkSpan = _findTextSpan('discord.gg/Rtf6DuQAag');

    expect(linkSpan.style?.color, theme.colorScheme.primary);
    expect(linkSpan.style?.decoration, TextDecoration.underline);
    expect(linkSpan.style?.decorationColor, theme.colorScheme.primary);
    expect(linkSpan.recognizer, isA<TapGestureRecognizer>());

    (linkSpan.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();

    final launchArguments = urlLauncherCall!.arguments as Map<Object?, Object?>;
    expect(launchArguments['url'], 'https://discord.gg/Rtf6DuQAag');
    expect(launchArguments['useWebView'], isTrue);
  });

  testWidgets('styles https scheme as part of pinned chat links', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText:
                  'PartyPopper 50% off on all subs! https://www.twitch.tv/subs/marlon',
            ),
          ],
          launchExternal: false,
          onDismiss: (_) {},
          onDismissMany: (_) {},
        ),
      ),
    );

    final theme = Theme.of(tester.element(find.byType(PinnedChatsStack)));
    final linkSpan = _findTextSpan('https://www.twitch.tv/subs/marlon');

    expect(linkSpan.style?.color, theme.colorScheme.primary);
    expect(linkSpan.style?.decoration, TextDecoration.underline);

    (linkSpan.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();

    final launchArguments = urlLauncherCall!.arguments as Map<Object?, Object?>;
    expect(launchArguments['url'], 'https://www.twitch.tv/subs/marlon');
  });

  testWidgets('starts link pins expanded and toggles them minimized', (
    tester,
  ) async {
    const longMessage =
        'PartyPopper 50% off on all subs! https://www.twitch.tv/subs/marlon';

    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [_pin(id: 'pin-1', messageText: longMessage)],
          launchExternal: false,
          onDismiss: (_) {},
          onDismissMany: (_) {},
        ),
      ),
    );

    expect(find.byTooltip('Collapse pinned chat'), findsOneWidget);

    final previewRichText = _findRichTextContaining('PartyPopper');
    expect(previewRichText.maxLines, greaterThan(1));
    expect(previewRichText.text.toPlainText(), contains('subs!\nhttps://'));

    await tester.tap(find.byTooltip('Collapse pinned chat'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand pinned chat'), findsOneWidget);
    expect(_findRichTextContaining('PartyPopper').maxLines, 1);

    await tester.tap(find.byTooltip('Expand pinned chat'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Collapse pinned chat'), findsOneWidget);
    expect(_findRichTextContaining('PartyPopper').maxLines, greaterThan(1));
  });

  testWidgets('starts very long pinned chats minimized', (tester) async {
    const longMessage =
        'M3 LINKS -> Discord: discord.gg/mar3lg | X: x.com/communities/1926380245063520455 | Snapchat: https://www.snapchat.com/add/marlonluga | YouTube: youtube.com/@mar3lg';

    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [_pin(id: 'pin-1', messageText: longMessage)],
          launchExternal: false,
          onDismiss: (_) {},
          onDismissMany: (_) {},
        ),
      ),
    );

    expect(find.byTooltip('Expand pinned chat'), findsOneWidget);
    expect(_findRichTextContaining('M3 LINKS').maxLines, 1);

    await tester.tap(find.byTooltip('Expand pinned chat'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Collapse pinned chat'), findsOneWidget);
    expect(_findRichTextContaining('M3 LINKS').maxLines, greaterThan(1));
  });
}

class _TestApp extends StatelessWidget {
  final Widget child;

  const _TestApp({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: const FrostyThemes(colorSchemeSeed: Color(0xFF9146FF)).dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 360, child: child),
        ),
      ),
    );
  }
}

PinnedChatMessage _pin({required String id, required String messageText}) =>
    PinnedChatMessage(
      id: id,
      messageId: 'message-$id',
      messageText: messageText,
      senderDisplayName: 'SenderName',
      pinnedByDisplayName: 'ModName',
      sentAt: DateTime.parse('2026-06-18T09:40:00Z'),
    );

TextSpan _findTextSpan(String text) {
  for (final richText in find.byType(RichText).evaluate()) {
    final widget = richText.widget as RichText;
    final span = _findTextSpanIn(widget.text, text);
    if (span != null) return span;
  }

  throw StateError('No TextSpan found for "$text"');
}

TextSpan? _findTextSpanIn(InlineSpan span, String text) {
  if (span is TextSpan) {
    if (span.text == text) return span;

    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = _findTextSpanIn(child, text);
      if (found != null) return found;
    }
  }

  return null;
}

RichText _findRichTextContaining(String text) {
  for (final richText in find.byType(RichText).evaluate()) {
    final widget = richText.widget as RichText;
    if (widget.text.toPlainText().contains(text)) return widget;
  }

  throw StateError('No RichText found containing "$text"');
}
