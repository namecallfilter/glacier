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
                      'chatColor': '#FF0000',
                    },
                    'pinnedMessage': {
                      'id': 'msg-1',
                      'sentAt': '2026-06-18T04:09:30Z',
                      'text': 'Please raise your hand',
                      'sender': {
                        'id': 'sender-1',
                        'login': 'fossabot',
                        'displayName': 'Fossabot',
                        'chatColor': '#00FF00',
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
      expect(pins.first.senderColor, '#00FF00');
      expect(pins.first.pinnedById, 'mod-1');
      expect(pins.first.pinnedByLogin, 'modname');
      expect(pins.first.pinnedByDisplayName, 'ModName');
      expect(pins.first.pinnedByColor, '#FF0000');
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

    test('parses Twitch badges and emote fragments', () {
      final pins = PinnedChatMessage.listFromGqlResponse({
        'data': {
          'channel': {
            'pinnedChatMessages': {
              'edges': [
                {
                  'node': {
                    'id': 'pin-rich',
                    'pinnedBy': {
                      'displayName': 'Opogix',
                      'badges': [
                        {
                          'setID': 'moderator',
                          'version': '1',
                          'title': 'Moderator',
                        },
                      ],
                    },
                    'pinnedMessage': {
                      'id': 'msg-rich',
                      'sender': {'displayName': 'Opogix'},
                      'badges': [
                        {
                          'setID': 'subscriber',
                          'version': '12',
                          'title': '12-Month Subscriber',
                          'imageURL4x': 'https://static.example/sub-4x.png',
                        },
                      ],
                      'fragments': [
                        {'text': '50% off all subs! '},
                        {
                          'text': 'Kappa',
                          'emote': {'emoteID': '25'},
                        },
                        {'text': ' https://www.twitch.tv/subs/marlon'},
                      ],
                    },
                  },
                },
              ],
            },
          },
        },
      });

      final pin = pins.single;

      expect(
        pin.messageText,
        '50% off all subs! Kappa https://www.twitch.tv/subs/marlon',
      );
      expect(pin.senderBadges.single.key, 'subscriber/12');
      expect(pin.senderBadges.single.title, '12-Month Subscriber');
      expect(
        pin.senderBadges.single.imageUrl,
        'https://static.example/sub-4x.png',
      );
      expect(pin.pinnedByBadges.single.key, 'moderator/1');
      expect(pin.fragments, hasLength(3));
      expect(pin.fragments[1].text, 'Kappa');
      expect(pin.fragments[1].emote?.id, '25');
      expect(
        pin.fragments[1].emote?.imageUrl,
        'https://static-cdn.jtvnw.net/emoticons/v2/25/default/dark/3.0',
      );
    });

    test('parses display badges and infers pinned-by authority badge', () {
      final pins = PinnedChatMessage.listFromGqlResponse({
        'data': {
          'channel': {
            'pinnedChatMessages': {
              'edges': [
                {
                  'node': {
                    'id': 'pin-display-badges',
                    'type': 'MOD',
                    'pinnedBy': {'id': '672062767', 'displayName': '0pogix'},
                    'pinnedMessage': {
                      'id': 'msg-display-badges',
                      'content': {
                        'text':
                            'PartyPopper 50% off on all subs! https://www.twitch.tv/subs/marlon',
                        'fragments': [
                          {
                            'content': {'emoteID': '426170'},
                            'text': 'PartyPopper',
                          },
                          {'content': null, 'text': ' 50% off on all subs! '},
                          {
                            'content': null,
                            'text': 'https://www.twitch.tv/subs/marlon',
                          },
                        ],
                      },
                      'sentAt': '2026-06-18T16:37:51.213618213Z',
                      'sender': {
                        'id': '672062767',
                        'displayName': '0pogix',
                        'displayBadges': [
                          {
                            'id': 'bW9kZXJhdG9yOzE7',
                            'setID': 'moderator',
                            'version': '1',
                          },
                          {
                            'id': 'c3Vic2NyaWJlcjsxMjsxMDE5NzMzNjQ3',
                            'setID': 'subscriber',
                            'version': '12',
                          },
                          {
                            'id': 'eW91LWdvdC10aGlzOzE7',
                            'setID': 'you-got-this',
                            'version': '1',
                          },
                        ],
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      });

      final pin = pins.single;

      expect(pin.senderBadges.map((badge) => badge.key), [
        'moderator/1',
        'subscriber/12',
        'you-got-this/1',
      ]);
      expect(pin.pinnedByBadges.single.key, 'moderator/1');
      expect(pin.fragments.first.emote?.id, '426170');
    });

    test('parses badge connection and keyed map payloads', () {
      final pins = PinnedChatMessage.listFromGqlResponse({
        'data': {
          'channel': {
            'pinnedChatMessages': {
              'edges': [
                {
                  'node': {
                    'id': 'pin-badge-shapes',
                    'pinnedBy': {
                      'displayName': 'ModName',
                      'displayBadges': {
                        'edges': [
                          {
                            'node': {
                              'setID': 'broadcaster',
                              'version': '1',
                              'title': 'Broadcaster',
                            },
                          },
                        ],
                      },
                    },
                    'pinnedMessage': {
                      'id': 'msg-badge-shapes',
                      'text': 'Pinned message',
                      'sender': {
                        'displayName': 'SenderName',
                        'badges': {
                          'subscriber/24': {
                            'title': '24-Month Subscriber',
                            'imageURL': 'https://static.example/sub.png',
                          },
                          'vip/1': {'title': 'VIP'},
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      });

      final pin = pins.single;

      expect(pin.pinnedByBadges.single.key, 'broadcaster/1');
      expect(pin.senderBadges.map((badge) => badge.key), [
        'subscriber/24',
        'vip/1',
      ]);
      expect(pin.senderBadges.first.imageUrl, 'https://static.example/sub.png');
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
