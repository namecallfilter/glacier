import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/screens/channel/video/video_store.dart';
import 'package:frosty/services/cast_state.dart';

void main() {
  group('shouldClearLocalLoadingForCast', () {
    test('clears local loading while casting', () {
      expect(
        shouldClearLocalLoadingForCast(const CastState(isCasting: true)),
        isTrue,
      );
    });

    test('keeps local loading state when disconnected', () {
      expect(
        shouldClearLocalLoadingForCast(const CastState.disconnected()),
        isFalse,
      );
    });
  });
}
