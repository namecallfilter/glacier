const pinnedChatBasePollInterval = Duration(seconds: 1);

Duration pinnedChatPollInterval({
  required bool autoSyncChatDelay,
  required double syncedChatDelaySeconds,
}) {
  if (!autoSyncChatDelay || syncedChatDelaySeconds <= 0) {
    return pinnedChatBasePollInterval;
  }

  return pinnedChatBasePollInterval +
      Duration(milliseconds: (syncedChatDelaySeconds * 1000).round());
}
