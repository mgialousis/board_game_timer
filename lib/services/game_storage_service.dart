import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/game_state.dart';

/// Persists the single active game and the user settings to
/// shared_preferences.
///
/// There is only ever one in-progress game, so the entire [GameState] is stored
/// as one JSON string under one key — a key/value store is the simplest correct
/// choice here (no schema, no migrations, no DB). Loads are defensive: a corrupt
/// or invalid payload is discarded instead of crashing the app on launch.
class GameStorageService {
  // These legacy identifiers predate the TurnTimer name. Keep them stable so
  // app updates continue to restore existing games and settings.
  static const String _gameKey = 'turnpulse.active_game';
  static const String _settingsKey = 'turnpulse.settings';

  Future<void> saveGame(GameState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gameKey, jsonEncode(state.toJson()));
  }

  Future<GameState?> loadGame() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_gameKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final state = GameState.fromJson(json);
      // Reject anything that could not produce a playable game.
      if (state.players.length < 2) return null;
      if (state.currentPlayerIndex < 0 ||
          state.currentPlayerIndex >= state.players.length) {
        return null;
      }
      return state;
    } catch (_) {
      await prefs.remove(_gameKey);
      return null;
    }
  }

  Future<void> clearGame() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_gameKey);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<AppSettings?> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return null;
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
