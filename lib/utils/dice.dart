// Dice probability helpers and the aggregate a distribution chart needs.
//
// Kept free of Flutter imports so it can be unit-tested (and reused) on its
// own. All of it is derived from the roll list — nothing here is stored.

/// Lowest / highest total achievable with two six-sided dice.
const int kMinRoll = 2;
const int kMaxRoll = 12;

/// How many of the 36 equally likely two-dice combinations make each total.
/// 7 has six (1+6 … 6+1); 2 and 12 have one each. The values sum to 36.
const Map<int, int> kWaysToRoll = {
  2: 1,
  3: 2,
  4: 3,
  5: 4,
  6: 5,
  7: 6,
  8: 5,
  9: 4,
  10: 3,
  11: 2,
  12: 1,
};

/// The number of times [total] would be expected in [rolls] fair rolls.
double expectedCount(int total, int rolls) =>
    rolls * (kWaysToRoll[total] ?? 0) / 36;

bool isValidRoll(int total) => total >= kMinRoll && total <= kMaxRoll;

/// The distribution of a game's rolls: counts per total plus the handful of
/// derived figures the in-game strip and the results chart display.
///
/// Built from the compact `(totals, rollerIndices)` pair that a finished game
/// archives, so the live game and a 6-month-old history entry render through
/// exactly the same code.
class DiceStats {
  DiceStats._(this._counts, this._sevensByRoller, this.totalRolls);

  /// [totals] are the rolls in order; [rollerIndices] is the parallel list of
  /// player indices (may be shorter or empty — attribution is optional).
  factory DiceStats.from(
    List<int> totals, [
    List<int> rollerIndices = const [],
  ]) {
    final counts = <int, int>{for (var n = kMinRoll; n <= kMaxRoll; n++) n: 0};
    final sevens = <int, int>{};
    var used = 0;
    for (var i = 0; i < totals.length; i++) {
      final t = totals[i];
      if (!isValidRoll(t)) continue; // defensive: ignore corrupt entries
      counts[t] = counts[t]! + 1;
      used++;
      if (t == 7 && i < rollerIndices.length) {
        final r = rollerIndices[i];
        sevens[r] = (sevens[r] ?? 0) + 1;
      }
    }
    return DiceStats._(counts, sevens, used);
  }

  final Map<int, int> _counts;
  final Map<int, int> _sevensByRoller;

  /// Number of valid rolls recorded.
  final int totalRolls;

  bool get isEmpty => totalRolls == 0;

  int countFor(int total) => _counts[total] ?? 0;

  double expectedFor(int total) => expectedCount(total, totalRolls);

  /// How far [total] came up above (+) or below (-) its expected count.
  double deviationFor(int total) => countFor(total) - expectedFor(total);

  /// The largest count on any single total — the chart's vertical scale.
  int get maxCount => _counts.values.fold(0, (max, c) => c > max ? c : max);

  int get sevens => countFor(7);

  /// Sevens rolled by the player at each index (absent = none).
  Map<int, int> get sevensByPlayerIndex => Map.unmodifiable(_sevensByRoller);

  /// The player index that rolled the most 7s, or null if nobody did (or the
  /// lead is shared — a tie is not a distinction worth a badge).
  int? get mostSevensPlayerIndex {
    int? best;
    var bestCount = 0;
    var tied = false;
    _sevensByRoller.forEach((index, count) {
      if (count > bestCount) {
        best = index;
        bestCount = count;
        tied = false;
      } else if (count == bestCount) {
        tied = true;
      }
    });
    return tied ? null : best;
  }

  /// The total furthest above its expected count, or null when there are no
  /// rolls yet. Ties break towards the lower number, which is arbitrary but
  /// stable.
  int? get hottest => _extreme(hot: true);

  /// The total furthest below its expected count.
  int? get coldest => _extreme(hot: false);

  int? _extreme({required bool hot}) {
    if (isEmpty) return null;
    int? best;
    double bestDeviation = 0;
    for (var n = kMinRoll; n <= kMaxRoll; n++) {
      final d = deviationFor(n);
      if (best == null || (hot ? d > bestDeviation : d < bestDeviation)) {
        best = n;
        bestDeviation = d;
      }
    }
    return best;
  }
}
