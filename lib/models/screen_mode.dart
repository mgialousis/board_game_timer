/// How the screen should behave during an active game.
enum ScreenMode {
  /// Normal OS screen timeout; no special handling.
  normal,

  /// Keep the display on for the whole game (most battery-hungry).
  keepAwake,

  /// Let the screen turn off and show a lock-screen surface (an Android
  /// notification / iOS Live Activity) with the active player's color and
  /// Next/Pause controls. The most battery-friendly way to run a long game.
  lockedPlay;

  String get id => name;

  static ScreenMode fromId(String? id) => ScreenMode.values.firstWhere(
    (m) => m.name == id,
    orElse: () => ScreenMode.normal,
  );
}
