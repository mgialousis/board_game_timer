import 'dice_mode.dart';
import 'dice_roll.dart';
import 'player.dart';
import 'screen_mode.dart';
import 'turn_record.dart';
import 'undo_entry.dart';

/// The complete state of one game. Immutable — the controller swaps in a new
/// instance via [copyWith] on every action. Per-second UI ticks do *not* mutate
/// this; elapsed time is always derived from [currentTurnStartTime] and the
/// current wall clock, which keeps timing accurate across lag and backgrounding.
class GameState {
  const GameState({
    required this.players,
    required this.currentPlayerIndex,
    required this.currentTurnStartTime,
    required this.isPaused,
    required this.pausedAt,
    required this.turnHistory,
    required this.undoStack,
    required this.gameName,
    required this.startedAt,
    required this.endedAt,
    required this.batterySaverMode,
    required this.screenMode,
    required this.turnWarningThreshold,
    this.diceMode = DiceMode.off,
    this.rolls = const [],
    this.currentTurnRolled = false,
  });

  final List<Player> players;
  final int currentPlayerIndex;

  /// Effective start of the current turn's *active* counting. The controller
  /// shifts this forward by paused gaps, so `now - currentTurnStartTime` is
  /// always the active elapsed while running.
  final DateTime currentTurnStartTime;

  final bool isPaused;

  /// When the current pause began. Non-null iff [isPaused].
  final DateTime? pausedAt;

  final List<TurnRecord> turnHistory;
  final List<UndoEntry> undoStack;
  final String gameName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool batterySaverMode;

  /// How the screen behaves during this game (normal / keep awake / locked play).
  final ScreenMode screenMode;

  /// Soft per-turn time limit; zero means disabled. See [isCurrentTurnOverLimit].
  final Duration turnWarningThreshold;

  /// Whether this game records dice rolls (and which dice).
  final DiceMode diceMode;

  /// Every roll logged this game, in order. A roll is attributed to the player
  /// whose turn it started.
  final List<DiceRoll> rolls;

  /// Whether the *in-progress* turn already has a roll.
  ///
  /// Explicit state rather than something derived from [rolls]: undo and resume
  /// synthesize [currentTurnStartTime], so any timestamp-based derivation would
  /// be fragile. This single flag is what makes one number button mean either
  /// "log this player's roll" or "pass the turn and log the next player's".
  final bool currentTurnRolled;

  // --- Derived state -------------------------------------------------------

  bool get isFinished => endedAt != null;
  Player get currentPlayer => players[currentPlayerIndex];
  int get nextPlayerIndex => (currentPlayerIndex + 1) % players.length;
  Player get nextPlayer => players[nextPlayerIndex];

  /// Active elapsed of the in-progress turn at [now]. Frozen while paused and
  /// never negative.
  Duration currentTurnElapsed(DateTime now) {
    final reference = isPaused ? (pausedAt ?? now) : now;
    final d = reference.difference(currentTurnStartTime);
    return d.isNegative ? Duration.zero : d;
  }

  /// Total time to show for the current player: recorded time plus the
  /// in-progress turn.
  Duration currentPlayerTotal(DateTime now) =>
      currentPlayer.accumulatedDuration + currentTurnElapsed(now);

  /// Whether the in-progress turn has reached [turnWarningThreshold]. Always
  /// false when the threshold is disabled (zero).
  bool isCurrentTurnOverLimit(DateTime now) =>
      turnWarningThreshold > Duration.zero &&
      currentTurnElapsed(now) >= turnWarningThreshold;

  /// The roll logged for the turn in progress, or null if the active player
  /// hasn't rolled yet.
  int? get currentTurnRoll =>
      currentTurnRolled && rolls.isNotEmpty ? rolls.last.total : null;

  /// Every roll's total, in order — the input to [DiceStats].
  List<int> get rollTotals => [for (final r in rolls) r.total];

  // Post-game statistics (totals, percentages, winner) live on [GameRecord],
  // which is what the results screen and the history log render.

  // --- copyWith ------------------------------------------------------------

  static const Object _unset = Object();

  GameState copyWith({
    List<Player>? players,
    int? currentPlayerIndex,
    DateTime? currentTurnStartTime,
    bool? isPaused,
    Object? pausedAt = _unset,
    List<TurnRecord>? turnHistory,
    List<UndoEntry>? undoStack,
    String? gameName,
    DateTime? startedAt,
    Object? endedAt = _unset,
    bool? batterySaverMode,
    ScreenMode? screenMode,
    Duration? turnWarningThreshold,
    DiceMode? diceMode,
    List<DiceRoll>? rolls,
    bool? currentTurnRolled,
  }) {
    return GameState(
      players: players ?? this.players,
      currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
      currentTurnStartTime: currentTurnStartTime ?? this.currentTurnStartTime,
      isPaused: isPaused ?? this.isPaused,
      pausedAt: identical(pausedAt, _unset)
          ? this.pausedAt
          : pausedAt as DateTime?,
      turnHistory: turnHistory ?? this.turnHistory,
      undoStack: undoStack ?? this.undoStack,
      gameName: gameName ?? this.gameName,
      startedAt: startedAt ?? this.startedAt,
      endedAt: identical(endedAt, _unset) ? this.endedAt : endedAt as DateTime?,
      batterySaverMode: batterySaverMode ?? this.batterySaverMode,
      screenMode: screenMode ?? this.screenMode,
      turnWarningThreshold: turnWarningThreshold ?? this.turnWarningThreshold,
      diceMode: diceMode ?? this.diceMode,
      rolls: rolls ?? this.rolls,
      currentTurnRolled: currentTurnRolled ?? this.currentTurnRolled,
    );
  }

  // --- Serialization -------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'version': 2,
    'players': players.map((p) => p.toJson()).toList(),
    'currentPlayerIndex': currentPlayerIndex,
    'currentTurnStartMs': currentTurnStartTime.millisecondsSinceEpoch,
    'isPaused': isPaused,
    'pausedAtMs': pausedAt?.millisecondsSinceEpoch,
    'turnHistory': turnHistory.map((t) => t.toJson()).toList(),
    'undoStack': undoStack.map((u) => u.toJson()).toList(),
    'gameName': gameName,
    'startedAtMs': startedAt.millisecondsSinceEpoch,
    'endedAtMs': endedAt?.millisecondsSinceEpoch,
    'batterySaverMode': batterySaverMode,
    'screenMode': screenMode.id,
    'turnWarningSeconds': turnWarningThreshold.inSeconds,
    'diceMode': diceMode.id,
    'rolls': rolls.map((r) => r.toJson()).toList(),
    'currentTurnRolled': currentTurnRolled,
  };

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
    players: (json['players'] as List)
        .map((e) => Player.fromJson(e as Map<String, dynamic>))
        .toList(),
    currentPlayerIndex: (json['currentPlayerIndex'] as num).toInt(),
    currentTurnStartTime: DateTime.fromMillisecondsSinceEpoch(
      (json['currentTurnStartMs'] as num).toInt(),
    ),
    isPaused: json['isPaused'] as bool? ?? false,
    pausedAt: json['pausedAtMs'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (json['pausedAtMs'] as num).toInt(),
          ),
    turnHistory: ((json['turnHistory'] as List?) ?? const [])
        .map((e) => TurnRecord.fromJson(e as Map<String, dynamic>))
        .toList(),
    undoStack: ((json['undoStack'] as List?) ?? const [])
        .map((e) => UndoEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    gameName: json['gameName'] as String? ?? '',
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['startedAtMs'] as num).toInt(),
    ),
    endedAt: json['endedAtMs'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (json['endedAtMs'] as num).toInt(),
          ),
    batterySaverMode: json['batterySaverMode'] as bool? ?? false,
    screenMode: json['screenMode'] != null
        ? ScreenMode.fromId(json['screenMode'] as String?)
        : ((json['keepScreenAwake'] as bool? ?? false)
              ? ScreenMode.keepAwake
              : ScreenMode.normal),
    turnWarningThreshold: Duration(
      seconds: (json['turnWarningSeconds'] as num?)?.toInt() ?? 0,
    ),
    // Absent in games saved before dice tracking existed: they load as a
    // perfectly ordinary game with the feature off.
    diceMode: DiceMode.fromId(json['diceMode'] as String?),
    rolls: ((json['rolls'] as List?) ?? const [])
        .map((e) => DiceRoll.fromJson(e as Map<String, dynamic>))
        .toList(),
    currentTurnRolled: json['currentTurnRolled'] as bool? ?? false,
  );
}
