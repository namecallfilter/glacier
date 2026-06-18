import 'package:frosty/models/pinned_chat.dart';

List<PinnedChatMessage> reconcilePinnedChats({
  required Iterable<PinnedChatMessage> currentPins,
  required Iterable<PinnedChatMessage> fetchedPins,
  required Set<String> dismissedPinIds,
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now().toUtc();

  return fetchedPins.where((pin) {
    if (dismissedPinIds.contains(pin.id)) return false;
    final endsAt = pin.endsAt;
    return endsAt == null || endsAt.isAfter(effectiveNow);
  }).toList();
}
