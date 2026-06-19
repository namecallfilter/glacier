import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/screens/channel/chat/stores/pinned_chat_polling.dart';

void main() {
  group('pinnedChatPollInterval', () {
    test('uses a one second interval when auto-sync is off', () {
      expect(
        pinnedChatPollInterval(
          autoSyncChatDelay: false,
          syncedChatDelaySeconds: 12.5,
        ),
        const Duration(seconds: 1),
      );
    });

    test('adds synced latency when auto-sync is on', () {
      expect(
        pinnedChatPollInterval(
          autoSyncChatDelay: true,
          syncedChatDelaySeconds: 2.35,
        ),
        const Duration(milliseconds: 3350),
      );
    });

    test('tracks fluctuating synced latency values', () {
      final lowLatencyInterval = pinnedChatPollInterval(
        autoSyncChatDelay: true,
        syncedChatDelaySeconds: 0.75,
      );
      final highLatencyInterval = pinnedChatPollInterval(
        autoSyncChatDelay: true,
        syncedChatDelaySeconds: 4.2,
      );

      expect(lowLatencyInterval, const Duration(milliseconds: 1750));
      expect(highLatencyInterval, const Duration(milliseconds: 5200));
    });

    test('does not go below the one second base interval', () {
      expect(
        pinnedChatPollInterval(
          autoSyncChatDelay: true,
          syncedChatDelaySeconds: -3,
        ),
        const Duration(seconds: 1),
      );
    });
  });
}
