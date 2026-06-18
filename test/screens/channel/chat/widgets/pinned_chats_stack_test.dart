import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/models/pinned_chat.dart';
import 'package:frosty/screens/channel/chat/widgets/pinned_chats_stack.dart';

void main() {
  testWidgets('shows collapsed pinned chat stack with count', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: PinnedChatsStack(
          pinnedChats: [
            _pin(id: 'pin-1', messageText: 'First pinned message'),
            _pin(id: 'pin-2', messageText: 'Second pinned message'),
          ],
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
}

class _TestApp extends StatelessWidget {
  final Widget child;

  const _TestApp({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
