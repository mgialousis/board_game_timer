import 'package:board_game_timer/controllers/game_engine.dart';
import 'package:board_game_timer/models/dice_mode.dart';
import 'package:board_game_timer/models/game_state.dart';
import 'package:board_game_timer/models/player.dart';
import 'package:board_game_timer/models/screen_mode.dart';
import 'package:flutter_test/flutter_test.dart';

GameState newGame(
  DateTime now, {
  int players = 2,
  DiceMode diceMode = DiceMode.off,
}) => GameState(
  players: [
    for (var i = 0; i < players; i++)
      Player(id: 'p$i', name: 'P${i + 1}', colorValue: 0xFF000000 + i),
  ],
  currentPlayerIndex: 0,
  currentTurnStartTime: now,
  isPaused: false,
  pausedAt: null,
  turnHistory: const [],
  undoStack: const [],
  gameName: '',
  startedAt: now,
  endedAt: null,
  batterySaverMode: false,
  screenMode: ScreenMode.normal,
  turnWarningThreshold: Duration.zero,
  diceMode: diceMode,
);

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  test('nextTurn records elapsed and advances circularly', () {
    var g = newGame(t0, players: 3);
    g = GameEngine.nextTurn(g, t0.add(const Duration(seconds: 5)));
    expect(g.currentPlayerIndex, 1);
    expect(g.players[0].accumulatedDuration, const Duration(seconds: 5));
    expect(g.players[0].turnCount, 1);
    expect(g.turnHistory.length, 1);
  });

  test('pause freezes, resume continues, no negative durations', () {
    var g = newGame(t0);
    g = GameEngine.pause(g, t0.add(const Duration(seconds: 3)));
    expect(
      g.currentTurnElapsed(t0.add(const Duration(seconds: 100))),
      const Duration(seconds: 3),
    );
    g = GameEngine.resume(g, t0.add(const Duration(seconds: 100)));
    expect(
      g.currentTurnElapsed(t0.add(const Duration(seconds: 102))),
      const Duration(seconds: 5),
    );
    expect(g.currentTurnElapsed(t0), Duration.zero); // clock backwards
  });

  test('undo reverts an advance and restores elapsed', () {
    var g = newGame(t0);
    g = GameEngine.nextTurn(g, t0.add(const Duration(seconds: 5)));
    final undoAt = t0.add(const Duration(seconds: 9));
    g = GameEngine.undo(g, undoAt);
    expect(g.currentPlayerIndex, 0);
    expect(g.currentTurnElapsed(undoAt), const Duration(seconds: 5));
    expect(g.turnHistory, isEmpty);
    expect(g.players[0].accumulatedDuration, Duration.zero);
  });

  test('endGame finalizes a non-zero turn but not a zero-length one', () {
    final done = GameEngine.endGame(
      newGame(t0),
      t0.add(const Duration(seconds: 5)),
    );
    expect(done.isFinished, isTrue);
    expect(done.players[0].accumulatedDuration, const Duration(seconds: 5));

    var g2 = newGame(t0);
    g2 = GameEngine.nextTurn(g2, t0.add(const Duration(seconds: 5)));
    final done2 = GameEngine.endGame(g2, t0.add(const Duration(seconds: 5)));
    expect(done2.players[1].turnCount, 0);
  });

  // --- Dice ----------------------------------------------------------------

  group('dice', () {
    GameState diceGame({int players = 4}) =>
        newGame(t0, players: players, diceMode: DiceMode.twoD6);

    test('the first roll of a game logs without changing turn', () {
      final at = t0.add(const Duration(seconds: 4));
      final g = GameEngine.logRoll(diceGame(), 8, at);

      expect(g.currentPlayerIndex, 0, reason: 'still P1s turn');
      expect(g.currentTurnRolled, isTrue);
      expect(g.currentTurnRoll, 8);
      expect(g.rolls.single.playerId, 'p0');
      expect(g.turnHistory, isEmpty);
      // The clock keeps running for the player who rolled.
      expect(g.currentTurnElapsed(at), const Duration(seconds: 4));
    });

    test('a roll passed with the turn belongs to the incoming player', () {
      var g = GameEngine.logRoll(diceGame(), 8, t0);
      g = GameEngine.nextTurn(g, t0.add(const Duration(seconds: 30)), roll: 5);

      expect(g.currentPlayerIndex, 1);
      expect(g.rolls.map((r) => r.total), [8, 5]);
      expect(g.rolls.last.playerId, 'p1', reason: 'P2 rolled the 5');
      expect(g.currentTurnRoll, 5);
      expect(g.players[0].accumulatedDuration, const Duration(seconds: 30));
    });

    test('logRoll is ignored once the turn already has a roll', () {
      var g = GameEngine.logRoll(diceGame(), 8, t0);
      g = GameEngine.logRoll(g, 4, t0.add(const Duration(seconds: 1)));
      expect(g.rolls.single.total, 8);
    });

    test('a turn passed without a roll records nothing, and self-heals', () {
      // The setup phase: pass turns with no dice at all.
      var g = diceGame();
      for (var i = 0; i < 8; i++) {
        g = GameEngine.nextTurn(g, t0.add(Duration(seconds: 10 * (i + 1))));
      }
      expect(g.rolls, isEmpty);
      expect(g.currentTurnRolled, isFalse);
      expect(g.currentPlayerIndex, 0, reason: 'two full rounds returns to P1');
      expect(g.players[0].turnCount, 2);

      // First roll of the main game attaches to whoever is already up.
      g = GameEngine.logRoll(g, 6, t0.add(const Duration(seconds: 90)));
      expect(g.rolls.single.playerId, 'p0');
      expect(g.currentPlayerIndex, 0);
    });

    test('dice are ignored entirely when the game is not tracking them', () {
      var g = GameEngine.logRoll(newGame(t0), 8, t0);
      expect(g.rolls, isEmpty);
      g = GameEngine.nextTurn(newGame(t0), t0, roll: 8);
      expect(g.rolls, isEmpty);
      expect(g.currentTurnRolled, isFalse);
    });

    test('out-of-range rolls are refused', () {
      final g = GameEngine.logRoll(diceGame(), 13, t0);
      expect(g.rolls, isEmpty);
    });

    group('undo', () {
      test('undoing a logged roll drops it and leaves the clock alone', () {
        var g = GameEngine.logRoll(diceGame(), 8, t0);
        final undoAt = t0.add(const Duration(seconds: 45));
        g = GameEngine.undo(g, undoAt);

        expect(g.rolls, isEmpty);
        expect(g.currentTurnRolled, isFalse);
        expect(g.currentPlayerIndex, 0);
        // The turn has been running for 45s and undo must not rewind it.
        expect(g.currentTurnElapsed(undoAt), const Duration(seconds: 45));
        expect(g.undoStack, isEmpty);
      });

      test('undoing an advance drops the roll it carried', () {
        var g = GameEngine.logRoll(diceGame(), 8, t0);
        g = GameEngine.nextTurn(
          g,
          t0.add(const Duration(seconds: 30)),
          roll: 5,
        );
        g = GameEngine.undo(g, t0.add(const Duration(seconds: 40)));

        expect(g.currentPlayerIndex, 0);
        expect(g.rolls.map((r) => r.total), [8]);
        expect(g.currentTurnRolled, isTrue, reason: 'P1 had rolled an 8');
        expect(g.currentTurnRoll, 8);
      });

      test('undoing a plain advance restores an unrolled turn', () {
        var g = diceGame();
        g = GameEngine.nextTurn(g, t0.add(const Duration(seconds: 10)));
        g = GameEngine.undo(g, t0.add(const Duration(seconds: 20)));
        expect(g.currentTurnRolled, isFalse);
        expect(g.rolls, isEmpty);
      });
    });

    test('skip keeps the roll but starts the next turn unrolled', () {
      var g = GameEngine.logRoll(diceGame(), 8, t0);
      g = GameEngine.skipPlayer(g, t0.add(const Duration(seconds: 10)));

      expect(g.rolls.single.total, 8, reason: 'the dice were really rolled');
      expect(g.currentTurnRolled, isFalse);
      expect(g.currentPlayerIndex, 1);

      // ...and undoing the skip restores P1 with their roll intact.
      g = GameEngine.undo(g, t0.add(const Duration(seconds: 12)));
      expect(g.currentPlayerIndex, 0);
      expect(g.currentTurnRolled, isTrue);
      expect(g.rolls.single.total, 8);
    });

    test('endGame keeps the in-progress turn roll', () {
      var g = GameEngine.logRoll(diceGame(), 11, t0);
      g = GameEngine.endGame(g, t0.add(const Duration(seconds: 20)));
      expect(g.rolls.single.total, 11);
    });

    group('correcting a mistyped roll', () {
      test('replacing keeps undo honest', () {
        var g = GameEngine.logRoll(diceGame(), 8, t0);
        g = GameEngine.amendCurrentRoll(g, 9);
        expect(g.rolls.single.total, 9);
        expect(g.rolls.single.playerId, 'p0');
        expect(g.currentTurnRolled, isTrue);

        // One undo still removes exactly one roll.
        g = GameEngine.undo(g, t0.add(const Duration(seconds: 5)));
        expect(g.rolls, isEmpty);
      });

      test('removing a logged roll also drops its undo step', () {
        var g = GameEngine.logRoll(diceGame(), 8, t0);
        g = GameEngine.amendCurrentRoll(g, null);
        expect(g.rolls, isEmpty);
        expect(g.currentTurnRolled, isFalse);
        expect(g.undoStack, isEmpty, reason: 'nothing left to undo');
      });

      test('removing a roll that came with a turn change keeps the turn', () {
        var g = GameEngine.logRoll(diceGame(), 8, t0);
        g = GameEngine.nextTurn(
          g,
          t0.add(const Duration(seconds: 30)),
          roll: 5,
        );
        g = GameEngine.amendCurrentRoll(g, null);

        expect(g.currentPlayerIndex, 1, reason: 'the turn still changed');
        expect(g.rolls.map((r) => r.total), [8]);
        expect(g.currentTurnRolled, isFalse);

        // Undo now reverts only the turn change - the 8 stays put.
        g = GameEngine.undo(g, t0.add(const Duration(seconds: 40)));
        expect(g.currentPlayerIndex, 0);
        expect(g.rolls.map((r) => r.total), [8]);
      });

      test('is a no-op when the turn has no roll', () {
        final g = diceGame();
        expect(GameEngine.amendCurrentRoll(g, 7).rolls, isEmpty);
      });
    });
  });

  // --- Passing the turn out of order ---------------------------------------

  group('passTurnTo', () {
    test('hands over to any player and records the turn', () {
      var g = newGame(t0, players: 4);
      g = GameEngine.passTurnTo(g, 3, t0.add(const Duration(seconds: 12)));

      expect(g.currentPlayerIndex, 3);
      expect(g.players[0].accumulatedDuration, const Duration(seconds: 12));
      expect(g.turnHistory.single.playerId, 'p0');
    });

    test('passing to the current player starts them a fresh turn', () {
      // Catan's snake round: the last player places twice in a row.
      var g = newGame(t0, players: 4);
      g = GameEngine.passTurnTo(g, 0, t0.add(const Duration(seconds: 12)));

      expect(g.currentPlayerIndex, 0);
      expect(g.players[0].turnCount, 1);
      expect(
        g.currentTurnElapsed(t0.add(const Duration(seconds: 12))),
        Duration.zero,
      );
    });

    test('undo reverts it like any other advance', () {
      var g = newGame(t0, players: 4);
      g = GameEngine.passTurnTo(g, 3, t0.add(const Duration(seconds: 12)));
      g = GameEngine.undo(g, t0.add(const Duration(seconds: 15)));

      expect(g.currentPlayerIndex, 0);
      expect(g.turnHistory, isEmpty);
      expect(
        g.currentTurnElapsed(t0.add(const Duration(seconds: 15))),
        const Duration(seconds: 12),
      );
    });

    test('an out-of-range index is refused', () {
      final g = newGame(t0, players: 4);
      expect(GameEngine.passTurnTo(g, 9, t0).currentPlayerIndex, 0);
      expect(GameEngine.passTurnTo(g, -1, t0).turnHistory, isEmpty);
    });

    test('carries a roll to the chosen player', () {
      var g = newGame(t0, players: 4, diceMode: DiceMode.twoD6);
      g = GameEngine.passTurnTo(
        g,
        2,
        t0.add(const Duration(seconds: 9)),
        roll: 6,
      );
      expect(g.rolls.single.playerId, 'p2');
      expect(g.currentTurnRoll, 6);
    });
  });
}
