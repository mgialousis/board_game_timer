import 'package:board_game_timer/models/dice_mode.dart';
import 'package:board_game_timer/models/dice_roll.dart';
import 'package:board_game_timer/models/game_state.dart';
import 'package:board_game_timer/models/player.dart';
import 'package:board_game_timer/models/screen_mode.dart';
import 'package:board_game_timer/models/turn_record.dart';
import 'package:board_game_timer/models/undo_entry.dart';
import 'package:flutter_test/flutter_test.dart';

GameState _sample() {
  final start = DateTime(2026, 1, 1, 10);
  return GameState(
    players: const [
      Player(
        id: 'a',
        name: 'Ada',
        colorValue: 0xFFE53935,
        accumulatedDuration: Duration(seconds: 30),
        turnCount: 2,
        longestTurn: Duration(seconds: 20),
      ),
      Player(
        id: 'b',
        name: 'Bo',
        colorValue: 0xFF1E88E5,
        accumulatedDuration: Duration(seconds: 10),
        turnCount: 1,
        longestTurn: Duration(seconds: 10),
      ),
    ],
    currentPlayerIndex: 1,
    currentTurnStartTime: start,
    isPaused: false,
    pausedAt: null,
    turnHistory: [
      TurnRecord(
        playerId: 'a',
        startTime: start,
        endTime: start.add(const Duration(seconds: 20)),
        duration: const Duration(seconds: 20),
      ),
    ],
    undoStack: const [
      UndoEntry(
        kind: UndoKind.advance,
        previousPlayerIndex: 0,
        previousElapsed: Duration(seconds: 20),
      ),
    ],
    gameName: 'Catan',
    startedAt: start,
    endedAt: null,
    batterySaverMode: true,
    screenMode: ScreenMode.lockedPlay,
    turnWarningThreshold: const Duration(minutes: 2),
  );
}

void main() {
  group('serialization', () {
    test('round-trips through JSON', () {
      final original = _sample();
      final restored = GameState.fromJson(original.toJson());

      expect(restored.gameName, 'Catan');
      expect(restored.players.length, 2);
      expect(restored.players.first.name, 'Ada');
      expect(
        restored.players.first.accumulatedDuration,
        const Duration(seconds: 30),
      );
      expect(restored.currentPlayerIndex, 1);
      expect(restored.isPaused, false);
      expect(restored.pausedAt, isNull);
      expect(restored.turnHistory.length, 1);
      expect(restored.turnHistory.first.duration, const Duration(seconds: 20));
      expect(restored.undoStack.length, 1);
      expect(restored.undoStack.first.kind, UndoKind.advance);
      expect(restored.batterySaverMode, true);
      expect(restored.screenMode, ScreenMode.lockedPlay);
      expect(restored.turnWarningThreshold, const Duration(minutes: 2));
    });

    test('migrates the legacy keepScreenAwake flag to ScreenMode', () {
      final json = _sample().toJson()..remove('screenMode');
      json['keepScreenAwake'] = true;
      expect(GameState.fromJson(json).screenMode, ScreenMode.keepAwake);

      json['keepScreenAwake'] = false;
      expect(GameState.fromJson(json).screenMode, ScreenMode.normal);
    });

    test('preserves paused state and timestamp', () {
      final paused = _sample().copyWith(
        isPaused: true,
        pausedAt: DateTime(2026, 1, 1, 10, 5),
      );
      final restored = GameState.fromJson(paused.toJson());
      expect(restored.isPaused, true);
      expect(restored.pausedAt, DateTime(2026, 1, 1, 10, 5));
    });
  });

  // Post-game statistics (totals, percentages, winner) are covered by
  // game_record_test.dart — they live on GameRecord.

  test('isCurrentTurnOverLimit respects the threshold', () {
    final start = DateTime(2026, 1, 1, 10);
    final g = _sample().copyWith(
      currentTurnStartTime: start,
      turnWarningThreshold: const Duration(minutes: 2),
    );
    expect(
      g.isCurrentTurnOverLimit(start.add(const Duration(seconds: 119))),
      isFalse,
    );
    expect(
      g.isCurrentTurnOverLimit(start.add(const Duration(minutes: 2))),
      isTrue,
    );

    // Disabled threshold is never over the limit.
    final off = g.copyWith(turnWarningThreshold: Duration.zero);
    expect(
      off.isCurrentTurnOverLimit(start.add(const Duration(hours: 1))),
      isFalse,
    );
  });

  test('currentTurnElapsed is frozen while paused and never negative', () {
    final start = DateTime(2026, 1, 1, 10);
    final running = _sample().copyWith(currentTurnStartTime: start);
    expect(
      running.currentTurnElapsed(start.add(const Duration(seconds: 7))),
      const Duration(seconds: 7),
    );

    // Clock earlier than start -> clamped to zero.
    expect(
      running.currentTurnElapsed(start.subtract(const Duration(seconds: 5))),
      Duration.zero,
    );

    final paused = running.copyWith(
      isPaused: true,
      pausedAt: start.add(const Duration(seconds: 4)),
    );
    // Frozen at 4s regardless of how far "now" advances.
    expect(
      paused.currentTurnElapsed(start.add(const Duration(seconds: 100))),
      const Duration(seconds: 4),
    );
  });

  group('dice', () {
    test('rolls survive a JSON round trip', () {
      final g = _sample().copyWith(
        diceMode: DiceMode.twoD6,
        rolls: const [
          DiceRoll(playerId: 'a', total: 8),
          DiceRoll(playerId: 'b', total: 7),
        ],
        currentTurnRolled: true,
      );

      final back = GameState.fromJson(g.toJson());
      expect(back.diceMode, DiceMode.twoD6);
      expect(back.rolls.map((r) => r.total), [8, 7]);
      expect(back.rolls.last.playerId, 'b');
      expect(back.currentTurnRolled, isTrue);
      expect(back.currentTurnRoll, 7);
      expect(back.rollTotals, [8, 7]);
    });

    test('a game saved before dice tracking existed still loads', () {
      // Exactly the payload shape v1.1.0 wrote: no dice keys at all.
      final legacy = _sample().toJson()
        ..remove('diceMode')
        ..remove('rolls')
        ..remove('currentTurnRolled')
        ..['version'] = 1;

      final back = GameState.fromJson(legacy);
      expect(back.diceMode, DiceMode.off);
      expect(back.rolls, isEmpty);
      expect(back.currentTurnRolled, isFalse);
      expect(back.currentTurnRoll, isNull);
      // ...and everything else is untouched.
      expect(back.players.length, 2);
      expect(back.currentPlayerIndex, 1);
      expect(back.turnHistory.length, 1);
    });
  });
}
