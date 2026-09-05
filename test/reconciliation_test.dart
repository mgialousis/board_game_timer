import 'package:board_game_timer/controllers/game_controller.dart';
import 'package:board_game_timer/models/player.dart';
import 'package:board_game_timer/models/screen_mode.dart';
import 'package:board_game_timer/services/game_storage_service.dart';
import 'package:board_game_timer/services/live_play_service.dart';
import 'package:board_game_timer/services/screen_wake_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeWake extends ScreenWakeService {
  @override
  Future<void> setEnabled(bool value) async {}
}

/// Stand-in for the platform lock-screen surface: records calls and hands the
/// controller a scripted action log to reconcile.
class FakeLivePlay extends LivePlayService {
  final List<String> calls = [];
  List<LiveAction> pending = [];
  LivePlaySnapshot? lastSnapshot;

  @override
  Future<void> start(LivePlaySnapshot snapshot) async {
    calls.add('start');
    lastSnapshot = snapshot;
  }

  @override
  Future<void> update(LivePlaySnapshot snapshot) async {
    calls.add('update');
    lastSnapshot = snapshot;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<bool> requestPermissions() async {
    calls.add('permissions');
    return true;
  }

  @override
  Future<List<LiveAction>> drainActions() async {
    final out = pending;
    pending = [];
    return out;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime clock;
  late FakeLivePlay livePlay;
  late GameController controller;

  DateTime now() => clock;
  void advance(Duration d) => clock = clock.add(d);
  DateTime at(Duration sinceStart) => DateTime(2026, 1, 1, 12).add(sinceStart);

  List<Player> roster() => const [
    Player(id: 'p0', name: 'P1', colorValue: 0xFFE53935),
    Player(id: 'p1', name: 'P2', colorValue: 0xFF1E88E5),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 1, 1, 12);
    livePlay = FakeLivePlay();
    controller = GameController(
      storage: GameStorageService(),
      wake: FakeWake(),
      livePlay: livePlay,
      clock: now,
    );
  });

  /// Simulates the app being resumed and lets the async reconcile settle.
  Future<void> resumeApp() async {
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
  }

  group('replaying lock-screen actions on resume', () {
    test(
      'folds "next" actions into history with timestamp-accurate durations',
      () async {
        await controller.startGame(players: roster());

        // While backgrounded, the user tapped Next twice from the lock screen:
        // p0's turn ended after 10s, p1's after a further 5s.
        livePlay.pending = [
          LiveAction(LiveActionType.next, at(const Duration(seconds: 10))),
          LiveAction(LiveActionType.next, at(const Duration(seconds: 15))),
        ];
        advance(const Duration(seconds: 20));
        await resumeApp();

        final g = controller.game!;
        expect(g.currentPlayerIndex, 0); // wrapped back around
        expect(g.players[0].accumulatedDuration, const Duration(seconds: 10));
        expect(g.players[0].turnCount, 1);
        expect(g.players[1].accumulatedDuration, const Duration(seconds: 5));
        expect(g.players[1].turnCount, 1);
        expect(g.turnHistory.length, 2);
        // The new in-progress turn started at the second tap (12:00:15), so at
        // 12:00:20 it shows 5s — no time was lost or double counted.
        expect(controller.currentTurnElapsed, const Duration(seconds: 5));
      },
    );

    test('replays pause/resume so no time accumulates in the gap', () async {
      await controller.startGame(players: roster());

      livePlay.pending = [
        LiveAction(LiveActionType.pause, at(const Duration(seconds: 30))),
        LiveAction(LiveActionType.resume, at(const Duration(seconds: 90))),
      ];
      advance(const Duration(seconds: 100));
      await resumeApp();

      expect(controller.isPaused, isFalse);
      // 30s before the pause + 10s since the resume.
      expect(controller.currentTurnElapsed, const Duration(seconds: 40));
    });

    test('a trailing pause leaves the game paused after resume', () async {
      await controller.startGame(players: roster());

      livePlay.pending = [
        LiveAction(LiveActionType.pause, at(const Duration(seconds: 12))),
      ];
      advance(const Duration(minutes: 5));
      await resumeApp();

      expect(controller.isPaused, isTrue);
      expect(controller.currentTurnElapsed, const Duration(seconds: 12));
    });

    test('reconciled state is persisted for the next launch', () async {
      await controller.startGame(players: roster());
      livePlay.pending = [
        LiveAction(LiveActionType.next, at(const Duration(seconds: 7))),
      ];
      advance(const Duration(seconds: 8));
      await resumeApp();

      final reloaded = GameController(
        storage: GameStorageService(),
        wake: FakeWake(),
        livePlay: FakeLivePlay(),
        clock: now,
      );
      await reloaded.init();
      expect(reloaded.currentPlayer!.id, 'p1');
      expect(
        reloaded.game!.players[0].accumulatedDuration,
        const Duration(seconds: 7),
      );
    });

    test('init() also drains actions (app was killed while locked)', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 3));

      // Fresh controller = cold start; the action log survived in the store.
      final fresh = FakeLivePlay()
        ..pending = [
          LiveAction(LiveActionType.next, at(const Duration(seconds: 9))),
        ];
      final restarted = GameController(
        storage: GameStorageService(),
        wake: FakeWake(),
        livePlay: fresh,
        clock: now,
      );
      advance(const Duration(seconds: 10));
      await restarted.init();

      expect(restarted.currentPlayer!.id, 'p1');
      expect(
        restarted.game!.players[0].accumulatedDuration,
        const Duration(seconds: 9),
      );
    });

    test('actions with no active game are dropped without crashing', () async {
      livePlay.pending = [
        LiveAction(LiveActionType.next, at(const Duration(seconds: 5))),
      ];
      await resumeApp();
      expect(controller.game, isNull);
    });

    test('next while paused preserves the pause state', () async {
      await controller.startGame(players: roster());
      livePlay.pending = [
        LiveAction(LiveActionType.pause, at(const Duration(seconds: 5))),
        LiveAction(LiveActionType.next, at(const Duration(seconds: 10))),
      ];
      advance(const Duration(seconds: 20));
      await resumeApp();

      expect(controller.currentPlayer!.id, 'p1');
      expect(controller.isPaused, isTrue);
      expect(controller.currentTurnElapsed, Duration.zero);
    });
  });

  group('lock-screen surface lifecycle', () {
    test(
      'selecting Locked play requests permissions and starts the surface',
      () async {
        await controller.startGame(players: roster());
        await controller.setScreenMode(ScreenMode.lockedPlay);

        expect(livePlay.calls, contains('permissions'));
        expect(livePlay.calls, contains('start'));
        expect(livePlay.lastSnapshot!.currentIndex, 0);
        expect(livePlay.lastSnapshot!.playerColors, [0xFFE53935, 0xFF1E88E5]);
      },
    );

    test('in-app actions keep the surface snapshot in sync', () async {
      await controller.setScreenMode(ScreenMode.lockedPlay);
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 4));
      controller.nextTurn();

      expect(livePlay.calls, contains('update'));
      expect(livePlay.lastSnapshot!.currentIndex, 1);

      controller.pause();
      expect(livePlay.lastSnapshot!.isPaused, isTrue);
    });

    test('ending or discarding the game stops the surface', () async {
      await controller.setScreenMode(ScreenMode.lockedPlay);
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 2));
      await controller.endGame();
      expect(livePlay.calls.last, 'stop');

      await controller.startGame(players: roster());
      livePlay.calls.clear();
      await controller.discardGame();
      expect(livePlay.calls, contains('stop'));
    });

    test('normal mode never starts the surface', () async {
      await controller.startGame(players: roster());
      advance(const Duration(seconds: 3));
      controller.nextTurn();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();

      expect(livePlay.calls.where((c) => c == 'start'), isEmpty);
      expect(livePlay.calls.where((c) => c == 'update'), isEmpty);
    });

    test(
      'denied notification permission leaves the current mode unchanged',
      () async {
        final denied = _DeniedLivePlay();
        final deniedController = GameController(
          storage: GameStorageService(),
          wake: FakeWake(),
          livePlay: denied,
          clock: now,
        );

        final applied = await deniedController.setScreenMode(
          ScreenMode.lockedPlay,
        );

        expect(applied, isFalse);
        expect(deniedController.screenMode, ScreenMode.normal);
        expect(denied.calls, ['permissions']);
      },
    );
  });
}

class _DeniedLivePlay extends FakeLivePlay {
  @override
  Future<bool> requestPermissions() async {
    calls.add('permissions');
    return false;
  }
}
