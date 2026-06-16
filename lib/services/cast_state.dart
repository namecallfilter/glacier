class CastState {
  final bool isCasting;
  final String? receiverName;
  final Duration? latency;
  final String? statusMessage;
  final String? castMode;

  const CastState({
    required this.isCasting,
    this.receiverName,
    this.latency,
    this.statusMessage,
    this.castMode,
  });

  const CastState.disconnected()
    : isCasting = false,
      receiverName = null,
      latency = null,
      statusMessage = null,
      castMode = null;

  double? get latencySeconds {
    final currentLatency = latency;
    return currentLatency == null ? null : currentLatency.inMilliseconds / 1000;
  }

  String? get formattedLatency {
    final seconds = latencySeconds;
    return seconds == null ? null : '${seconds.toStringAsFixed(2)}s';
  }

  factory CastState.fromMethodChannelPayload(Object? payload) {
    if (payload is! Map) return const CastState.disconnected();

    final isCasting = payload['isCasting'] == true;
    final receiverName = payload['receiverName'];
    final latencyMs = payload['latencyMs'];
    final statusMessage = payload['statusMessage'];
    final castMode = payload['castMode'];

    return CastState(
      isCasting: isCasting,
      receiverName: receiverName is String && receiverName.trim().isNotEmpty
          ? receiverName.trim()
          : null,
      latency: latencyMs is num && latencyMs >= 0
          ? Duration(milliseconds: latencyMs.round())
          : null,
      statusMessage: statusMessage is String && statusMessage.trim().isNotEmpty
          ? statusMessage.trim()
          : null,
      castMode: castMode is String && castMode.trim().isNotEmpty
          ? castMode.trim()
          : null,
    );
  }
}
