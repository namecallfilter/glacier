import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/models/pinned_chat.dart';
import 'package:frosty/screens/channel/chat/stores/pinned_chat_reconciliation.dart';

void main() {
  group('reconcilePinnedChats', () {
    test('replaces current pins with fetched pins', () {
      final current = [_pin(id: 'old-pin', messageId: 'old-msg')];
      final fetched = [_pin(id: 'new-pin', messageId: 'new-msg')];

      final result = reconcilePinnedChats(
        currentPins: current,
        fetchedPins: fetched,
        dismissedPinIds: const {},
      );

      expect(result.map((pin) => pin.id), ['new-pin']);
    });

    test('filters dismissed pins', () {
      final result = reconcilePinnedChats(
        currentPins: const [],
        fetchedPins: [
          _pin(id: 'visible-pin', messageId: 'visible-msg'),
          _pin(id: 'dismissed-pin', messageId: 'dismissed-msg'),
        ],
        dismissedPinIds: const {'dismissed-pin'},
      );

      expect(result.map((pin) => pin.id), ['visible-pin']);
    });

    test('filters expired pins', () {
      final now = DateTime.parse('2026-06-18T05:00:00Z');

      final result = reconcilePinnedChats(
        currentPins: const [],
        fetchedPins: [
          _pin(
            id: 'expired-pin',
            messageId: 'expired-msg',
            endsAt: DateTime.parse('2026-06-18T04:59:59Z'),
          ),
          _pin(
            id: 'active-pin',
            messageId: 'active-msg',
            endsAt: DateTime.parse('2026-06-18T05:00:01Z'),
          ),
          _pin(id: 'no-expiry-pin', messageId: 'no-expiry-msg'),
        ],
        dismissedPinIds: const {},
        now: now,
      );

      expect(result.map((pin) => pin.id), ['active-pin', 'no-expiry-pin']);
    });

    test('preserves fetched order for visible pins', () {
      final result = reconcilePinnedChats(
        currentPins: const [],
        fetchedPins: [
          _pin(id: 'pin-1', messageId: 'msg-1'),
          _pin(id: 'pin-2', messageId: 'msg-2'),
          _pin(id: 'pin-3', messageId: 'msg-3'),
        ],
        dismissedPinIds: const {},
      );

      expect(result.map((pin) => pin.id), ['pin-1', 'pin-2', 'pin-3']);
    });
  });
}

PinnedChatMessage _pin({
  required String id,
  required String messageId,
  DateTime? endsAt,
}) => PinnedChatMessage(
  id: id,
  messageId: messageId,
  messageText: 'Message for $id',
  senderDisplayName: 'Sender',
  endsAt: endsAt,
);
