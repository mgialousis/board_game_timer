import '../models/dice_roll.dart';
import '../models/game_state.dart';
import '../models/turn_record.dart';
import '../models/undo_entry.dart';
import '../utils/dice.dart';

/// Pure, side-effect-free game-state transitions.
///
/// Shared by [GameController] (foreground UI) and the background handlers used
/// for locked-screen play, so a turn advanced from a notification / Live
/// Activity applies *exactly* the same rules as one advanced in-app. Every
/// method takes the current wall clock, so it is deterministic and isolate-safe
/// (no plugins, no Timer, no I/O).
class GameEngine {
  GameEngine._();

  static const int maxUndo = 100;

  /// A [GameState.currentTurnStartTime] such that the current turn's elapsed
  /// equals [elapsed], honoring whether [g] is paused.
  static DateTime startForElapsed(GameState g, Duration elapsed, DateTime now) {
    final reference = g.isPaused ? (g.pausedAt ?? now) : now;
    return reference.subtract(elapsed);
  }

  static List<UndoEntry> _pushUndo(List<UndoEntry> stack, UndoEntry entry) {
    final next = [...stack, entry];
    if (next.length > maxUndo) next.removeAt(0);
    return next;
  }

  static List<DiceRoll> _dropLastRoll(List<DiceRoll> rolls) =>
      rolls.isEmpty ? rolls : rolls.sublist(0, rolls.length - 1);

  /// Recomputes every player's accumulated/turnCount/longest from history so
  /// per-player stats stay consistent across undo and skip.
  static GameState withRecomputedStats(GameState g) {
    final totals = <String, Duration>{
      for (final p in g.players) p.id: Duration.zero,
    };
    final counts = <String, int>{for (final p in g.players) p.id: 0};
    final longest = <String, Duration>{
      for (final p in g.players) p.id: Duration.zero,
    };
    for (final r in g.turnHistory) {
      if (!totals.containsKey(r.playerId)) continue;
      totals[r.playerId] = totals[r.playerId]! + r.duration;
      counts[r.playerId] = counts[r.playerId]! + 1;
      if (r.duration > longest[r.playerId]!) longest[r.playerId] = r.duration;
    }
    final players = g.players
        .map(
          (p) => p.copyWith(
            accumulatedDuration: totals[p.id],
            turnCount: counts[p.id],
            longestTurn: longest[p.id],
          ),
        )
        .toList();
    return g.copyWith(players: players);
  }

  // --- Turn changes --------------------------------------------------------

  /// Ends the current player's turn (recording it) and advances to the next.
  ///
  /// [roll] is the dice total the *incoming* player just rolled, if the turn
  /// was passed by tapping a number. In Catan the first thing you do on your
  /// turn is roll, so the roll belongs to the turn that is starting.
  static GameState nextTurn(GameState g, DateTime now, {int? roll}) {
    if (g.isFinished) return g;
    return _advanceTo(g, g.nextPlayerIndex, now, roll: roll);
  }

  /// Ends the current turn and hands over to [targetIndex] instead of the next
  /// player in order — used to follow an out-of-order sequence such as Catan's
  /// snake-order setup phase. Passing to the *current* player is allowed and
  /// simply records their turn and starts them a fresh one (in the snake round
  /// the last player places twice in a row).
  static GameState passTurnTo(
    GameState g,
    int targetIndex,
    DateTime now, {
    int? roll,
  }) {
    if (g.isFinished) return g;
    if (targetIndex < 0 || targetIndex >= g.players.length) return g;
    return _advanceTo(g, targetIndex, now, roll: roll);
  }

  static GameState _advanceTo(
    GameState g,
    int targetIndex,
    DateTime now, {
    int? roll,
  }) {
    assert(roll == null || isValidRoll(roll), 'roll out of range: $roll');
    // A roll can only be logged by a game that is tracking dice.
    final logged = (g.diceMode.isOn && roll != null && isValidRoll(roll))
        ? roll
        : null;
    final elapsed = g.currentTurnElapsed(now);
    final record = TurnRecord(
      playerId: g.currentPlayer.id,
      startTime: g.currentTurnStartTime,
      endTime: g.isPaused ? (g.pausedAt ?? now) : now,
      duration: elapsed,
    );
    final undo = UndoEntry(
      kind: UndoKind.advance,
      previousPlayerIndex: g.currentPlayerIndex,
      previousElapsed: elapsed,
      recordedRoll: logged,
      previousTurnRolled: g.currentTurnRolled,
    );
    return withRecomputedStats(
      g.copyWith(
        currentPlayerIndex: targetIndex,
        currentTurnStartTime: startForElapsed(g, Duration.zero, now),
        turnHistory: [...g.turnHistory, record],
        undoStack: _pushUndo(g.undoStack, undo),
        rolls: logged == null
            ? g.rolls
            : [
                ...g.rolls,
                DiceRoll(playerId: g.players[targetIndex].id, total: logged),
              ],
        currentTurnRolled: logged != null,
      ),
    );
  }

  /// Skips the current player: discards their in-progress time (no turn is
  /// recorded) and advances to the next.
  ///
  /// Any roll already logged for that turn is kept — the dice were physically
  /// rolled, so the distribution should know about them.
  static GameState skipPlayer(GameState g, DateTime now) {
    if (g.isFinished) return g;
    final undo = UndoEntry(
      kind: UndoKind.skip,
      previousPlayerIndex: g.currentPlayerIndex,
      previousElapsed: g.currentTurnElapsed(now),
      previousTurnRolled: g.currentTurnRolled,
    );
    return g.copyWith(
      currentPlayerIndex: g.nextPlayerIndex,
      currentTurnStartTime: startForElapsed(g, Duration.zero, now),
      undoStack: _pushUndo(g.undoStack, undo),
      currentTurnRolled: false,
    );
  }

  // --- Dice ----------------------------------------------------------------

  /// Logs [total] for the player whose turn is *already* in progress, without
  /// changing turn. This is what happens on the first roll of a game (and after
  /// a turn was passed without one) — the roller is already the active player.
  static GameState logRoll(GameState g, int total, DateTime now) {
    if (g.isFinished || !g.diceMode.isOn) return g;
    if (!isValidRoll(total) || g.currentTurnRolled) return g;
    final undo = UndoEntry(
      kind: UndoKind.roll,
      previousPlayerIndex: g.currentPlayerIndex,
      previousElapsed: g.currentTurnElapsed(now),
      recordedRoll: total,
      previousTurnRolled: false,
    );
    return g.copyWith(
      rolls: [
        ...g.rolls,
        DiceRoll(playerId: g.currentPlayer.id, total: total),
      ],
      undoStack: _pushUndo(g.undoStack, undo),
      currentTurnRolled: true,
    );
  }

  /// Corrects the in-progress turn's roll: [total] replaces it, null removes
  /// it. This is the mistyped-number path, so it does not push its own undo
  /// step — instead it keeps the *existing* one honest, so a later Undo still
  /// drops exactly the right number.
  static GameState amendCurrentRoll(GameState g, int? total) {
    if (g.isFinished || !g.currentTurnRolled || g.rolls.isEmpty) return g;
    if (total != null && !isValidRoll(total)) return g;

    var stack = g.undoStack;
    if (stack.isNotEmpty && stack.last.recordedRoll != null) {
      final last = stack.last;
      final head = stack.sublist(0, stack.length - 1);
      stack = switch ((total, last.kind)) {
        // The roll is gone and the step logged nothing else: drop the step.
        (null, UndoKind.roll) => head,
        // The turn change still happened; it just no longer carries a roll.
        (null, _) => [...head, _withRoll(last, null)],
        (final t, _) => [...head, _withRoll(last, t)],
      };
    }

    final head = _dropLastRoll(g.rolls);
    return g.copyWith(
      rolls: total == null
          ? head
          : [...head, DiceRoll(playerId: g.rolls.last.playerId, total: total)],
      undoStack: stack,
      currentTurnRolled: total != null,
    );
  }

  static UndoEntry _withRoll(UndoEntry e, int? roll) => UndoEntry(
    kind: e.kind,
    previousPlayerIndex: e.previousPlayerIndex,
    previousElapsed: e.previousElapsed,
    recordedRoll: roll,
    previousTurnRolled: e.previousTurnRolled,
  );

  // --- Undo / pause / end --------------------------------------------------

  /// Reverts the most recent advance, skip or logged roll.
  static GameState undo(GameState g, DateTime now) {
    if (g.isFinished || g.undoStack.isEmpty) return g;
    final stack = [...g.undoStack];
    final entry = stack.removeLast();
    final rolls = entry.recordedRoll != null ? _dropLastRoll(g.rolls) : g.rolls;

    // A logged roll changed nothing but the dice, so undoing it must leave the
    // clock and the active player exactly where they are.
    if (entry.kind == UndoKind.roll) {
      return g.copyWith(
        undoStack: stack,
        rolls: rolls,
        currentTurnRolled: entry.previousTurnRolled,
      );
    }

    var history = g.turnHistory;
    if (entry.kind == UndoKind.advance && history.isNotEmpty) {
      history = history.sublist(0, history.length - 1);
    }
    return withRecomputedStats(
      g.copyWith(
        currentPlayerIndex: entry.previousPlayerIndex,
        currentTurnStartTime: startForElapsed(g, entry.previousElapsed, now),
        turnHistory: history,
        undoStack: stack,
        rolls: rolls,
        currentTurnRolled: entry.previousTurnRolled,
      ),
    );
  }

  static GameState pause(GameState g, DateTime now) {
    if (g.isFinished || g.isPaused) return g;
    return g.copyWith(isPaused: true, pausedAt: now);
  }

  static GameState resume(GameState g, DateTime now) {
    if (g.isFinished || !g.isPaused) return g;
    final gap = now.difference(g.pausedAt ?? now);
    return g.copyWith(
      isPaused: false,
      pausedAt: null,
      // Shift the start forward by the paused gap so elapsed continues smoothly.
      currentTurnStartTime: g.currentTurnStartTime.add(
        gap.isNegative ? Duration.zero : gap,
      ),
    );
  }

  /// Ends the game, finalizing the in-progress turn (only if it has any time)
  /// and freezing statistics for the summary screen.
  static GameState endGame(GameState g, DateTime now) {
    if (g.isFinished) return g;
    final elapsed = g.currentTurnElapsed(now);
    var history = g.turnHistory;
    if (elapsed > Duration.zero) {
      history = [
        ...history,
        TurnRecord(
          playerId: g.currentPlayer.id,
          startTime: g.currentTurnStartTime,
          endTime: g.isPaused ? (g.pausedAt ?? now) : now,
          duration: elapsed,
        ),
      ];
    }
    return withRecomputedStats(
      g.copyWith(
        turnHistory: history,
        undoStack: const [],
        isPaused: false,
        pausedAt: null,
        endedAt: now,
      ),
    );
  }
}
