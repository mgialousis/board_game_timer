import 'package:board_game_timer/controllers/game_controller.dart';
import 'package:board_game_timer/models/dice_mode.dart';
import 'package:board_game_timer/models/player.dart';
import 'package:board_game_timer/screens/game_screen.dart';
import 'package:board_game_timer/screens/history_screen.dart';
import 'package:board_game_timer/screens/setup_screen.dart';
import 'package:board_game_timer/screens/summary_screen.dart';
import 'package:board_game_timer/services/game_storage_service.dart';
import 'package:board_game_timer/services/screen_wake_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeWake extends ScreenWakeService {
  @override
  Future<void> setEnabled(bool value) async {}
}

void main() {
  late DateTime clock;
  DateTime now() => clock;

  GameController makeController() => GameController(
    storage: GameStorageService(),
    wake: FakeWake(),
    clock: now,
  );

  List<Player> roster() => const [
    Player(id: 'p0', name: 'Alice', colorValue: 0xFFE53935),
    Player(id: 'p1', name: 'Bob', colorValue: 0xFF1E88E5),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 1, 1, 12);
  });

  testWidgets('setup screen shows default players and can add one', (
    tester,
  ) async {
    final controller = makeController();
    await tester.pumpWidget(
      MaterialApp(home: SetupScreen(controller: controller)),
    );

    expect(find.text('Start game'), findsOneWidget);
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('Player 2'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Player 3'), findsOneWidget);
  });

  testWidgets('tapping the game area advances to the next player', (
    tester,
  ) async {
    final controller = makeController();
    // Battery saver on -> no infinite pulse animation in the test.
    await controller.setBatterySaver(true);
    await controller.startGame(players: roster());

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await tester.pump();

    String currentPlayer() =>
        tester.widget<Text>(find.byKey(const Key('current-player-name'))).data!;

    expect(currentPlayer(), 'Alice');

    await tester.tap(find.byKey(const Key('game-tap-area')));
    await tester.pump();

    // Advanced to Bob (Alice now appears only in the "Next" pill).
    expect(currentPlayer(), 'Bob');

    // Dispose the screen so the 1-second ticker is cancelled.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('shows a soft turn warning after the threshold', (tester) async {
    final controller = makeController();
    await controller.setBatterySaver(true); // avoid the infinite pulse anim
    await controller.setTurnWarning(const Duration(seconds: 5));
    await controller.startGame(players: roster());

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await tester.pump();
    expect(find.byKey(const Key('turn-warning')), findsNothing);

    // Move the injected clock past the threshold, then fire one ticker tick.
    clock = clock.add(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('turn-warning')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('summary screen lists players and actions', (tester) async {
    final controller = makeController();
    await controller.startGame(players: roster(), gameName: 'Chess');
    clock = clock.add(const Duration(seconds: 5));
    controller.nextTurn();
    clock = clock.add(const Duration(seconds: 3));
    await controller.endGame();

    await tester.pumpWidget(
      MaterialApp(
        home: SummaryScreen(
          controller: controller,
          result: controller.lastResult!,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chess'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Rematch'), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);
    // Unscored game: no winner banner yet.
    expect(find.byKey(const Key('winner-banner')), findsNothing);
    // No dice were tracked, so the distribution stays hidden entirely.
    expect(find.byKey(const Key('dice-chart')), findsNothing);
  });

  testWidgets('entering scores shows the winner and saves to history', (
    tester,
  ) async {
    final controller = makeController();
    await controller.startGame(players: roster(), gameName: 'Chess');
    clock = clock.add(const Duration(seconds: 5));
    controller.nextTurn();
    clock = clock.add(const Duration(seconds: 3));
    await controller.endGame();

    await tester.pumpWidget(
      MaterialApp(
        home: SummaryScreen(
          controller: controller,
          result: controller.lastResult!,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-scores')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('score-field-p0')), '7');
    await tester.enterText(find.byKey(const Key('score-field-p1')), '12');
    await tester.tap(find.byKey(const Key('save-scores')));
    await tester.pumpAndSettle();

    // Bob scored higher, so the banner names him with his score.
    final banner = find.byKey(const Key('winner-banner'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.text('Bob')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: banner, matching: find.text('12')),
      findsOneWidget,
    );
    expect(controller.lastResult!.winners.single.name, 'Bob');

    // ...and the history entry was updated in place, not duplicated.
    final history = await controller.loadHistory();
    expect(history.length, 1);
    expect(history.single.winners.single.name, 'Bob');
  });

  testWidgets('history screen lists finished games', (tester) async {
    final controller = makeController();
    await controller.startGame(players: roster(), gameName: 'Chess');
    clock = clock.add(const Duration(seconds: 5));
    await controller.endGame();
    await controller.setScores({'p0': 3, 'p1': 1});

    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chess'), findsOneWidget);
    expect(find.textContaining('Alice'), findsOneWidget); // winner line
    expect(find.text('No games yet'), findsNothing);
  });

  testWidgets('deleting a game from history can be undone', (tester) async {
    final controller = makeController();
    await controller.startGame(players: roster(), gameName: 'Chess');
    clock = clock.add(const Duration(seconds: 5));
    await controller.endGame();

    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chess'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    // Gone from the list, with an undo offered.
    expect(find.text('Chess'), findsNothing);
    expect(find.text('No games yet'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(await controller.loadHistory(), isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Chess'), findsOneWidget);
    expect((await controller.loadHistory()).single.gameName, 'Chess');
  });

  testWidgets('history screen shows an empty state', (tester) async {
    final controller = makeController();
    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No games yet'), findsOneWidget);
  });

  group('dice tracking', () {
    Future<GameController> diceGame(
      WidgetTester tester, {
      int? preRoll,
      String name = '',
    }) async {
      final controller = makeController();
      await controller.setBatterySaver(true); // no infinite pulse in tests
      await controller.setDiceMode(DiceMode.twoD6);
      await controller.startGame(players: roster(), gameName: name);
      if (preRoll != null) controller.tapRoll(preRoll);

      await tester.pumpWidget(
        MaterialApp(home: GameScreen(controller: controller)),
      );
      await tester.pump();
      return controller;
    }

    // The 1-second ticker must be cancelled or the test never settles.
    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('the strip is hidden unless dice tracking is on', (
      tester,
    ) async {
      final controller = makeController();
      await controller.setBatterySaver(true);
      await controller.startGame(players: roster());

      await tester.pumpWidget(
        MaterialApp(home: GameScreen(controller: controller)),
      );
      await tester.pump();

      expect(find.byKey(const Key('dice-strip')), findsNothing);
      expect(
        find.text('Tap anywhere to end turn  ·  long-press to pause'),
        findsOneWidget,
      );
      await teardown(tester);
    });

    testWidgets('the first number tap logs the roll without passing', (
      tester,
    ) async {
      final controller = await diceGame(tester);
      expect(find.byKey(const Key('dice-strip')), findsOneWidget);
      expect(find.text('Tap Alice’s roll'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dice-btn-8')));
      await tester.pump();

      expect(controller.currentPlayer!.name, 'Alice');
      expect(controller.currentTurnRoll, 8);
      expect(find.text('Alice rolled 8'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a number tap passes the turn once the roll is in', (
      tester,
    ) async {
      // Alice has already rolled, so the next number belongs to Bob.
      final controller = await diceGame(tester, preRoll: 8);
      clock = clock.add(const Duration(seconds: 30));

      await tester.tap(find.byKey(const Key('dice-btn-5')));
      await tester.pump();

      expect(controller.currentPlayer!.name, 'Bob');
      expect(controller.currentTurnRoll, 5);
      expect(controller.game!.rolls.last.playerId, 'p1');
      await teardown(tester);
    });

    testWidgets('tapping the board passes the turn with no roll', (
      tester,
    ) async {
      final controller = await diceGame(tester);

      await tester.tap(find.byKey(const Key('game-tap-area')));
      await tester.pump();

      expect(controller.currentPlayer!.name, 'Bob');
      expect(controller.game!.rolls, isEmpty);
      expect(controller.currentTurnRoll, isNull);
      await teardown(tester);
    });

    testWidgets('the current roll can be corrected', (tester) async {
      final controller = await diceGame(tester, preRoll: 8);

      await tester.tap(find.byKey(const Key('dice-current-roll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fix-roll-9')));
      await tester.pumpAndSettle();

      expect(controller.currentTurnRoll, 9);
      expect(controller.currentPlayer!.name, 'Alice');
      await teardown(tester);
    });

    testWidgets('the summary charts the distribution', (tester) async {
      final controller = makeController();
      await controller.setDiceMode(DiceMode.twoD6);
      await controller.startGame(players: roster(), gameName: 'Catan');
      controller.tapRoll(7);
      clock = clock.add(const Duration(seconds: 5));
      controller.tapRoll(8);
      clock = clock.add(const Duration(seconds: 5));
      await controller.endGame();

      await tester.pumpWidget(
        MaterialApp(
          home: SummaryScreen(
            controller: controller,
            result: controller.lastResult!,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dice-chart')), findsOneWidget);
      expect(find.textContaining('2 rolls'), findsWidgets);
    });
  });

  group('passing the turn out of order', () {
    testWidgets('the Next pill picks who plays next without advancing', (
      tester,
    ) async {
      final controller = makeController();
      await controller.setBatterySaver(true);
      await controller.startGame(players: roster());

      await tester.pumpWidget(
        MaterialApp(home: GameScreen(controller: controller)),
      );
      await tester.pump();

      // Opening the picker must not itself count as a tap on the board.
      await tester.tap(find.byKey(const Key('next-player-pill')));
      await tester.pumpAndSettle();
      expect(controller.currentPlayer!.name, 'Alice');
      expect(find.text('Pass turn to…'), findsOneWidget);

      // Hand it back to Alice — Catan's snake round plays the same player twice.
      await tester.tap(find.byKey(const Key('pass-to-p0')));
      await tester.pumpAndSettle();

      expect(controller.currentPlayer!.name, 'Alice');
      expect(controller.currentPlayer!.turnCount, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
