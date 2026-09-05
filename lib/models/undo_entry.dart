/// What kind of action an [UndoEntry] reverts.
enum UndoKind {
  /// A turn change: the previous player's turn was recorded.
  advance,

  /// The current player passed without their time being recorded.
  skip,

  /// A dice roll was logged for the current player *without* changing turn.
  roll,
}

/// One reversible step on the undo stack.
///
/// We store the *relative* elapsed of the turn we are returning to
/// ([previousElapsed]) rather than an absolute timestamp, so undo stays correct
/// no matter how much wall-clock time passed before the user pressed Undo, and
/// so it respects whatever the pause state is when it is applied.
class UndoEntry {
  const UndoEntry({
    required this.kind,
    required this.previousPlayerIndex,
    required this.previousElapsed,
    this.recordedRoll,
    this.previousTurnRolled = false,
  });

  final UndoKind kind;
  final int previousPlayerIndex;
  final Duration previousElapsed;

  /// The dice roll logged as part of this step, if any. Set for
  /// [UndoKind.roll], and for an [UndoKind.advance] that also logged the
  /// incoming player's roll — undoing either drops the roll again.
  final int? recordedRoll;

  /// Whether the turn we are returning to had already been rolled for, so undo
  /// restores [GameState.currentTurnRolled] rather than guessing it.
  final bool previousTurnRolled;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'previousPlayerIndex': previousPlayerIndex,
    'previousElapsedMicros': previousElapsed.inMicroseconds,
    'recordedRoll': recordedRoll,
    'previousTurnRolled': previousTurnRolled,
  };

  factory UndoEntry.fromJson(Map<String, dynamic> json) => UndoEntry(
    kind: UndoKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => UndoKind.advance,
    ),
    previousPlayerIndex: (json['previousPlayerIndex'] as num).toInt(),
    previousElapsed: Duration(
      microseconds: (json['previousElapsedMicros'] as num).toInt(),
    ),
    // Both absent on undo stacks saved before dice tracking existed.
    recordedRoll: (json['recordedRoll'] as num?)?.toInt(),
    previousTurnRolled: json['previousTurnRolled'] as bool? ?? false,
  );
}
