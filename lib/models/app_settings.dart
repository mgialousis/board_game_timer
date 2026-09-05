import 'dice_mode.dart';
import 'screen_mode.dart';

/// User preferences that persist independently of any single game, so a brand
/// new game remembers the last-used choices.
class AppSettings {
  const AppSettings({
    this.batterySaverMode = false,
    this.screenMode = ScreenMode.normal,
    this.turnWarningThreshold = Duration.zero,
    this.diceMode = DiceMode.off,
  });

  /// Disables the active-player pulse animation.
  final bool batterySaverMode;

  /// How the screen behaves during a game (normal / keep awake / locked play).
  final ScreenMode screenMode;

  /// Soft per-turn time limit. When greater than zero, the game screen shows a
  /// subtle warning once the active turn exceeds this. Zero means "off".
  final Duration turnWarningThreshold;

  /// Whether new games record dice rolls. Off by default, so nothing about the
  /// app changes for anyone who doesn't want it.
  final DiceMode diceMode;

  AppSettings copyWith({
    bool? batterySaverMode,
    ScreenMode? screenMode,
    Duration? turnWarningThreshold,
    DiceMode? diceMode,
  }) => AppSettings(
    batterySaverMode: batterySaverMode ?? this.batterySaverMode,
    screenMode: screenMode ?? this.screenMode,
    turnWarningThreshold: turnWarningThreshold ?? this.turnWarningThreshold,
    diceMode: diceMode ?? this.diceMode,
  );

  Map<String, dynamic> toJson() => {
    'batterySaverMode': batterySaverMode,
    'screenMode': screenMode.id,
    'turnWarningSeconds': turnWarningThreshold.inSeconds,
    'diceMode': diceMode.id,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    batterySaverMode: json['batterySaverMode'] as bool? ?? false,
    screenMode: _readScreenMode(json),
    turnWarningThreshold: Duration(
      seconds: (json['turnWarningSeconds'] as num?)?.toInt() ?? 0,
    ),
    diceMode: DiceMode.fromId(json['diceMode'] as String?),
  );
}

/// Reads the screen mode, migrating the legacy boolean `keepScreenAwake` flag
/// that predates the [ScreenMode] enum.
ScreenMode _readScreenMode(Map<String, dynamic> json) {
  if (json['screenMode'] != null) {
    return ScreenMode.fromId(json['screenMode'] as String?);
  }
  if (json['keepScreenAwake'] == true) return ScreenMode.keepAwake;
  return ScreenMode.normal;
}
