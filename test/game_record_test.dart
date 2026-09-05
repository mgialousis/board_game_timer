import 'package:board_game_timer/models/dice_mode.dart';
import 'package:board_game_timer/models/dice_roll.dart';
import 'package:board_game_timer/models/game_record.dart';
import 'package:board_game_timer/models/game_state.dart';
import 'package:board_game_timer/models/player.dart';
import 'package:board_game_timer/models/screen_mode.dart';
import 'package:board_game_timer/models/turn_record.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime(2026, 1, 1, 20);
final _end = DateTime(2026, 1, 1, 21, 30);

GameRecord _record({List<Player>? players}) => GameRecord(
  id: 'g1',
  gameName: 'Catan',
  startedAt: _start,
  endedAt: _end,
  players:
      players ??
      const [
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
);

void main() {
  group('time statistics', () {
    test('percentages reflect recorded time and sum to 100', () {
      final r = _record(); // Ada 30s, Bo 10s -> 75% / 25%
      expect(r.totalPlayedTime, const Duration(seconds: 40));
      expect(r.percentFor(r.players[0]), closeTo(75, 0.001));
      expect(r.percentFor(r.players[1]), closeTo(25, 0.001));
      expect(
        r.percentFor(r.players[0]) + r.percentFor(r.players[1]),
        closeTo(100, 0.001),
      );
    });

    test('identifies slowest by total and by average', () {
      final r = _record();
      // Ada: 30s total, avg 15s. Bo: 10s total, avg 10s.
      expect(r.slowestByTotal?.id, 'a');
      expect(r.slowestByAverage?.id, 'a');
    });

    test('returns null slowest when nobody has played', () {
      final r = _record(
        players: const [
          Player(id: 'a', name: 'Ada', colorValue: 0xFFE53935),
          Player(id: 'b', name: 'Bo', colorValue: 0xFF1E88E5),
        ],
      );
      expect(r.slowestByTotal, isNull);
      expect(r.slowestByAverage, isNull);
      expect(r.percentFor(r.players[0]), 0);
    });

    test('game length is the wall clock span, never negative', () {
      expect(_record().gameLength, const Duration(minutes: 90));
      final backwards = GameRecord(
        id: 'x',
        gameName: '',
        startedAt: _end,
        endedAt: _start,
        players: const [],
      );
      expect(backwards.gameLength, Duration.zero);
    });

    test('title falls back when the game is unnamed', () {
      expect(_record().title, 'Catan');
      final unnamed = GameRecord(
        id: 'x',
        gameName: '',
        startedAt: _start,
        endedAt: _end,
        players: const [],
      );
      expect(unnamed.title, 'Board game');
    });
  });

  group('scores and winner', () {
    test('an unscored game has no winner', () {
      final r = _record();
      expect(r.hasScores, isFalse);
      expect(r.topScore, isNull);
      expect(r.winners, isEmpty);
      expect(r.isWinner(r.players[0]), isFalse);
    });

    test('highest score wins', () {
      final r = _record().withScores({'a': 7, 'b': 12});
      expect(r.hasScores, isTrue);
      expect(r.topScore, 12);
      expect(r.winners.map((p) => p.id), ['b']);
      expect(r.isWinner(r.players[1]), isTrue);
      expect(r.isWinner(r.players[0]), isFalse);
    });

    test('a tie produces co-winners', () {
      final r = _record().withScores({'a': 9, 'b': 9});
      expect(r.topScore, 9);
      expect(r.winners.map((p) => p.id), ['a', 'b']);
    });

    test('zero is a real score, not "unscored"', () {
      final r = _record().withScores({'a': 0, 'b': -5});
      expect(r.hasScores, isTrue);
      expect(r.topScore, 0);
      expect(r.winners.map((p) => p.id), ['a']);
    });

    test('negative scores are supported', () {
      final r = _record().withScores({'a': -20, 'b': -3});
      expect(r.topScore, -3);
      expect(r.winners.map((p) => p.id), ['b']);
    });

    test('a partly scored game still picks a winner', () {
      final r = _record().withScores({'a': 4});
      expect(r.hasScores, isTrue);
      expect(r.winners.map((p) => p.id), ['a']);
      expect(r.players[1].score, isNull);
    });

    test('withScores can clear a previously entered score', () {
      final scored = _record().withScores({'a': 4, 'b': 8});
      final cleared = scored.withScores({'a': null, 'b': null});
      expect(cleared.hasScores, isFalse);
      expect(cleared.winners, isEmpty);
    });
  });

  group('ranking', () {
    test('orders by time when unscored', () {
      expect(_record().ranked.map((p) => p.id), ['a', 'b']); // 30s then 10s
    });

    test('orders by score once scored, unscored players last', () {
      final r = _record(
        players: const [
          Player(id: 'a', name: 'Ada', colorValue: 1, score: 3),
          Player(id: 'b', name: 'Bo', colorValue: 2),
          Player(id: 'c', name: 'Cy', colorValue: 3, score: 11),
        ],
      );
      expect(r.ranked.map((p) => p.id), ['c', 'a', 'b']);
    });
  });

  group('serialization', () {
    test('round-trips through JSON including scores', () {
      final original = _record().withScores({'a': 12, 'b': -3});
      final restored = GameRecord.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.gameName, 'Catan');
      expect(restored.startedAt, _start);
      expect(restored.endedAt, _end);
      expect(restored.players.length, 2);
      expect(restored.players[0].score, 12);
      expect(restored.players[1].score, -3);
      expect(
        restored.players[0].accumulatedDuration,
        const Duration(seconds: 30),
      );
      expect(restored.winners.map((p) => p.id), ['a']);
    });

    test('a game saved before scoring existed loads as unscored', () {
      final json = _record().toJson();
      for (final p in json['players'] as List) {
        (p as Map<String, dynamic>).remove('score');
      }
      final restored = GameRecord.fromJson(json);
      expect(restored.hasScores, isFalse);
    });
  });

  group('fromGameState', () {
    test('captures the finished game and derives a stable id', () {
      final state = GameState(
        players: const [
          Player(
            id: 'a',
            name: 'Ada',
            colorValue: 1,
            accumulatedDuration: Duration(seconds: 5),
            turnCount: 1,
          ),
          Player(id: 'b', name: 'Bo', colorValue: 2),
        ],
        currentPlayerIndex: 0,
        currentTurnStartTime: _start,
        isPaused: false,
        pausedAt: null,
        turnHistory: [
          TurnRecord(
            playerId: 'a',
            startTime: _start,
            endTime: _start.add(const Duration(seconds: 5)),
            duration: const Duration(seconds: 5),
          ),
        ],
        undoStack: const [],
        gameName: 'Uno',
        startedAt: _start,
        endedAt: _end,
        batterySaverMode: false,
        screenMode: ScreenMode.normal,
        turnWarningThreshold: Duration.zero,
      );

      final record = GameRecord.fromGameState(state);
      expect(record.gameName, 'Uno');
      expect(record.startedAt, _start);
      expect(record.endedAt, _end);
      expect(record.players.length, 2);
      expect(record.totalPlayedTime, const Duration(seconds: 5));
      // Same game -> same id, so re-saving updates rather than duplicates.
      expect(record.id, GameRecord.fromGameState(state).id);
    });
  });

  group('dice', () {
    GameRecord rolled() => GameRecord(
      id: 'g1',
      gameName: 'Catan',
      startedAt: _start,
      endedAt: _end,
      players: const [
        Player(id: 'a', name: 'Ada', colorValue: 0xFFE53935),
        Player(id: 'b', name: 'Bo', colorValue: 0xFF1E88E5),
      ],
      rollTotals: const [7, 8, 7, 5],
      rollerIndices: const [0, 1, 0, 1],
    );

    test('a game without dice hides the whole feature', () {
      final r = _record();
      expect(r.hasRolls, isFalse);
      expect(r.diceStats.isEmpty, isTrue);
      expect(r.mostSevensPlayer, isNull);
      expect(r.sevensRolledBy(r.players.first), 0);
      expect(r.rollCountFor(r.players.first), 0);
    });

    test('projects rolls out of a finished game state', () {
      final state = GameState(
        players: const [
          Player(id: 'a', name: 'Ada', colorValue: 1),
          Player(id: 'b', name: 'Bo', colorValue: 2),
        ],
        currentPlayerIndex: 0,
        currentTurnStartTime: _start,
        isPaused: false,
        pausedAt: null,
        turnHistory: const [],
        undoStack: const [],
        gameName: 'Catan',
        startedAt: _start,
        endedAt: _end,
        batterySaverMode: false,
        screenMode: ScreenMode.normal,
        turnWarningThreshold: Duration.zero,
        diceMode: DiceMode.twoD6,
        rolls: const [
          DiceRoll(playerId: 'a', total: 7),
          DiceRoll(playerId: 'b', total: 9),
        ],
      );

      final r = GameRecord.fromGameState(state);
      expect(r.hasRolls, isTrue);
      expect(r.rollTotals, [7, 9]);
      expect(r.rollerIndices, [0, 1], reason: 'ids projected to indices');
      expect(r.diceStats.totalRolls, 2);
    });

    test('per-player figures come off the parallel lists', () {
      final r = rolled();
      expect(r.diceStats.countFor(7), 2);
      expect(r.rollCountFor(r.players[0]), 2);
      expect(r.rollCountFor(r.players[1]), 2);
      expect(r.sevensRolledBy(r.players[0]), 2);
      expect(r.sevensRolledBy(r.players[1]), 0);
      expect(r.mostSevensPlayer?.name, 'Ada');
    });

    test('lookups work on the re-sorted list from ranked', () {
      final r = rolled().withScores({'a': 3, 'b': 9});
      // Bo is first in `ranked` but second in `players`.
      expect(r.ranked.first.name, 'Bo');
      expect(r.sevensRolledBy(r.ranked.first), 0);
      expect(r.sevensRolledBy(r.ranked.last), 2);
    });

    test('editing scores must not erase the roll log', () {
      final r = rolled().withScores({'a': 10, 'b': 8});
      expect(r.rollTotals, [7, 8, 7, 5]);
      expect(r.rollerIndices, [0, 1, 0, 1]);
      expect(r.winners.single.name, 'Ada');
    });

    test('rolls survive a JSON round trip', () {
      final back = GameRecord.fromJson(rolled().toJson());
      expect(back.rollTotals, [7, 8, 7, 5]);
      expect(back.rollerIndices, [0, 1, 0, 1]);
      expect(back.hasRolls, isTrue);
    });

    test('a history entry archived before dice tracking still loads', () {
      final legacy = _record().toJson()
        ..remove('rollTotals')
        ..remove('rollers')
        ..['version'] = 1;

      final back = GameRecord.fromJson(legacy);
      expect(back.hasRolls, isFalse);
      expect(back.rollTotals, isEmpty);
      expect(back.players.length, 2, reason: 'the rest is unaffected');
      expect(back.totalPlayedTime, const Duration(seconds: 40));
    });

    test('an unscored, undiced game writes no dice keys at all', () {
      expect(_record().toJson().containsKey('rollTotals'), isFalse);
    });
  });
}
