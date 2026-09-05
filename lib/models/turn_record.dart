/// A completed turn.
///
/// [duration] is the *active* (non-paused) time the player spent. Because the
/// controller advances [GameState.currentTurnStartTime] past any paused gaps,
/// the invariant `endTime - startTime == duration` holds — but [duration] is
/// stored explicitly (and is always non-negative) so it is the single source
/// of truth for statistics.
class TurnRecord {
  const TurnRecord({
    required this.playerId,
    required this.startTime,
    required this.endTime,
    required this.duration,
  });

  final String playerId;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'startMs': startTime.millisecondsSinceEpoch,
    'endMs': endTime.millisecondsSinceEpoch,
    'durationMicros': duration.inMicroseconds,
  };

  factory TurnRecord.fromJson(Map<String, dynamic> json) => TurnRecord(
    playerId: json['playerId'] as String,
    startTime: DateTime.fromMillisecondsSinceEpoch(
      (json['startMs'] as num).toInt(),
    ),
    endTime: DateTime.fromMillisecondsSinceEpoch(
      (json['endMs'] as num).toInt(),
    ),
    duration: Duration(microseconds: (json['durationMicros'] as num).toInt()),
  );
}
