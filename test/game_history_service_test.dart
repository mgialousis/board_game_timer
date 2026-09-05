import 'dart:convert';

import 'package:board_game_timer/models/game_record.dart';
import 'package:board_game_timer/models/player.dart';
import 'package:board_game_timer/services/game_history_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameRecord _record(int day, {String name = 'Game', int? score}) {
  final start = DateTime(2026, 1, day, 20);
  return GameRecord(
    id: GameRecord.idFor(start, start.add(const Duration(hours: 1))),
    gameName: name,
    startedAt: start,
    endedAt: start.add(const Duration(hours: 1)),
    players: [
      Player(id: 'a', name: 'Ada', colorValue: 1, score: score),
      const Player(id: 'b', name: 'Bo', colorValue: 2),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameHistoryService history;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    history = GameHistoryService();
  });

  test('starts empty', () async {
    expect(await history.list(), isEmpty);
  });

  test('saves games and returns them newest first', () async {
    await history.save(_record(1, name: 'Oldest'));
    await history.save(_record(3, name: 'Newest'));
    await history.save(_record(2, name: 'Middle'));

    final list = await history.list();
    expect(list.map((r) => r.gameName), ['Newest', 'Middle', 'Oldest']);
  });

  test(
    'saving the same game again updates it instead of duplicating',
    () async {
      final original = _record(1);
      await history.save(original);
      await history.save(original.withScores({'a': 42}));

      final list = await history.list();
      expect(list.length, 1);
      expect(list.single.players.first.score, 42);
    },
  );

  test('editing an old game does not reorder it', () async {
    await history.save(_record(1, name: 'Old'));
    await history.save(_record(5, name: 'Recent'));
    await history.save(_record(1, name: 'Old').withScores({'a': 3}));

    final list = await history.list();
    expect(list.map((r) => r.gameName), ['Recent', 'Old']);
  });

  test('keeps only the most recent maxEntries games', () async {
    for (var day = 1; day <= GameHistoryService.maxEntries + 5; day++) {
      await history.save(_record(day, name: 'Day $day'));
    }
    final list = await history.list();
    expect(list.length, GameHistoryService.maxEntries);
    // Newest kept, oldest evicted.
    expect(list.first.gameName, 'Day ${GameHistoryService.maxEntries + 5}');
    expect(list.map((r) => r.gameName), isNot(contains('Day 1')));
  });

  test('deletes a single game', () async {
    final keep = _record(1, name: 'Keep');
    final drop = _record(2, name: 'Drop');
    await history.save(keep);
    await history.save(drop);

    await history.delete(drop.id);
    final list = await history.list();
    expect(list.map((r) => r.gameName), ['Keep']);
  });

  test('deleting an unknown id is harmless', () async {
    await history.save(_record(1));
    await history.delete('nope');
    expect((await history.list()).length, 1);
  });

  test('clears everything', () async {
    await history.save(_record(1));
    await history.save(_record(2));
    await history.clearAll();
    expect(await history.list(), isEmpty);
  });

  test(
    'skips individually malformed entries but keeps the good ones',
    () async {
      final good = _record(2, name: 'Good');
      SharedPreferences.setMockInitialValues({
        'turntimer.history': jsonEncode([
          {'garbage': true},
          good.toJson(),
        ]),
      });

      final list = await GameHistoryService().list();
      expect(list.map((r) => r.gameName), ['Good']);
    },
  );

  test('a corrupt log is discarded rather than crashing', () async {
    SharedPreferences.setMockInitialValues({
      'turntimer.history': 'not json at all',
    });
    expect(await GameHistoryService().list(), isEmpty);
  });

  test('survives a round trip through storage', () async {
    await history.save(_record(1, name: 'Catan', score: 10));
    final reloaded = await GameHistoryService().list();
    expect(reloaded.single.gameName, 'Catan');
    expect(reloaded.single.winners.map((p) => p.id), ['a']);
  });

  test('a log written before dice tracking still loads', () async {
    // A pre-1.2.0 entry: version 1, no roll keys.
    final legacy = {
      'version': 1,
      'id': 'g-old',
      'gameName': 'Old game',
      'startedAtMs': DateTime(2026, 1, 1, 20).millisecondsSinceEpoch,
      'endedAtMs': DateTime(2026, 1, 1, 21).millisecondsSinceEpoch,
      'players': [
        {'id': 'a', 'name': 'Ada', 'colorValue': 1},
      ],
    };
    SharedPreferences.setMockInitialValues({
      'turntimer.history': jsonEncode([legacy]),
    });

    final loaded = await GameHistoryService().list();
    expect(loaded.single.gameName, 'Old game');
    expect(loaded.single.hasRolls, isFalse);

    // ...and a new diced game saves alongside it without disturbing it.
    final fresh = GameRecord(
      id: 'g-new',
      gameName: 'Catan',
      startedAt: DateTime(2026, 2, 1, 20),
      endedAt: DateTime(2026, 2, 1, 22),
      players: const [Player(id: 'a', name: 'Ada', colorValue: 1)],
      rollTotals: const [7, 8],
      rollerIndices: const [0, 0],
    );
    await GameHistoryService().save(fresh);

    final both = await GameHistoryService().list();
    expect(both.map((r) => r.gameName), ['Catan', 'Old game']);
    expect(both.first.rollTotals, [7, 8]);
    expect(both.last.hasRolls, isFalse);
  });
}
