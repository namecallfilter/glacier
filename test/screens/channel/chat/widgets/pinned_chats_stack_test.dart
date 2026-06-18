import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/models/badges.dart';
import 'package:frosty/models/pinned_chat.dart';
import 'package:frosty/screens/channel/chat/widgets/pinned_chats_stack.dart';
import 'package:frosty/theme.dart';
import 'package:frosty/widgets/frosty_cached_network_image.dart';

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

  testWidgets('uses chat background with border and shadow', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [_pin(id: 'pin-1', messageText: 'Pinned message')],
          launchExternal: false,
          onDismiss: (_) {},
          onDismissMany: (_) {},
        ),
      ),
    );

    final theme = Theme.of(tester.element(find.byType(PinnedChatsStack)));
    final cardMaterial = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(PinnedChatsStack),
            matching: find.byType(Material),
          ),
        )
        .firstWhere((material) => material.shape is RoundedRectangleBorder);
    final cardShape = cardMaterial.shape! as RoundedRectangleBorder;

    expect(cardMaterial.color, theme.scaffoldBackgroundColor);
    expect(cardMaterial.elevation, greaterThan(0));
    expect(cardMaterial.shadowColor, isNot(theme.scaffoldBackgroundColor));
    expect(cardShape.side.width, greaterThan(0));
    expect(cardShape.side.color, isNot(theme.scaffoldBackgroundColor));
  });

  testWidgets('renders pinned chat Twitch emotes and badges', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText: '50% off all subs! Kappa',
              pinnedByBadges: [
                const PinnedChatBadge(
                  setId: 'moderator',
                  version: '1',
                  title: 'Moderator',
                ),
              ],
              senderBadges: [
                const PinnedChatBadge(
                  setId: 'subscriber',
                  version: '12',
                  title: '12-Month Subscriber',
                  imageUrl: 'https://static.example/sub-4x.png',
                ),
              ],
              fragments: [
                const PinnedChatFragment(text: '50% off all subs! '),
                const PinnedChatFragment(
                  text: 'Kappa',
                  emote: PinnedChatEmote(id: '25', text: 'Kappa'),
                ),
              ],
            ),
          ],
          twitchBadges: const {
            'moderator/1': ChatBadge(
              name: 'Moderator',
              url: 'https://static.example/mod-4x.png',
              type: BadgeType.twitch,
            ),
          },
          launchExternal: false,
          onDismiss: (_) {},
          onDismissMany: (_) {},
        ),
      ),
    );

    expect(_findImage('https://static.example/mod-4x.png'), findsOneWidget);
    expect(_findImage('https://static.example/sub-4x.png'), findsOneWidget);
    expect(
      _findImage(
        'https://static-cdn.jtvnw.net/emoticons/v2/25/default/dark/3.0',
      ),
      findsOneWidget,
    );
  });

  testWidgets('opens emote details from pinned chat emotes', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText: 'Kappa',
              fragments: const [
                PinnedChatFragment(
                  text: 'Kappa',
                  emote: PinnedChatEmote(id: '25', text: 'Kappa'),
                ),
              ],
            ),
          ],
          launchExternal: false,
          onDismiss: (_) {},
          onDismissMany: (_) {},
        ),
      ),
    );

    await tester.tap(
      find
          .ancestor(
            of: _findImage(
              'https://static-cdn.jtvnw.net/emoticons/v2/25/default/dark/3.0',
            ),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Kappa'), findsWidgets);
    expect(find.text('Twitch sub emote'), findsOneWidget);
    expect(find.text('Copy name'), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);
  });

  testWidgets('breaks leading link fragments when expanded', (tester) async {
    const message =
        'PartyPopper 50% off on all subs! https://www.twitch.tv/subs/marlon';

    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText: message,
              fragments: const [
                PinnedChatFragment(text: 'PartyPopper 50% off on all subs! '),
                PinnedChatFragment(text: 'https://www.twitch.tv/subs/marlon'),
              ],
            ),
          ],
          launchExternal: false,
          onDismiss: (_) {},
          onDismissMany: (_) {},
        ),
      ),
    );

    expect(
      _findRichTextContaining('PartyPopper').text.toPlainText(),
      contains('subs!\nhttps://'),
    );
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

PinnedChatMessage _pin({
  required String id,
  required String messageText,
  List<PinnedChatFragment> fragments = const [],
  List<PinnedChatBadge> senderBadges = const [],
  List<PinnedChatBadge> pinnedByBadges = const [],
}) => PinnedChatMessage(
  id: id,
  messageId: 'message-$id',
  messageText: messageText,
  senderDisplayName: 'SenderName',
  pinnedByDisplayName: 'ModName',
  sentAt: DateTime.parse('2026-06-18T09:40:00Z'),
  fragments: fragments,
  senderBadges: senderBadges,
  pinnedByBadges: pinnedByBadges,
);

Finder _findImage(String imageUrl) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is FrostyCachedNetworkImage && widget.imageUrl == imageUrl,
  );
}

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
