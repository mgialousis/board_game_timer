/// One recorded dice roll, attributed to the player who rolled it.
///
/// Deliberately minimal: no timestamp, because a roll always belongs to the
/// turn that was starting when it was logged, and nothing needs it ordered by
/// wall clock. The list order is the roll order.
class DiceRoll {
  const DiceRoll({required this.playerId, required this.total});

  final String playerId;

  /// The sum of the dice — 2..12 for [DiceMode.twoD6].
  final int total;

  Map<String, dynamic> toJson() => {'p': playerId, 't': total};

  factory DiceRoll.fromJson(Map<String, dynamic> json) => DiceRoll(
    playerId: json['p'] as String,
    total: (json['t'] as num).toInt(),
  );
}
