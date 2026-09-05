import 'package:audioplayers/audioplayers.dart';

/// Plays the short turn-warning chime (`assets/sounds/turn_warning.wav`).
///
/// Wrapped like [ScreenWakeService] so callers can fire-and-forget. The player
/// is created lazily on first [play] and, if anything fails (no audio output,
/// plugin unavailable in unit tests, etc.), the service disables itself instead
/// of throwing or retrying.
class WarningSoundService {
  AudioPlayer? _player;
  bool _failed = false;

  Future<void> play() async {
    if (_failed) return;
    try {
      var player = _player;
      if (player == null) {
        player = AudioPlayer(playerId: 'turn_warning');
        await player.setReleaseMode(ReleaseMode.stop);
        _player = player;
      }
      await player.stop();
      await player.play(AssetSource('sounds/turn_warning.wav'), volume: 0.9);
    } catch (_) {
      _failed = true; // Don't keep retrying where audio isn't available.
    }
  }

  Future<void> dispose() async {
    try {
      await _player?.dispose();
    } catch (_) {
      // Already released — ignore.
    }
  }
}
