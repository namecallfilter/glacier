import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/models/badges.dart';
import 'package:frosty/models/emotes.dart';
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

  test('keeps pinned chat close to the top of the chat area', () {
    expect(PinnedChatsStack.topOffset, 5);
  });

  testWidgets(
    'shows only the current pinned chat without multi-pin affordance',
    (tester) async {
      await tester.pumpWidget(
        _TestApp(
          child: PinnedChatsStack(
            pinnedChats: [
              _pin(id: 'pin-1', messageText: 'First pinned message'),
              _pin(id: 'pin-2', messageText: 'Second pinned message'),
            ],
            launchExternal: false,
            onDismiss: (_) {},
          ),
        ),
      );

      expect(find.text('Pinned by ModName'), findsOneWidget);
      expect(find.text('First pinned message'), findsOneWidget);
      expect(find.text('Second pinned message'), findsNothing);
      expect(find.text('2 pinned'), findsNothing);
      expect(find.byTooltip('Open pinned chats'), findsNothing);
    },
  );

  testWidgets('tapping pinned chat card does not open a pinned chat list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [_pin(id: 'pin-1', messageText: 'First pinned message')],
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('First pinned message'));
    await tester.pumpAndSettle();

    expect(find.text('Pinned chats'), findsNothing);
    expect(find.text('Dismiss selected'), findsNothing);
    expect(find.text('Dismiss all'), findsNothing);
  });

  testWidgets('all pinned chats can be minimized', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [_pin(id: 'pin-1', messageText: 'Short pinned message')],
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    expect(find.byTooltip('Collapse pinned chat'), findsOneWidget);
    expect(find.byTooltip('Expand pinned chat'), findsNothing);
    expect(find.textContaining('SenderName'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse pinned chat'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand pinned chat'), findsOneWidget);
    expect(find.byTooltip('Collapse pinned chat'), findsNothing);
    expect(_findRichTextContaining('Short pinned message').maxLines, 1);
    expect(find.textContaining('SenderName'), findsNothing);

    await tester.tap(find.byTooltip('Expand pinned chat'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Collapse pinned chat'), findsOneWidget);
    expect(find.textContaining('SenderName'), findsOneWidget);
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

  testWidgets('filters pinned-by badges but keeps all sender badges', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText: 'Pinned message',
              pinnedByBadges: const [
                PinnedChatBadge(
                  setId: 'moderator',
                  version: '1',
                  title: 'Moderator',
                  imageUrl: 'https://static.example/pinner-mod.png',
                ),
                PinnedChatBadge(
                  setId: 'head-moderator',
                  version: '1',
                  title: 'Head Mod',
                  imageUrl: 'https://static.example/pinner-head-mod.png',
                ),
                PinnedChatBadge(
                  setId: 'broadcaster',
                  version: '1',
                  title: 'Broadcaster',
                  imageUrl: 'https://static.example/pinner-broadcaster.png',
                ),
                PinnedChatBadge(
                  setId: 'subscriber',
                  version: '12',
                  title: '12-Month Subscriber',
                  imageUrl: 'https://static.example/pinner-sub.png',
                ),
              ],
              senderBadges: const [
                PinnedChatBadge(
                  setId: 'subscriber',
                  version: '12',
                  title: '12-Month Subscriber',
                  imageUrl: 'https://static.example/sender-sub.png',
                ),
                PinnedChatBadge(
                  setId: 'vip',
                  version: '1',
                  title: 'VIP',
                  imageUrl: 'https://static.example/sender-vip.png',
                ),
                PinnedChatBadge(
                  setId: 'bits',
                  version: '1000',
                  title: 'Cheer 1K',
                  imageUrl: 'https://static.example/sender-bits.png',
                ),
              ],
            ),
          ],
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    expect(_findImage('https://static.example/pinner-mod.png'), findsOneWidget);
    expect(
      _findImage('https://static.example/pinner-head-mod.png'),
      findsOneWidget,
    );
    expect(
      _findImage('https://static.example/pinner-broadcaster.png'),
      findsOneWidget,
    );
    expect(_findImage('https://static.example/pinner-sub.png'), findsNothing);
    expect(_findImage('https://static.example/sender-sub.png'), findsOneWidget);
    expect(_findImage('https://static.example/sender-vip.png'), findsOneWidget);
    expect(
      _findImage('https://static.example/sender-bits.png'),
      findsOneWidget,
    );
  });

  testWidgets('opens badge details from pinned chat badges', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText: 'Pinned message',
              senderBadges: const [
                PinnedChatBadge(
                  setId: 'subscriber',
                  version: '12',
                  title: '12-Month Subscriber',
                  imageUrl: 'https://static.example/sender-sub.png',
                ),
              ],
            ),
          ],
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    await tester.tap(
      find
          .ancestor(
            of: _findImage('https://static.example/sender-sub.png'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('12-Month Subscriber'), findsOneWidget);
    expect(find.text('Twitch badge'), findsOneWidget);
    expect(find.text('Copy image URL'), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);
    expect(find.text('Copy name'), findsNothing);
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
          emoteToObject: const {
            'Kappa': Emote(
              name: 'Kappa',
              zeroWidth: false,
              url: 'https://static.example/kappa-global.png',
              type: EmoteType.twitchGlobal,
            ),
          },
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    await tester.tap(
      find
          .ancestor(
            of: _findImage('https://static.example/kappa-global.png'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Kappa'), findsWidgets);
    expect(find.text('Twitch global emote'), findsOneWidget);
    expect(find.text('Twitch sub emote'), findsNothing);
    expect(find.text('Copy name'), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);
  });

  testWidgets('renders chat asset emotes in pinned chat text', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText: 'hello peepoHey chat',
              fragments: const [
                PinnedChatFragment(text: 'hello peepoHey chat'),
              ],
            ),
          ],
          emoteToObject: const {
            'peepoHey': Emote(
              name: 'peepoHey',
              zeroWidth: false,
              url: 'https://static.example/peepohey.png',
              type: EmoteType.sevenTVChannel,
              ownerDisplayName: 'SevenTV',
              ownerUsername: 'seventv',
            ),
          },
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    expect(_findImage('https://static.example/peepohey.png'), findsOneWidget);

    await tester.tap(
      find
          .ancestor(
            of: _findImage('https://static.example/peepohey.png'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('peepoHey'), findsWidgets);
    expect(find.text('7TV channel emote'), findsOneWidget);
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
        ),
      ),
    );

    expect(find.byTooltip('Collapse pinned chat'), findsOneWidget);
    expect(find.textContaining('SenderName'), findsOneWidget);

    final previewRichText = _findRichTextContaining('PartyPopper');
    expect(previewRichText.maxLines, isNull);
    expect(previewRichText.text.toPlainText(), contains('subs!\nhttps://'));

    await tester.tap(find.byTooltip('Collapse pinned chat'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand pinned chat'), findsOneWidget);
    expect(_findRichTextContaining('PartyPopper').maxLines, 1);
    expect(find.textContaining('SenderName'), findsNothing);

    if (find.byTooltip('Expand pinned chat').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Expand pinned chat'));
      await tester.pumpAndSettle();
    }

    expect(find.byTooltip('Collapse pinned chat'), findsOneWidget);
    expect(_findRichTextContaining('PartyPopper').maxLines, isNull);
    expect(find.textContaining('SenderName'), findsOneWidget);
  });

  testWidgets('starts very long pinned chats expanded and toggles minimized', (
    tester,
  ) async {
    const longMessage =
        'M3 LINKS -> Discord: discord.gg/mar3lg | X: x.com/communities/1926380245063520455 | Snapchat: https://www.snapchat.com/add/marlonluga | YouTube: youtube.com/@mar3lg';

    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [_pin(id: 'pin-1', messageText: longMessage)],
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    expect(find.byTooltip('Collapse pinned chat'), findsOneWidget);
    expect(find.byTooltip('Expand pinned chat'), findsNothing);
    expect(_findRichTextContaining('M3 LINKS').maxLines, isNull);
    expect(find.textContaining('SenderName'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse pinned chat'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand pinned chat'), findsOneWidget);
    expect(find.byTooltip('Collapse pinned chat'), findsNothing);
    expect(_findRichTextContaining('M3 LINKS').maxLines, 1);
    expect(find.textContaining('SenderName'), findsNothing);
  });

  testWidgets('shows the full expanded pinned message in a narrow chat', (
    tester,
  ) async {
    const longMessage =
        'FREE TWITCH SUB FOR NO ADS AND EMOTES -> Go to https://twitch.tv/prime and subscribe here: twitch.tv/subs/mooda';

    await tester.pumpWidget(
      _TestApp(
        width: 240,
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText: longMessage,
              senderDisplayName: 'Fossabot',
              pinnedByDisplayName: 'popcorn643',
              pinnedByBadges: const [
                PinnedChatBadge(
                  setId: 'moderator',
                  version: '1',
                  title: 'Moderator',
                  imageUrl: 'https://static.example/pinner-mod.png',
                ),
              ],
              senderBadges: const [
                PinnedChatBadge(
                  setId: 'moderator',
                  version: '1',
                  title: 'Moderator',
                  imageUrl: 'https://static.example/sender-mod.png',
                ),
              ],
            ),
          ],
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      _findRenderParagraphContaining('FREE TWITCH SUB').didExceedMaxLines,
      isFalse,
    );
    expect(find.textContaining('Fossabot'), findsOneWidget);
  });

  testWidgets('does not overflow in a skinny side chat width', (tester) async {
    const longMessage =
        'Follow up the new tiktok https://www.tiktok.com/@yuqi?_r=1&_t=ZN-97J6joaxpv0';

    await tester.pumpWidget(
      _TestApp(
        width: 180,
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText: longMessage,
              pinnedByDisplayName: 'Jaycondones2x',
              senderDisplayName: 'Jaycondones2x',
              pinnedByBadges: const [
                PinnedChatBadge(
                  setId: 'moderator',
                  version: '1',
                  title: 'Moderator',
                  imageUrl: 'https://static.example/pinner-mod.png',
                ),
              ],
              senderBadges: const [
                PinnedChatBadge(
                  setId: 'moderator',
                  version: '1',
                  title: 'Moderator',
                  imageUrl: 'https://static.example/sender-mod.png',
                ),
                PinnedChatBadge(
                  setId: 'subscriber',
                  version: '12',
                  title: '12-Month Subscriber',
                  imageUrl: 'https://static.example/sender-sub.png',
                ),
                PinnedChatBadge(
                  setId: 'bits',
                  version: '1000',
                  title: 'Cheer 1K',
                  imageUrl: 'https://static.example/sender-bits.png',
                ),
              ],
            ),
          ],
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows expanded pinned metadata without ellipses', (
    tester,
  ) async {
    const longMessage =
        'Follow up the new tiktok https://www.tiktok.com/@yuqi?_r=1&_t=ZN-97J6joaxpv0';

    await tester.pumpWidget(
      _TestApp(
        width: 320,
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText: longMessage,
              pinnedByDisplayName: 'Jaycondones2x',
              senderDisplayName: 'Jaycondones2x',
              pinnedByBadges: const [
                PinnedChatBadge(
                  setId: 'moderator',
                  version: '1',
                  title: 'Moderator',
                  imageUrl: 'https://static.example/pinner-mod.png',
                ),
              ],
              senderBadges: const [
                PinnedChatBadge(
                  setId: 'moderator',
                  version: '1',
                  title: 'Moderator',
                  imageUrl: 'https://static.example/sender-mod.png',
                ),
                PinnedChatBadge(
                  setId: 'subscriber',
                  version: '12',
                  title: '12-Month Subscriber',
                  imageUrl: 'https://static.example/sender-sub.png',
                ),
                PinnedChatBadge(
                  setId: 'bits',
                  version: '1000',
                  title: 'Cheer 1K',
                  imageUrl: 'https://static.example/sender-bits.png',
                ),
              ],
            ),
          ],
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    final metadataTexts = _findRichTextsContaining('Jaycondones2x');

    expect(metadataTexts.length, greaterThanOrEqualTo(2));
    expect(
      metadataTexts.where((text) => text.overflow == TextOverflow.ellipsis),
      isEmpty,
    );
  });

  testWidgets('keeps badges on the same line as wrapped names', (tester) async {
    const longMessage = 'Follow tiktok https://www.tiktok.com/@yuqi';
    const displayName = 'Jaycondones2xLongName';

    await tester.pumpWidget(
      _TestApp(
        width: 160,
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(
              id: 'pin-1',
              messageText: longMessage,
              pinnedByDisplayName: displayName,
              senderDisplayName: displayName,
              pinnedByBadges: const [
                PinnedChatBadge(
                  setId: 'moderator',
                  version: '1',
                  title: 'Moderator',
                  imageUrl: 'https://static.example/pinner-mod.png',
                ),
              ],
              senderBadges: const [
                PinnedChatBadge(
                  setId: 'moderator',
                  version: '1',
                  title: 'Moderator',
                  imageUrl: 'https://static.example/sender-mod.png',
                ),
              ],
            ),
          ],
          launchExternal: false,
          onDismiss: (_) {},
        ),
      ),
    );

    if (find.byTooltip('Expand pinned chat').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Expand pinned chat'));
      await tester.pumpAndSettle();
    }

    final nameCenters = _textFirstLineCentersY(displayName);
    expect(nameCenters.length, greaterThanOrEqualTo(2));

    final pinnedByBadgeCenter = tester
        .getRect(_findImage('https://static.example/pinner-mod.png'))
        .center
        .dy;
    expect(_nearestDistance(pinnedByBadgeCenter, nameCenters), lessThan(8));

    final senderBadgeCenter = tester
        .getRect(_findImage('https://static.example/sender-mod.png'))
        .center
        .dy;
    expect(_nearestDistance(senderBadgeCenter, nameCenters), lessThan(8));
  });
}

class _TestApp extends StatelessWidget {
  final Widget child;
  final double width;

  const _TestApp({required this.child, this.width = 360});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: const FrostyThemes(colorSchemeSeed: Color(0xFF9146FF)).dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, child: child),
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
  String senderDisplayName = 'SenderName',
  String pinnedByDisplayName = 'ModName',
}) => PinnedChatMessage(
  id: id,
  messageId: 'message-$id',
  messageText: messageText,
  senderDisplayName: senderDisplayName,
  pinnedByDisplayName: pinnedByDisplayName,
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

RenderParagraph _findRenderParagraphContaining(String text) {
  for (final richText in find.byType(RichText).evaluate()) {
    final widget = richText.widget as RichText;
    if (!widget.text.toPlainText().contains(text)) continue;

    final renderObject = richText.renderObject;
    if (renderObject is RenderParagraph) return renderObject;
  }

  throw StateError('No RenderParagraph found containing "$text"');
}

List<RichText> _findRichTextsContaining(String text) {
  return [
    for (final richText in find.byType(RichText).evaluate())
      if ((richText.widget as RichText).text.toPlainText().contains(text))
        richText.widget as RichText,
  ];
}

List<double> _textFirstLineCentersY(String text) {
  final centers = <double>[];

  for (final element in find.byType(RichText).evaluate()) {
    final center = _firstLineCenterY(element, text);
    if (center != null) centers.add(center);
  }

  return centers;
}

double? _firstLineCenterY(Element element, String text) {
  final renderObject = element.renderObject;
  if (renderObject is! RenderParagraph) return null;

  final plainText = renderObject.text.toPlainText();
  if (plainText != text) return null;

  final boxes = renderObject.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: plainText.length),
  );
  if (boxes.isEmpty) return null;

  final paragraphOffset = renderObject.localToGlobal(Offset.zero);
  return boxes.first.toRect().shift(paragraphOffset).center.dy;
}

double _nearestDistance(double target, List<double> values) {
  return values
      .map((value) => (value - target).abs())
      .reduce((a, b) => a < b ? a : b);
}
