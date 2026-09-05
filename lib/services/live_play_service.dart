import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/game_state.dart';

/// A snapshot of just what the lock-screen surface needs to render and to
/// transition itself while the app is backgrounded.
class LivePlaySnapshot {
  const LivePlaySnapshot({
    required this.gameName,
    required this.playerNames,
    required this.playerColors,
    required this.currentIndex,
    required this.turnStartMillis,
    required this.isPaused,
    required this.pausedAtMillis,
  });

  final String gameName;
  final List<String> playerNames;
  final List<int> playerColors; // ARGB
  final int currentIndex;
  final int turnStartMillis;
  final bool isPaused;
  final int pausedAtMillis;

  factory LivePlaySnapshot.fromGame(GameState g) => LivePlaySnapshot(
    gameName: g.gameName,
    playerNames: [for (final p in g.players) p.name],
    playerColors: [for (final p in g.players) p.colorValue],
    currentIndex: g.currentPlayerIndex,
    turnStartMillis: g.currentTurnStartTime.millisecondsSinceEpoch,
    isPaused: g.isPaused,
    pausedAtMillis: g.pausedAt?.millisecondsSinceEpoch ?? 0,
  );

  String toJsonString() => jsonEncode({
    'gameName': gameName,
    'players': [
      for (var i = 0; i < playerNames.length; i++)
        {'name': playerNames[i], 'color': playerColors[i]},
    ],
    'currentIndex': currentIndex,
    'turnStartMillis': turnStartMillis,
    'isPaused': isPaused,
    'pausedAtMillis': pausedAtMillis,
  });
}

enum LiveActionType { next, pause, resume }

/// An action the user triggered from the lock-screen surface, to be replayed
/// authoritatively through [GameEngine] when the app comes back.
class LiveAction {
  const LiveAction(this.type, this.timestamp);

  final LiveActionType type;
  final DateTime timestamp;

  static LiveAction? fromJson(Map<String, dynamic> j) {
    final ms = (j['timestampMillis'] as num?)?.toInt();
    if (ms == null) return null;
    final type = switch (j['type']) {
      'next' => LiveActionType.next,
      'pause' => LiveActionType.pause,
      'resume' => LiveActionType.resume,
      _ => null,
    };
    if (type == null) return null;
    return LiveAction(type, DateTime.fromMillisecondsSinceEpoch(ms));
  }
}

/// Bridges to the platform lock-screen surface — an Android foreground-service
/// notification or an iOS Live Activity.
///
/// Every call is guarded, so the app behaves normally wherever the surface is
/// unavailable: other platforms, unit tests, or when the user has denied the
/// notification permission. The native side owns display + immediate response
/// while backgrounded; Dart stays authoritative by draining [drainActions] and
/// replaying them through [GameEngine].
class LivePlayService {
  static const MethodChannel _channel = MethodChannel('turntimer/locked_play');

  Future<void> start(LivePlaySnapshot snapshot) =>
      _invoke('start', snapshot.toJsonString());

  Future<void> update(LivePlaySnapshot snapshot) =>
      _invoke('update', snapshot.toJsonString());

  Future<void> stop() => _invoke('stop', null);

  /// Requests permission to show the lock-screen controls and reports whether
  /// Android can currently post notifications. Unsupported platforms return
  /// false so callers do not silently enable a non-functional mode.
  Future<bool> requestPermissions() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNotificationSettings() =>
      _invoke('openNotificationSettings', null);

  /// Returns and clears the actions the user triggered from the lock screen.
  Future<List<LiveAction>> drainActions() async {
    try {
      final raw = await _channel.invokeMethod<String>('drainActions');
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => LiveAction.fromJson(Map<String, dynamic>.from(e as Map)))
          .whereType<LiveAction>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _invoke(String method, Object? arg) async {
    try {
      await _channel.invokeMethod(method, arg);
    } catch (_) {
      // Unsupported platform / not implemented / permission denied — ignore.
    }
  }
}
