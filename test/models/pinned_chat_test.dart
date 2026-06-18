import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/models/pinned_chat.dart';

void main() {
  group('PinnedChatMessage.listFromGqlResponse', () {
    test('returns empty list when channel has no pinned chat messages', () {
      final pins = PinnedChatMessage.listFromGqlResponse({
        'data': {
          'channel': {
            'pinnedChatMessages': {'edges': <dynamic>[]},
          },
        },
      });

      expect(pins, isEmpty);
    });

    test('parses a pinned chat message with nested text field', () {
      final pins = PinnedChatMessage.listFromGqlResponse({
        'data': {
          'channel': {
            'pinnedChatMessages': {
              'edges': [
                {
                  'node': {
                    'id': 'pin-1',
                    'startsAt': '2026-06-18T04:10:00Z',
                    'updatedAt': '2026-06-18T04:11:00Z',
                    'endsAt': null,
                    'pinnedBy': {
                      'id': 'mod-1',
                      'login': 'modname',
                      'displayName': 'ModName',
                    },
                    'pinnedMessage': {
                      'id': 'msg-1',
                      'sentAt': '2026-06-18T04:09:30Z',
                      'text': 'Please raise your hand',
                      'sender': {
                        'id': 'sender-1',
                        'login': 'fossabot',
                        'displayName': 'Fossabot',
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      });

      expect(pins, hasLength(1));
      expect(pins.first.id, 'pin-1');
      expect(pins.first.messageId, 'msg-1');
      expect(pins.first.messageText, 'Please raise your hand');
      expect(pins.first.senderId, 'sender-1');
      expect(pins.first.senderLogin, 'fossabot');
      expect(pins.first.senderDisplayName, 'Fossabot');
      expect(pins.first.pinnedById, 'mod-1');
      expect(pins.first.pinnedByLogin, 'modname');
      expect(pins.first.pinnedByDisplayName, 'ModName');
      expect(pins.first.startsAt, DateTime.parse('2026-06-18T04:10:00Z'));
      expect(pins.first.updatedAt, DateTime.parse('2026-06-18T04:11:00Z'));
      expect(pins.first.endsAt, isNull);
      expect(pins.first.sentAt, DateTime.parse('2026-06-18T04:09:30Z'));
    });

    test('parses multiple pinned chat messages', () {
      final pins = PinnedChatMessage.listFromGqlResponse({
        'data': {
          'channel': {
            'pinnedChatMessages': {
              'edges': [
                {
                  'node': {
                    'id': 'pin-1',
                    'pinnedBy': {'displayName': 'ModOne'},
                    'pinnedMessage': {
                      'id': 'msg-1',
                      'text': 'First pin',
                      'sender': {'displayName': 'SenderOne'},
                    },
                  },
                },
                {
                  'node': {
                    'id': 'pin-2',
                    'pinnedBy': {'displayName': 'ModTwo'},
                    'pinnedMessage': {
                      'id': 'msg-2',
                      'message': {'text': 'Second pin'},
                      'sender': {'displayName': 'SenderTwo'},
                    },
                  },
                },
              ],
            },
          },
        },
      });

      expect(pins.map((pin) => pin.id), ['pin-1', 'pin-2']);
      expect(pins.map((pin) => pin.messageText), ['First pin', 'Second pin']);
    });

    test('builds text from fragments when direct text is missing', () {
      final pins = PinnedChatMessage.listFromGqlResponse({
        'data': {
          'channel': {
            'pinnedChatMessages': {
              'edges': [
                {
                  'node': {
                    'id': 'pin-fragments',
                    'pinnedMessage': {
                      'id': 'msg-fragments',
                      'content': {
                        'fragments': [
                          {'text': 'Hello'},
                          {'text': ' '},
                          {'text': '@chat'},
                        ],
                      },
                      'sender': {'displayName': 'FragmentSender'},
                    },
                  },
                },
              ],
            },
          },
        },
      });

      expect(pins.single.messageText, 'Hello @chat');
    });

    test('skips malformed nodes without an id or message id', () {
      final pins = PinnedChatMessage.listFromGqlResponse({
        'data': {
          'channel': {
            'pinnedChatMessages': {
              'edges': [
                {
                  'node': {
                    'id': 'pin-without-message',
                    'pinnedMessage': {'text': 'missing message id'},
                  },
                },
                {
                  'node': {
                    'pinnedMessage': {
                      'id': 'msg-without-pin',
                      'text': 'missing pin id',
                    },
                  },
                },
              ],
            },
          },
        },
      });

      expect(pins, isEmpty);
    });
  });
}
