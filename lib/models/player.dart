import 'dart:ui' show Color;

/// A participant in a game.
///
/// Identity and appearance ([id], [name], [colorValue]) are chosen during
/// setup and never change once a game starts. The statistics fields
/// ([accumulatedDuration], [turnCount], [longestTurn]) are a *projection* of
/// [GameState.turnHistory]: the controller recomputes them from history after
/// every mutation so they stay consistent across undo and skip. They never
/// include the in-progress turn.
///
/// [score] is different: it is entered by hand at the end of the game and is
/// not derivable from anything, so the stat recomputation leaves it alone.
class Player {
  const Player({
    required this.id,
    required this.name,
    required this.colorValue,
    this.accumulatedDuration = Duration.zero,
    this.turnCount = 0,
    this.longestTurn = Duration.zero,
    this.score,
  });

  final String id;
  final String name;

  /// ARGB color value. Render with `Color(colorValue)`.
  final int colorValue;

  final Duration accumulatedDuration;
  final int turnCount;
  final Duration longestTurn;

  /// Final score for the game, entered after play. Null means "not scored" —
  /// deliberately distinct from a score of 0, which is a real result.
  /// May be negative; some games score below zero.
  final int? score;

  Color get color => Color(colorValue);

  /// Mean completed-turn length. Zero when the player has not finished a turn.
  Duration get averageTurn => turnCount == 0
      ? Duration.zero
      : Duration(microseconds: accumulatedDuration.inMicroseconds ~/ turnCount);

  /// The same person, ready to play again: identity and color kept, all
  /// results cleared (including [score], which `copyWith` alone cannot null).
  Player resetForNewGame() =>
      Player(id: id, name: name, colorValue: colorValue);

  static const Object _unset = Object();

  Player copyWith({
    String? name,
    int? colorValue,
    Duration? accumulatedDuration,
    int? turnCount,
    Duration? longestTurn,
    // Sentinel-defaulted so passing an explicit null *clears* the score
    // (needed when a score is erased in the edit sheet).
    Object? score = _unset,
  }) {
    return Player(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      accumulatedDuration: accumulatedDuration ?? this.accumulatedDuration,
      turnCount: turnCount ?? this.turnCount,
      longestTurn: longestTurn ?? this.longestTurn,
      score: identical(score, _unset) ? this.score : score as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'accumulatedMicros': accumulatedDuration.inMicroseconds,
    'turnCount': turnCount,
    'longestMicros': longestTurn.inMicroseconds,
    'score': score,
  };

  factory Player.fromJson(Map<String, dynamic> json) => Player(
    id: json['id'] as String,
    name: json['name'] as String,
    colorValue: (json['colorValue'] as num).toInt(),
    accumulatedDuration: Duration(
      microseconds: (json['accumulatedMicros'] as num?)?.toInt() ?? 0,
    ),
    turnCount: (json['turnCount'] as num?)?.toInt() ?? 0,
    longestTurn: Duration(
      microseconds: (json['longestMicros'] as num?)?.toInt() ?? 0,
    ),
    // Absent in games saved before scoring existed.
    score: (json['score'] as num?)?.toInt(),
  );
}
