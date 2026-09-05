import 'package:board_game_timer/controllers/game_controller.dart';
import 'package:board_game_timer/models/dice_mode.dart';
import 'package:board_game_timer/models/player.dart';
import 'package:board_game_timer/models/screen_mode.dart';
import 'package:board_game_timer/services/game_storage_service.dart';
import 'package:board_game_timer/services/screen_wake_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records calls but never touches the real plugin.
class FakeWake extends ScreenWakeService {
  bool enabled = false;
  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime clock;
  late FakeWake wake;
  late GameController controller;

  DateTime now() => clock;
  void advance(Duration d) => clock = clock.add(d);

  List<Player> roster([int n = 2]) => [
    for (var i = 0; i < n; i++)
      Player(id: 'p$i', name: 'P${i + 1}', colorValue: 0xFF000000 + i),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 1, 1, 12);
    wake = FakeWake();
    controller = GameController(
      storage: GameStorageService(),
      wake: wake,
      clock: now,
    );
  });

  group('starting a game', () {
    test('initializes at player 0 with zero elapsed', () async {
      await controller.startGame(players: roster());
      expect(controller.hasActiveGame, isTrue);
      expect(controller.currentPlayer!.id, 'p0');
      expect(controller.currentTurnElapsed, Duration.zero);
    });

    test('rejects fewer than 2 players', () {
      expect(
        () => controller.startGame(players: roster(1)),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('timing', () {
    test(
      'elapsed is derived from the clock (accurate after a long gap)',
      () async {
        await controller.startGame(players: roster());
        advance(const Duration(seconds: 5));
        expect(controller.currentTurnElapsed, const Duration(seconds: 5));
        // Simulate the app being backgrounded for a minute.
        advance(const Duration(minutes: 1));
        expect(controller.currentTurnElapsed, const Duration(seconds: 65));
      },
    );

    test(
      'never reports a negative duration if the clock goes backwards',
      () async {
        await controller.startGame(players: roster());
        advance(const Duration(seconds: -30));
        expect(controller.currentTurnElapsed, Duration.zero);
      },
    );
  });

  group('nextTurn', () {
    test('records the turn and advances in circular order', () async {
      await controller.startGame(players: roster(3));
      advance(const Duration(seconds: 5));
      controller.nextTurn();

      expect(controller.currentPlayer!.id, 'p1');
      expect(controller.currentTurnElapsed, Duration.zero);
      final p0 = controller.game!.players[0];
      expect(p0.accumulatedDuration, const Duration(seconds: 5));
      expect(p0.turnCount, 1);
      expect(p0.longestTurn, const Duration(seconds: 5));

      advance(const Duration(seconds: 3));
      controller.nextTurn(); // p1 -> p2
      advance(const Duration(seconds: 2));
      controller.nextTurn(); // p2 -> p0 (wrap around)
      expect(controller.currentPlayer!.id, 'p0');
    });
  });

  group('pause / resume', () {
    test('no time accumulates while paused, across multiple cycles', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 3));
      controller.pause();
      advance(const Duration(seconds: 100)); // ignored while paused
      expect(controller.currentTurnElapsed, const Duration(seconds: 3));

      controller.resume();
      advance(const Duration(seconds: 2));
      expect(controller.currentTurnElapsed, const Duration(seconds: 5));

      controller.pause();
      advance(const Duration(seconds: 50));
      controller.resume();
      advance(const Duration(seconds: 1));
      expect(controller.currentTurnElapsed, const Duration(seconds: 6));
    });

    test('pause does not keep the screen awake', () async {
      await controller.setScreenMode(ScreenMode.keepAwake);
      await controller.startGame(players: roster());
      expect(wake.enabled, isTrue);
      controller.pause();
      expect(wake.enabled, isFalse);
      controller.resume();
      expect(wake.enabled, isTrue);
    });
  });

  group('skip', () {
    test('discards in-progress time and records no turn', () async {
      await controller.startGame(players: roster(3));
      advance(const Duration(seconds: 8));
      controller.skipPlayer();

      expect(controller.currentPlayer!.id, 'p1');
      expect(controller.game!.turnHistory, isEmpty);
      expect(controller.game!.players[0].accumulatedDuration, Duration.zero);
      expect(controller.game!.players[0].turnCount, 0);
    });
  });

  group('undo', () {
    test('reverts an advance and lets the turn continue', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 5));
      controller.nextTurn(); // p0 -> p1, records p0 = 5s

      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(controller.currentPlayer!.id, 'p0');
      expect(controller.currentTurnElapsed, const Duration(seconds: 5));
      expect(controller.game!.turnHistory, isEmpty);
      expect(controller.game!.players[0].accumulatedDuration, Duration.zero);

      // The restored turn keeps counting from where it was.
      advance(const Duration(seconds: 2));
      controller.nextTurn();
      expect(
        controller.game!.players[0].accumulatedDuration,
        const Duration(seconds: 7),
      );
    });

    test('reverts a skip, restoring discarded time', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 4));
      controller.skipPlayer();
      controller.undo();

      expect(controller.currentPlayer!.id, 'p0');
      expect(controller.currentTurnElapsed, const Duration(seconds: 4));
      expect(controller.canUndo, isFalse);
    });

    test('undo while paused keeps elapsed frozen and pause state', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 5));
      controller.nextTurn(); // p0 -> p1
      controller.pause();
      controller.undo();

      expect(controller.isPaused, isTrue);
      expect(controller.currentPlayer!.id, 'p0');
      expect(controller.currentTurnElapsed, const Duration(seconds: 5));

      advance(const Duration(seconds: 30)); // still paused -> no change
      expect(controller.currentTurnElapsed, const Duration(seconds: 5));

      controller.resume();
      advance(const Duration(seconds: 2));
      expect(controller.currentTurnElapsed, const Duration(seconds: 7));
    });

    test('keeps statistics consistent through multiple undos', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 10));
      controller.nextTurn(); // p0=10
      advance(const Duration(seconds: 6));
      controller.nextTurn(); // p1=6
      advance(const Duration(seconds: 4));
      controller.nextTurn(); // p0 second turn = 4 (p0 total 14, count 2)

      expect(
        controller.game!.players[0].accumulatedDuration,
        const Duration(seconds: 14),
      );
      expect(controller.game!.players[0].turnCount, 2);
      expect(
        controller.game!.players[0].longestTurn,
        const Duration(seconds: 10),
      );

      controller.undo(); // remove p1's last turn record (the 4s one)
      expect(
        controller.game!.players[1].accumulatedDuration,
        const Duration(seconds: 6),
      );
      expect(controller.game!.players[0].turnCount, 1);
      expect(
        controller.game!.players[0].accumulatedDuration,
        const Duration(seconds: 10),
      );
    });
  });

  group('end game', () {
    test('finalizes the in-progress turn', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 5));
      await controller.endGame();

      expect(controller.hasActiveGame, isFalse);
      expect(controller.game!.isFinished, isTrue);
      expect(
        controller.game!.players[0].accumulatedDuration,
        const Duration(seconds: 5),
      );
      expect(controller.game!.players[0].turnCount, 1);
      expect(wake.enabled, isFalse);
    });

    test('does not record a phantom zero-length turn', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 5));
      controller.nextTurn(); // p0 -> p1, p1 starts at 0
      await controller.endGame(); // p1 has 0 elapsed

      expect(controller.game!.players[0].turnCount, 1);
      expect(controller.game!.players[1].turnCount, 0);
    });

    test('finalizes correctly even when paused', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 7));
      controller.pause();
      advance(const Duration(seconds: 100));
      await controller.endGame();
      expect(
        controller.game!.players[0].accumulatedDuration,
        const Duration(seconds: 7),
      );
    });
  });

  group('persistence', () {
    test('a fresh controller resumes the saved game', () async {
      await controller.startGame(players: roster(), gameName: 'Chess');
      advance(const Duration(seconds: 5));
      controller.nextTurn();

      final resumed = GameController(
        storage: GameStorageService(),
        wake: FakeWake(),
        clock: now,
      );
      await resumed.init();

      expect(resumed.hasActiveGame, isTrue);
      expect(resumed.game!.gameName, 'Chess');
      expect(resumed.currentPlayer!.id, 'p1');
      expect(
        resumed.game!.players[0].accumulatedDuration,
        const Duration(seconds: 5),
      );
    });

    test('ended games are not resumed', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 5));
      await controller.endGame();

      final resumed = GameController(
        storage: GameStorageService(),
        wake: FakeWake(),
        clock: now,
      );
      await resumed.init();
      expect(resumed.hasActiveGame, isFalse);
    });

    test('discarding clears the saved game', () async {
      await controller.startGame(players: roster());
      await controller.discardGame();

      final resumed = GameController(
        storage: GameStorageService(),
        wake: FakeWake(),
        clock: now,
      );
      await resumed.init();
      expect(resumed.hasActiveGame, isFalse);
    });

    test('settings persist across controllers', () async {
      await controller.setBatterySaver(true);
      await controller.setScreenMode(ScreenMode.keepAwake);

      final other = GameController(
        storage: GameStorageService(),
        wake: FakeWake(),
        clock: now,
      );
      await other.init();
      expect(other.settings.batterySaverMode, isTrue);
      expect(other.settings.screenMode, ScreenMode.keepAwake);
    });
  });

  group('turn warning', () {
    test('detects when the current turn passes the threshold', () async {
      await controller.setTurnWarning(const Duration(seconds: 10));
      await controller.startGame(players: roster());

      advance(const Duration(seconds: 9));
      expect(controller.isCurrentTurnOverLimit, isFalse);

      advance(const Duration(seconds: 1));
      expect(controller.isCurrentTurnOverLimit, isTrue);

      // Resets when the turn changes.
      controller.nextTurn();
      expect(controller.isCurrentTurnOverLimit, isFalse);
    });

    test('is off by default', () async {
      await controller.startGame(players: roster());
      advance(const Duration(minutes: 10));
      expect(controller.turnWarningThreshold, Duration.zero);
      expect(controller.isCurrentTurnOverLimit, isFalse);
    });

    test('threshold persists across controllers', () async {
      await controller.setTurnWarning(const Duration(minutes: 2));

      final other = GameController(
        storage: GameStorageService(),
        wake: FakeWake(),
        clock: now,
      );
      await other.init();
      expect(other.settings.turnWarningThreshold, const Duration(minutes: 2));
    });
  });

  group('history and scores', () {
    test('ending a game archives it immediately, unscored', () async {
      await controller.startGame(players: roster(), gameName: 'Chess');
      advance(const Duration(seconds: 5));
      await controller.endGame();

      expect(controller.lastResult, isNotNull);
      final history = await controller.loadHistory();
      expect(history.length, 1);
      expect(history.single.gameName, 'Chess');
      expect(history.single.hasScores, isFalse);
      expect(
        history.single.players.first.accumulatedDuration,
        const Duration(seconds: 5),
      );
    });

    test('discarding a game does not archive it', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 5));
      await controller.discardGame();

      expect(await controller.loadHistory(), isEmpty);
    });

    test('setScores updates the same history entry', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 5));
      await controller.endGame();
      await controller.setScores({'p0': 3, 'p1': 9});

      final history = await controller.loadHistory();
      expect(history.length, 1); // updated, not duplicated
      expect(history.single.winners.single.id, 'p1');
      expect(controller.lastResult!.topScore, 9);
    });

    test('scores can be corrected after being saved', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 5));
      await controller.endGame();
      await controller.setScores({'p0': 3, 'p1': 9});
      await controller.setScores({'p0': 30, 'p1': 9});

      final history = await controller.loadHistory();
      expect(history.length, 1);
      expect(history.single.winners.single.id, 'p0');
    });

    test('setScores without a finished game is a no-op', () async {
      await controller.setScores({'p0': 1});
      expect(controller.lastResult, isNull);
      expect(await controller.loadHistory(), isEmpty);
    });

    test('several games accumulate in history', () async {
      for (var i = 0; i < 3; i++) {
        await controller.startGame(players: roster(), gameName: 'Game $i');
        advance(const Duration(seconds: 5));
        await controller.endGame();
        advance(const Duration(minutes: 1));
      }
      final history = await controller.loadHistory();
      expect(history.length, 3);
      expect(history.first.gameName, 'Game 2'); // newest first
    });

    test('history survives a fresh controller', () async {
      await controller.startGame(players: roster(), gameName: 'Chess');
      advance(const Duration(seconds: 5));
      await controller.endGame();
      await controller.setScores({'p0': 5, 'p1': 2});

      final other = GameController(
        storage: GameStorageService(),
        wake: FakeWake(),
        clock: now,
      );
      final history = await other.loadHistory();
      expect(history.single.gameName, 'Chess');
      expect(history.single.winners.single.id, 'p0');
    });

    test('a deleted game can be restored to its original position', () async {
      for (var i = 0; i < 3; i++) {
        await controller.startGame(players: roster(), gameName: 'Game $i');
        advance(const Duration(seconds: 5));
        await controller.endGame();
        advance(const Duration(minutes: 1));
      }
      final history = await controller.loadHistory();
      final middle = history[1]; // 'Game 1'

      await controller.deleteHistoryEntry(middle.id);
      expect((await controller.loadHistory()).map((r) => r.gameName), [
        'Game 2',
        'Game 0',
      ]);

      await controller.restoreHistoryEntry(middle);
      expect(
        (await controller.loadHistory()).map((r) => r.gameName),
        ['Game 2', 'Game 1', 'Game 0'], // back in the middle, not at the top
      );
    });

    test('clearHistory empties the log', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 5));
      await controller.endGame();
      await controller.clearHistory();
      expect(await controller.loadHistory(), isEmpty);
    });
  });

  group('rematch', () {
    test('resets stats but keeps roster and name', () async {
      await controller.startGame(players: roster(), gameName: 'Uno');
      advance(const Duration(seconds: 9));
      controller.nextTurn();
      await controller.rematchSamePlayers();

      expect(controller.game!.gameName, 'Uno');
      expect(controller.game!.players.length, 2);
      expect(controller.game!.players[0].accumulatedDuration, Duration.zero);
      expect(controller.game!.turnHistory, isEmpty);
      expect(controller.currentTurnElapsed, Duration.zero);
    });

    test('clears the previous game\'s scores', () async {
      await controller.startGame(players: roster(), gameName: 'Uno');
      advance(const Duration(seconds: 5));
      await controller.endGame();
      await controller.setScores({'p0': 11, 'p1': 4});

      await controller.rematchSamePlayers();
      expect(controller.game!.players.every((p) => p.score == null), isTrue);
    });
  });

  group('dice', () {
    setUp(() async => controller.setDiceMode(DiceMode.twoD6));

    test('is off by default and enabling it carries into a new game', () async {
      final fresh = GameController(
        storage: GameStorageService(),
        wake: FakeWake(),
        clock: now,
      );
      expect(fresh.diceEnabled, isFalse);

      await controller.startGame(players: roster(4));
      expect(controller.diceEnabled, isTrue);
      expect(controller.game!.diceMode, DiceMode.twoD6);
    });

    test('one tap logs the first roll, the next passes the turn', () async {
      await controller.startGame(players: roster(4));

      controller.tapRoll(8);
      expect(controller.currentPlayer!.id, 'p0', reason: 'still P1');
      expect(controller.currentTurnRoll, 8);

      advance(const Duration(seconds: 40));
      controller.tapRoll(5);
      expect(controller.currentPlayer!.id, 'p1');
      expect(controller.currentTurnRoll, 5);
      expect(controller.game!.rolls.last.playerId, 'p1');
      expect(controller.game!.players[0].accumulatedDuration.inSeconds, 40);
    });

    test(
      'passing without a roll leaves the next tap to log for the new player',
      () async {
        await controller.startGame(players: roster(4));

        // The setup phase: tap-anywhere advances, no dice involved.
        for (var i = 0; i < 8; i++) {
          advance(const Duration(seconds: 15));
          controller.nextTurn();
        }
        expect(controller.game!.rolls, isEmpty);
        expect(controller.currentPlayer!.id, 'p0');

        controller.tapRoll(6);
        expect(controller.currentPlayer!.id, 'p0');
        expect(controller.game!.rolls.single.playerId, 'p0');
      },
    );

    test('undo drops the roll, and amend fixes a mistyped one', () async {
      await controller.startGame(players: roster(4));
      controller.tapRoll(8);

      controller.amendRoll(9);
      expect(controller.currentTurnRoll, 9);

      controller.undo();
      expect(controller.currentTurnRoll, isNull);
      expect(controller.game!.rolls, isEmpty);
    });

    test('the live distribution reflects what has been tapped', () async {
      await controller.startGame(players: roster(4));
      for (final roll in [7, 8, 7]) {
        advance(const Duration(seconds: 10));
        controller.tapRoll(roll);
      }
      expect(controller.liveDiceStats.totalRolls, 3);
      expect(controller.liveDiceStats.countFor(7), 2);
      expect(controller.liveDiceStats.sevens, 2);
    });

    test('rolls are persisted and restored with the game', () async {
      await controller.startGame(players: roster(4));
      controller.tapRoll(8);
      advance(const Duration(seconds: 20));
      controller.tapRoll(4);
      await Future<void>.delayed(Duration.zero);

      final reloaded = GameController(
        storage: GameStorageService(),
        wake: FakeWake(),
        clock: now,
      );
      await reloaded.init();
      expect(reloaded.game!.rolls.map((r) => r.total), [8, 4]);
      expect(reloaded.currentTurnRoll, 4);
      expect(reloaded.diceEnabled, isTrue);
    });

    test('a finished game archives its rolls', () async {
      await controller.startGame(players: roster(4), gameName: 'Catan');
      controller.tapRoll(7);
      advance(const Duration(seconds: 30));
      controller.tapRoll(9);
      advance(const Duration(seconds: 30));
      await controller.endGame();

      final result = controller.lastResult!;
      expect(result.rollTotals, [7, 9]);
      expect(result.rollerIndices, [0, 1]);
      expect(result.sevensRolledBy(result.players[0]), 1);

      final archived = (await controller.loadHistory()).single;
      expect(archived.rollTotals, [7, 9]);

      // ...and entering scores afterwards keeps them.
      await controller.setScores({'p0': 10, 'p1': 8});
      expect((await controller.loadHistory()).single.rollTotals, [7, 9]);
    });

    test('a rematch starts with a clean roll log', () async {
      await controller.startGame(players: roster(4));
      controller.tapRoll(7);
      await controller.rematchSamePlayers();
      expect(controller.game!.rolls, isEmpty);
      expect(controller.currentTurnRoll, isNull);
    });
  });

  group('passing the turn out of order', () {
    test('hands over to the chosen player and records the turn', () async {
      await controller.startGame(players: roster(4));
      advance(const Duration(seconds: 25));
      controller.passTurnTo(3);

      expect(controller.currentPlayer!.id, 'p3');
      expect(controller.game!.players[0].accumulatedDuration.inSeconds, 25);
    });

    test('passing to the same player starts them a new turn', () async {
      await controller.startGame(players: roster(4));
      advance(const Duration(seconds: 25));
      controller.passTurnTo(0);

      expect(controller.currentPlayer!.id, 'p0');
      expect(controller.currentPlayer!.turnCount, 1);
      expect(controller.currentTurnElapsed, Duration.zero);
    });
  });
}
