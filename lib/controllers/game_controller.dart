import 'dart:math';

import 'package:flutter/widgets.dart';

import '../models/app_settings.dart';
import '../models/dice_mode.dart';
import '../models/game_record.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/screen_mode.dart';
import '../utils/dice.dart';
import '../services/game_history_service.dart';
import '../services/game_storage_service.dart';
import '../services/live_play_service.dart';
import '../services/screen_wake_service.dart';
import 'game_engine.dart';

/// Owns all game state and coordinates the side effects (persistence, wakelock,
/// lock-screen surface) around the pure transitions in [GameEngine].
///
/// Design notes:
/// * Time is never counted by a running counter. Elapsed is always derived from
///   [GameState.currentTurnStartTime] and the current clock, so it stays correct
///   through lag, pauses, and app backgrounding. The per-second UI refresh lives
///   in the game screen — this controller holds no [Timer], which also keeps it
///   trivially unit-testable.
/// * The wall clock is injected ([clock]) so tests can advance time
///   deterministically.
/// * All state transitions go through [GameEngine] (pure), so the exact same
///   rules apply whether a turn is advanced in-app or from a lock-screen control
///   (the latter are replayed via [_reconcileLockedPlay]).
class GameController extends ChangeNotifier with WidgetsBindingObserver {
  GameController({
    GameStorageService? storage,
    ScreenWakeService? wake,
    LivePlayService? livePlay,
    GameHistoryService? history,
    DateTime Function()? clock,
  }) : _storage = storage ?? GameStorageService(),
       _wake = wake ?? ScreenWakeService(),
       _livePlay = livePlay ?? LivePlayService(),
       _history = history ?? GameHistoryService(),
       _now = clock ?? DateTime.now;

  final GameStorageService _storage;
  final ScreenWakeService _wake;
  final LivePlayService _livePlay;
  final GameHistoryService _history;
  final DateTime Function() _now;

  GameState? _game;
  AppSettings _settings = const AppSettings();
  bool _foreground = true;
  bool _livePlayRunning = false;
  GameRecord? _lastResult;

  // --- Getters -------------------------------------------------------------

  GameState? get game => _game;
  AppSettings get settings => _settings;

  /// The most recently finished game, as shown on the results screen. Also
  /// archived to history the moment the game ends.
  GameRecord? get lastResult => _lastResult;

  /// True when a game exists and has not been ended.
  bool get hasActiveGame => _game != null && !_game!.isFinished;
  bool get isPaused => _game?.isPaused ?? false;
  bool get canUndo =>
      (_game?.undoStack.isNotEmpty ?? false) && !(_game?.isFinished ?? true);

  Player? get currentPlayer => _game?.currentPlayer;
  Player? get nextPlayer => _game?.nextPlayer;

  Duration get currentTurnElapsed =>
      _game?.currentTurnElapsed(_now()) ?? Duration.zero;
  Duration get currentPlayerTotal =>
      _game?.currentPlayerTotal(_now()) ?? Duration.zero;

  /// Effective flags: a live game's own copy wins, otherwise the saved settings.
  bool get batterySaverMode =>
      _game?.batterySaverMode ?? _settings.batterySaverMode;
  ScreenMode get screenMode => _game?.screenMode ?? _settings.screenMode;
  bool get keepScreenAwake => screenMode == ScreenMode.keepAwake;
  bool get lockedPlay => screenMode == ScreenMode.lockedPlay;
  Duration get turnWarningThreshold =>
      _game?.turnWarningThreshold ?? _settings.turnWarningThreshold;

  /// Whether the in-progress turn has passed the soft warning threshold.
  bool get isCurrentTurnOverLimit =>
      _game?.isCurrentTurnOverLimit(_now()) ?? false;

  DiceMode get diceMode => _game?.diceMode ?? _settings.diceMode;
  bool get diceEnabled => diceMode.isOn;

  /// The roll logged for the turn in progress, or null if the active player
  /// hasn't rolled yet — which is exactly what decides whether the next number
  /// tap logs a roll or passes the turn. See [tapRoll].
  int? get currentTurnRoll => _game?.currentTurnRoll;

  /// The distribution so far, for the in-game strip.
  DiceStats get liveDiceStats => DiceStats.from(_game?.rollTotals ?? const []);

  // --- Init & lifecycle ----------------------------------------------------

  /// Loads settings and any resumable game. Call once at startup.
  Future<void> init() async {
    _settings = await _storage.loadSettings() ?? const AppSettings();
    final loaded = await _storage.loadGame();
    if (loaded != null && !loaded.isFinished && loaded.players.length >= 2) {
      _game = loaded;
    }
    // Older builds saved Locked play without verifying that Android actually
    // granted notification access. Revalidate once and fall back cleanly.
    if ((_settings.screenMode == ScreenMode.lockedPlay || lockedPlay) &&
        !await _livePlay.requestPermissions()) {
      _settings = _settings.copyWith(screenMode: ScreenMode.normal);
      if (_game?.screenMode == ScreenMode.lockedPlay) {
        _game = _game!.copyWith(screenMode: ScreenMode.normal);
      }
      await _storage.saveSettings(_settings);
      await _persist();
    }
    // The lock-screen service may have kept running while the app was dead;
    // fold in any turns taken there, then reconcile the surface.
    await _reconcileLockedPlay();
    _syncLockedPlay(forceStopIfIdle: true);
    _syncWakelock();
    notifyListeners();
  }

  void _setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    _syncWakelock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _setForeground(true);
        _onResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _setForeground(false);
        _persist();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _setForeground(false);
        _persist();
    }
  }

  Future<void> _onResumed() async {
    await _reconcileLockedPlay();
    _syncLockedPlay();
    notifyListeners();
  }

  /// Folds any lock-screen actions into the authoritative game state by
  /// replaying them deterministically through [GameEngine].
  Future<void> _reconcileLockedPlay() async {
    final actions = await _livePlay.drainActions();
    final g = _game;
    if (actions.isEmpty || g == null || g.isFinished) return;
    var state = g;
    for (final a in actions) {
      state = switch (a.type) {
        LiveActionType.next => GameEngine.nextTurn(state, a.timestamp),
        LiveActionType.pause => GameEngine.pause(state, a.timestamp),
        LiveActionType.resume => GameEngine.resume(state, a.timestamp),
      };
    }
    _game = state;
    await _persist();
  }

  // --- Starting games ------------------------------------------------------

  /// Begins a new game. Resets every player's statistics. Requires >= 2 players.
  Future<void> startGame({
    required List<Player> players,
    String gameName = '',
    bool randomizeFirst = false,
  }) async {
    assert(players.length >= 2, 'A game needs at least 2 players');
    final now = _now();
    // resetForNewGame (not copyWith) so last game's score is cleared too.
    final fresh = players.map((p) => p.resetForNewGame()).toList();
    final firstIndex = randomizeFirst ? Random().nextInt(fresh.length) : 0;
    _game = GameState(
      players: fresh,
      currentPlayerIndex: firstIndex,
      currentTurnStartTime: now,
      isPaused: false,
      pausedAt: null,
      turnHistory: const [],
      undoStack: const [],
      gameName: gameName.trim(),
      startedAt: now,
      endedAt: null,
      batterySaverMode: _settings.batterySaverMode,
      screenMode: _settings.screenMode,
      turnWarningThreshold: _settings.turnWarningThreshold,
      diceMode: _settings.diceMode,
    );
    _syncWakelock();
    await _persist();
    _syncLockedPlay();
    notifyListeners();
  }

  /// Starts a fresh game with the same roster and name (a rematch).
  Future<void> rematchSamePlayers({bool randomizeFirst = false}) async {
    final g = _game;
    if (g == null) return;
    await startGame(
      players: g.players,
      gameName: g.gameName,
      randomizeFirst: randomizeFirst,
    );
  }

  // --- In-game actions (delegate to GameEngine) ----------------------------

  void nextTurn() => _applyIfActive(GameEngine.nextTurn);

  void skipPlayer() => _applyIfActive(GameEngine.skipPlayer);

  /// Hands the turn to [playerIndex] instead of the next player in order (the
  /// "pass turn to…" picker). Passing to the current player starts them a fresh
  /// turn, which is what Catan's snake-order setup needs.
  void passTurnTo(int playerIndex) =>
      _applyIfActive((g, now) => GameEngine.passTurnTo(g, playerIndex, now));

  /// A number was tapped on the dice strip. One rule decides what it means:
  /// the roll always belongs to the player whose turn is *starting*, so if the
  /// active player hasn't rolled yet this logs it for them, and otherwise it
  /// passes the turn and logs it for whoever is next.
  ///
  /// That also makes the strip self-healing: pass a turn without a roll (the
  /// setup phase, or a missed tap) and the next number simply attaches to the
  /// player who is already up.
  void tapRoll(int total) {
    final g = _game;
    if (g == null || g.isFinished || !g.diceMode.isOn) return;
    _applyIfActive(
      (state, now) => state.currentTurnRolled
          ? GameEngine.nextTurn(state, now, roll: total)
          : GameEngine.logRoll(state, total, now),
    );
  }

  /// Corrects the in-progress turn's roll ([total] null removes it).
  void amendRoll(int? total) {
    final g = _game;
    if (g == null || g.isFinished) return;
    _game = GameEngine.amendCurrentRoll(g, total);
    _persist();
    notifyListeners();
  }

  void undo() {
    final g = _game;
    if (g == null || g.isFinished || g.undoStack.isEmpty) return;
    _game = GameEngine.undo(g, _now());
    _persist();
    _syncLockedPlay();
    notifyListeners();
  }

  void togglePause() => isPaused ? resume() : pause();

  void pause() {
    final g = _game;
    if (g == null || g.isFinished || g.isPaused) return;
    _game = GameEngine.pause(g, _now());
    _syncWakelock();
    _persist();
    _syncLockedPlay();
    notifyListeners();
  }

  void resume() {
    final g = _game;
    if (g == null || g.isFinished || !g.isPaused) return;
    _game = GameEngine.resume(g, _now());
    _syncWakelock();
    _persist();
    _syncLockedPlay();
    notifyListeners();
  }

  /// Ends the game, finalizing the in-progress turn and freezing statistics.
  Future<void> endGame() async {
    final g = _game;
    if (g == null || g.isFinished) return;
    final finished = GameEngine.endGame(g, _now());
    _game = finished;
    _lastResult = GameRecord.fromGameState(finished);
    _syncWakelock();
    _syncLockedPlay(); // game finished -> tears down the lock-screen surface
    // The game is over; don't auto-resume it next launch. The finished state is
    // kept in memory for the summary screen.
    await _storage.clearGame();
    // Archive immediately, so a finished game is logged even if the player
    // skips scoring or the app dies on the results screen.
    await _history.save(_lastResult!);
    notifyListeners();
  }

  /// Records final scores on the just-finished game, keyed by player id (a null
  /// value clears that player's score), and updates its history entry in place.
  Future<void> setScores(Map<String, int?> scores) async {
    final result = _lastResult;
    if (result == null) return;
    final updated = result.withScores(scores);
    _lastResult = updated;
    // Keep the finished in-memory state in step, so a rematch starts from the
    // same roster the results screen is showing.
    final g = _game;
    if (g != null && g.isFinished) {
      _game = g.copyWith(players: updated.players);
    }
    await _history.save(updated);
    notifyListeners();
  }

  // --- History -------------------------------------------------------------

  /// Past games, newest first. Loaded on demand to keep startup light.
  Future<List<GameRecord>> loadHistory() => _history.list();

  Future<void> deleteHistoryEntry(String id) => _history.delete(id);

  /// Puts a deleted game back (the Undo action). It keeps its id and
  /// timestamps, so it returns to its original place in the log.
  Future<void> restoreHistoryEntry(GameRecord record) => _history.save(record);

  Future<void> clearHistory() => _history.clearAll();

  /// Throws away the active game and returns to a clean slate.
  Future<void> discardGame() async {
    _game = null;
    _syncWakelock();
    _syncLockedPlay(); // no active game -> tears down the lock-screen surface
    await _storage.clearGame();
    notifyListeners();
  }

  // --- Settings ------------------------------------------------------------

  Future<void> setBatterySaver(bool value) async {
    _settings = _settings.copyWith(batterySaverMode: value);
    if (hasActiveGame) _game = _game!.copyWith(batterySaverMode: value);
    await _storage.saveSettings(_settings);
    await _persist();
    notifyListeners();
  }

  /// Applies a screen mode. Returns false when Locked play is unavailable or
  /// notification permission was denied, leaving the existing mode unchanged.
  Future<bool> setScreenMode(ScreenMode value) async {
    if (value == ScreenMode.lockedPlay &&
        !await _livePlay.requestPermissions()) {
      return false;
    }
    _settings = _settings.copyWith(screenMode: value);
    if (hasActiveGame) _game = _game!.copyWith(screenMode: value);
    await _storage.saveSettings(_settings);
    _syncWakelock();
    await _persist();
    _syncLockedPlay();
    notifyListeners();
    return true;
  }

  Future<void> openNotificationSettings() =>
      _livePlay.openNotificationSettings();

  Future<void> setTurnWarning(Duration value) async {
    _settings = _settings.copyWith(turnWarningThreshold: value);
    if (hasActiveGame) _game = _game!.copyWith(turnWarningThreshold: value);
    await _storage.saveSettings(_settings);
    await _persist();
    notifyListeners();
  }

  /// Turns dice tracking on or off. Applies to the running game too, so it can
  /// be switched mid-game; rolls already logged are kept either way.
  Future<void> setDiceMode(DiceMode value) async {
    _settings = _settings.copyWith(diceMode: value);
    if (hasActiveGame) _game = _game!.copyWith(diceMode: value);
    await _storage.saveSettings(_settings);
    await _persist();
    notifyListeners();
  }

  // --- Internals -----------------------------------------------------------

  /// Applies a pure [GameEngine] transition to the active game, persists, and
  /// notifies. Used by the simple advance/skip actions.
  void _applyIfActive(GameState Function(GameState, DateTime) transition) {
    final g = _game;
    if (g == null || g.isFinished) return;
    _game = transition(g, _now());
    _persist();
    _syncLockedPlay();
    notifyListeners();
  }

  Future<void> _persist() async {
    final g = _game;
    if (g != null && !g.isFinished) {
      await _storage.saveGame(g);
    }
  }

  void _syncWakelock() {
    final shouldStayAwake =
        hasActiveGame && !isPaused && _foreground && keepScreenAwake;
    _wake.setEnabled(shouldStayAwake);
  }

  /// Starts / updates / stops the lock-screen surface to match the current
  /// state. The service is always *started* while the app is foreground
  /// (Android forbids starting a foreground service from the background), and
  /// merely updated thereafter.
  void _syncLockedPlay({bool forceStopIfIdle = false}) {
    final shouldRun = lockedPlay && hasActiveGame;
    if (shouldRun) {
      final snapshot = LivePlaySnapshot.fromGame(_game!);
      if (_livePlayRunning) {
        _livePlay.update(snapshot);
      } else {
        _livePlay.start(snapshot);
        _livePlayRunning = true;
      }
    } else if (_livePlayRunning || forceStopIfIdle) {
      _livePlay.stop();
      _livePlayRunning = false;
    }
  }

  @override
  void dispose() {
    _wake.setEnabled(false);
    super.dispose();
  }
}
