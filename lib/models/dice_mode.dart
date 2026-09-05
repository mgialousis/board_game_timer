/// Whether (and how) a game records dice rolls.
///
/// An enum rather than a bool so other dice can be added later (a d20, or the
/// Cities & Knights event die) without another persistence migration.
enum DiceMode {
  /// No dice tracking — the app behaves exactly as it did before the feature.
  off('off'),

  /// Catan-style: one two-dice total (2..12) per turn.
  twoD6('2d6');

  const DiceMode(this.id);

  /// Stable string used in JSON, so reordering the enum can't corrupt saves.
  final String id;

  bool get isOn => this != DiceMode.off;

  static DiceMode fromId(String? id) =>
      DiceMode.values.firstWhere((m) => m.id == id, orElse: () => DiceMode.off);
}
