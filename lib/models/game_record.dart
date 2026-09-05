import '../utils/dice.dart';
import 'game_state.dart';
import 'player.dart';

/// A finished game, frozen for the results screen and the history log.
///
/// Deliberately *not* a [GameState]: the live model carries turn history, an
/// undo stack and pause bookkeeping that a finished game has no use for. Every
/// figure the results screen shows is already aggregated onto each [Player], so
/// archiving this compact shape keeps each history entry a few hundred bytes
/// instead of growing with the number of turns played.
class GameRecord {
  const GameRecord({
    required this.id,
    required this.gameName,
    required this.startedAt,
    required this.endedAt,
    required this.players,
    this.rollTotals = const [],
    this.rollerIndices = const [],
  });

  /// Stable identity, derived from the game's own timestamps rather than a
  /// random value: rebuilding a record for the same game (e.g. after editing
  /// scores) yields the same id, so saving it updates the existing history
  /// entry instead of appending a duplicate.
  final String id;

  final String gameName;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<Player> players;

  /// Every dice total rolled, in order. Empty for games played without dice
  /// tracking — including every game archived before the feature existed.
  ///
  /// Stored as two flat int lists rather than objects because history keeps 50
  /// games: an 80-roll game costs a few hundred bytes this way, while still
  /// being lossless enough to rebuild the distribution *and* who rolled what.
  final List<int> rollTotals;

  /// Parallel to [rollTotals]: the index into [players] of who rolled it.
  final List<int> rollerIndices;

  static String idFor(DateTime startedAt, DateTime endedAt) =>
      'g${startedAt.millisecondsSinceEpoch}-${endedAt.millisecondsSinceEpoch}';

  factory GameRecord.fromGameState(GameState g) {
    final ended = g.endedAt ?? g.startedAt;
    final indexOfPlayer = {
      for (var i = 0; i < g.players.length; i++) g.players[i].id: i,
    };
    return GameRecord(
      id: idFor(g.startedAt, ended),
      gameName: g.gameName,
      startedAt: g.startedAt,
      endedAt: ended,
      players: g.players,
      rollTotals: [for (final r in g.rolls) r.total],
      rollerIndices: [for (final r in g.rolls) indexOfPlayer[r.playerId] ?? -1],
    );
  }

  /// What to show when the player didn't name the game.
  String get title => gameName.isEmpty ? 'Board game' : gameName;

  /// Wall-clock length of the game, including pauses.
  Duration get gameLength {
    final d = endedAt.difference(startedAt);
    return d.isNegative ? Duration.zero : d;
  }

  // --- Time statistics -----------------------------------------------------

  /// Sum of every player's recorded time — the denominator for "percentage of
  /// total game time". Using thinking time (not wall clock) makes the shares
  /// add up to 100%.
  Duration get totalPlayedTime =>
      players.fold(Duration.zero, (sum, p) => sum + p.accumulatedDuration);

  double percentFor(Player player) {
    final total = totalPlayedTime.inMicroseconds;
    if (total == 0) return 0;
    return player.accumulatedDuration.inMicroseconds / total * 100;
  }

  /// The player with the most total recorded time, or null if nobody has any.
  Player? get slowestByTotal {
    Player? slowest;
    for (final p in players) {
      if (p.accumulatedDuration == Duration.zero) continue;
      if (slowest == null ||
          p.accumulatedDuration > slowest.accumulatedDuration) {
        slowest = p;
      }
    }
    return slowest;
  }

  /// The player with the highest average turn, among those who took a turn.
  Player? get slowestByAverage {
    Player? slowest;
    for (final p in players) {
      if (p.turnCount == 0) continue;
      if (slowest == null || p.averageTurn > slowest.averageTurn) {
        slowest = p;
      }
    }
    return slowest;
  }

  // --- Dice ----------------------------------------------------------------

  /// True once this game recorded at least one roll. The whole dice UI stays
  /// hidden until then, so games played without it (and every entry archived
  /// before the feature existed) look exactly as they always did.
  bool get hasRolls => rollTotals.isNotEmpty;

  DiceStats get diceStats => DiceStats.from(rollTotals, rollerIndices);

  /// How many 7s [player] rolled — the robber, so it is the one per-player
  /// dice figure worth showing.
  int sevensRolledBy(Player player) {
    final index = _indexOf(player);
    if (index < 0) return 0;
    return diceStats.sevensByPlayerIndex[index] ?? 0;
  }

  /// The player who rolled the most 7s, or null when nobody did or it's a tie.
  Player? get mostSevensPlayer {
    final index = diceStats.mostSevensPlayerIndex;
    if (index == null || index < 0 || index >= players.length) return null;
    return players[index];
  }

  /// How many rolls [player] made.
  int rollCountFor(Player player) {
    final index = _indexOf(player);
    if (index < 0) return 0;
    return rollerIndices.where((i) => i == index).length;
  }

  /// By id, not identity: [ranked] hands back re-sorted copies of the list.
  int _indexOf(Player player) => players.indexWhere((p) => p.id == player.id);

  // --- Scores --------------------------------------------------------------

  /// True once at least one score has been entered. Scoring is optional, so
  /// the whole winner UI stays hidden until then.
  bool get hasScores => players.any((p) => p.score != null);

  /// Highest score entered, or null if nobody has been scored.
  int? get topScore {
    int? top;
    for (final p in players) {
      final s = p.score;
      if (s == null) continue;
      if (top == null || s > top) top = s;
    }
    return top;
  }

  /// Everyone tied at [topScore] — highest score wins. Empty when unscored;
  /// more than one entry means the game was a draw.
  List<Player> get winners {
    final top = topScore;
    if (top == null) return const [];
    return players.where((p) => p.score == top).toList();
  }

  bool isWinner(Player player) =>
      player.score != null && player.score == topScore;

  /// Players in the order the results should be listed: by score once the game
  /// has been scored (unscored players last), otherwise by time spent.
  List<Player> get ranked {
    final list = [...players];
    if (hasScores) {
      list.sort((a, b) {
        final sa = a.score;
        final sb = b.score;
        if (sa == null && sb == null) {
          return b.accumulatedDuration.compareTo(a.accumulatedDuration);
        }
        if (sa == null) return 1;
        if (sb == null) return -1;
        if (sa != sb) return sb.compareTo(sa);
        return b.accumulatedDuration.compareTo(a.accumulatedDuration);
      });
    } else {
      list.sort(
        (a, b) => b.accumulatedDuration.compareTo(a.accumulatedDuration),
      );
    }
    return list;
  }

  /// Returns a copy with scores replaced, keyed by player id. A player missing
  /// from [scores] (or mapped to null) ends up unscored.
  GameRecord withScores(Map<String, int?> scores) => GameRecord(
    id: id,
    gameName: gameName,
    startedAt: startedAt,
    endedAt: endedAt,
    players: [
      for (final p in players)
        scores.containsKey(p.id) ? p.copyWith(score: scores[p.id]) : p,
    ],
    // Rebuilt by hand, so the dice must be carried over explicitly or editing
    // a score would silently erase the game's roll log.
    rollTotals: rollTotals,
    rollerIndices: rollerIndices,
  );

  // --- Serialization -------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'version': 2,
    'id': id,
    'gameName': gameName,
    'startedAtMs': startedAt.millisecondsSinceEpoch,
    'endedAtMs': endedAt.millisecondsSinceEpoch,
    'players': players.map((p) => p.toJson()).toList(),
    if (hasRolls) 'rollTotals': rollTotals,
    if (hasRolls) 'rollers': rollerIndices,
  };

  factory GameRecord.fromJson(Map<String, dynamic> json) {
    final startedAt = DateTime.fromMillisecondsSinceEpoch(
      (json['startedAtMs'] as num).toInt(),
    );
    final endedAt = DateTime.fromMillisecondsSinceEpoch(
      (json['endedAtMs'] as num).toInt(),
    );
    return GameRecord(
      id: json['id'] as String? ?? idFor(startedAt, endedAt),
      gameName: json['gameName'] as String? ?? '',
      startedAt: startedAt,
      endedAt: endedAt,
      players: (json['players'] as List)
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList(),
      // Absent on every entry archived before dice tracking: those games load
      // as `hasRolls == false` and render exactly as they used to.
      rollTotals: _intList(json['rollTotals']),
      rollerIndices: _intList(json['rollers']),
    );
  }

  static List<int> _intList(Object? value) => value is List
      ? [
          for (final e in value)
            if (e is num) e.toInt(),
        ]
      : const [];
}
