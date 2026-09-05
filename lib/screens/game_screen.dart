import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/game_controller.dart';
import '../services/warning_sound_service.dart';
import '../utils/duration_format.dart';
import '../utils/palette.dart';
import '../widgets/dice_strip.dart';
import '../widgets/timer_display.dart';
import 'setup_screen.dart';
import 'summary_screen.dart';

/// The active-game screen.
///
/// Battery-conscious by construction:
/// * A single 1-second [Timer] bumps a [ValueNotifier]; only the timer texts
///   listen to it, so the rest of the tree is not rebuilt every second.
/// * The pulse [AnimationController] runs only while a game is actively running
///   AND battery saver is off AND the app is foregrounded.
/// * Both are stopped on pause, when the app is backgrounded, and when the game
///   ends, so nothing animates or ticks needlessly.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _tapDebounce = Duration(milliseconds: 500);

  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  late final AnimationController _pulse;
  Timer? _ticker;
  bool _foreground = true;
  DateTime? _lastAdvance;
  final WarningSoundService _sound = WarningSoundService();

  GameController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
      lowerBound: 0,
      upperBound: 1,
    );
    _controller.addListener(_onControllerChanged);
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _ticker?.cancel();
    _pulse.dispose();
    _tick.dispose();
    _sound.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  /// Starts/stops the per-second ticker and the pulse to match current state.
  void _sync() {
    final shouldTick =
        _controller.hasActiveGame && !_controller.isPaused && _foreground;

    if (shouldTick && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    } else if (!shouldTick && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }

    final shouldPulse = shouldTick && !_controller.batterySaverMode;
    if (shouldPulse) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      if (_pulse.isAnimating) _pulse.stop();
      _pulse.value = 0;
    }
  }

  void _onTick() {
    _tick.value++;
    // Fire one soft haptic the moment a turn first crosses the warning
    // threshold. The visual warning is the reliable signal; this is a bonus.
    // The single-second window means it fires once per crossing and not again
    // on resume (elapsed is already well past the window by then).
    final limit = _controller.turnWarningThreshold;
    if (limit == Duration.zero) return;
    final elapsed = _controller.currentTurnElapsed;
    if (elapsed >= limit && elapsed < limit + const Duration(seconds: 1)) {
      HapticFeedback.mediumImpact();
      _sound.play();
    }
  }

  void _haptic([_Haptic kind = _Haptic.light]) {
    switch (kind) {
      case _Haptic.light:
        HapticFeedback.lightImpact();
      case _Haptic.medium:
        HapticFeedback.mediumImpact();
    }
  }

  void _handleTap() {
    if (!_controller.hasActiveGame) return;
    if (_controller.isPaused) {
      _controller.resume();
      _haptic();
      return;
    }
    // Debounce to swallow accidental double-taps without feeling sluggish.
    final now = DateTime.now();
    if (_lastAdvance != null && now.difference(_lastAdvance!) < _tapDebounce) {
      return;
    }
    _lastAdvance = now;
    _controller.nextTurn();
    _haptic();
  }

  void _handleLongPress() {
    if (!_controller.hasActiveGame) return;
    _controller.togglePause();
    _haptic(_Haptic.medium);
  }

  /// A number on the dice strip. The controller decides whether this logs the
  /// active player's roll or passes the turn and logs the next player's — but
  /// either way it is one tap, and it gets the same debounce as the tap area.
  void _handleRoll(int total) {
    if (!_controller.hasActiveGame || _controller.isPaused) return;
    final now = DateTime.now();
    if (_lastAdvance != null && now.difference(_lastAdvance!) < _tapDebounce) {
      return;
    }
    _lastAdvance = now;
    _controller.tapRoll(total);
    _haptic();
  }

  Future<void> _editCurrentRoll() async {
    final current = _controller.currentTurnRoll;
    if (current == null) return;
    final edit = await showRollEditSheet(context, current);
    if (edit == null || !mounted) return;
    _controller.amendRoll(edit.total);
    _haptic();
  }

  /// Hands the turn to a player of your choosing instead of the next in order —
  /// what Catan's snake-order setup needs (including the same player twice).
  Future<void> _passTurnTo() async {
    final game = _controller.game;
    if (game == null || game.isFinished) return;
    final index = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pass turn to…',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < game.players.length; i++)
              ListTile(
                key: Key('pass-to-${game.players[i].id}'),
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: game.players[i].color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                title: Text(game.players[i].name),
                subtitle: i == game.currentPlayerIndex
                    ? const Text('Again — ends this turn, starts a new one')
                    : (i == game.nextPlayerIndex
                          ? const Text('Next in order')
                          : null),
                onTap: () => Navigator.pop(context, i),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (index == null || !mounted) return;
    _lastAdvance = DateTime.now();
    _controller.passTurnTo(index);
    _haptic();
  }

  Future<void> _confirmEnd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End game?'),
        content: const Text('This will finish the game and show the results.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End game'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _controller.endGame();
    final result = _controller.lastResult;
    if (!mounted || result == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SummaryScreen(
          controller: _controller,
          result: result,
          // Ask for the final scores straight after the game ends.
          promptForScores: true,
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard game?'),
        content: const Text(
          'The current game will be lost. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _controller.discardGame();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SetupScreen(controller: _controller)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = _controller.game;
    if (game == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final player = _controller.currentPlayer!;
    final background = player.color;
    final foreground = contrastOn(background);
    final isPaused = _controller.isPaused;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  key: const Key('game-tap-area'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleTap,
                  onLongPress: _handleLongPress,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    color: background,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        _MainContent(
                          controller: _controller,
                          foreground: foreground,
                          tick: _tick,
                          pulse: _pulse,
                          onPassTurnTo: _passTurnTo,
                        ),
                        if (isPaused) _PausedOverlay(foreground: foreground),
                      ],
                    ),
                  ),
                ),
              ),
              if (_controller.diceEnabled && !isPaused)
                DiceStrip(
                  stats: _controller.liveDiceStats,
                  currentRoll: _controller.currentTurnRoll,
                  currentPlayerName: player.name,
                  nextPlayerName: _controller.nextPlayer?.name ?? '',
                  foreground: foreground,
                  onRoll: _handleRoll,
                  onEditRoll: _editCurrentRoll,
                ),
              _ControlBar(
                controller: _controller,
                onUndo: () {
                  _controller.undo();
                  _haptic();
                },
                onPauseToggle: () {
                  _controller.togglePause();
                  _haptic(_Haptic.medium);
                },
                onSkip: () {
                  _controller.skipPlayer();
                  _haptic();
                },
                onEnd: _confirmEnd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Haptic { light, medium }

class _MainContent extends StatelessWidget {
  const _MainContent({
    required this.controller,
    required this.foreground,
    required this.tick,
    required this.pulse,
    required this.onPassTurnTo,
  });

  final GameController controller;
  final Color foreground;
  final ValueNotifier<int> tick;
  final AnimationController pulse;
  final VoidCallback onPassTurnTo;

  @override
  Widget build(BuildContext context) {
    final game = controller.game!;
    final player = controller.currentPlayer!;
    final next = controller.nextPlayer!;
    final muted = foreground.withValues(alpha: 0.75);

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        // Subtle breathing: at most a 3% scale. Stays at 1.0 when not pulsing.
        return Transform.scale(scale: 1 + 0.03 * pulse.value, child: child);
      },
      // Centered when there is room, scrollable when there isn't: the dice
      // strip eats ~100px, which is enough to overflow a short screen.
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (game.gameName.isNotEmpty)
                Text(
                  game.gameName,
                  style: TextStyle(
                    color: muted,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'CURRENT PLAYER',
                style: TextStyle(
                  color: muted,
                  fontSize: 14,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  player.name,
                  key: const Key('current-player-name'),
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Only these two timers rebuild every second.
              ValueListenableBuilder<int>(
                valueListenable: tick,
                builder: (context, _, _) {
                  final limit = controller.turnWarningThreshold;
                  final overLimit = controller.isCurrentTurnOverLimit;
                  return Column(
                    children: [
                      TimerDisplay(
                        duration: controller.currentTurnElapsed,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 96,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total ${formatCompact(controller.currentPlayerTotal)}'
                        '  ·  ${player.turnCount} turns',
                        style: TextStyle(color: muted, fontSize: 18),
                      ),
                      if (limit > Duration.zero && overLimit) ...[
                        const SizedBox(height: 14),
                        _TurnWarningPill(limit: limit),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
              _NextPlayerPill(
                name: next.name,
                color: next.color,
                foreground: foreground,
                onTap: onPassTurnTo,
              ),
              const SizedBox(height: 8),
              Text(
                controller.diceEnabled
                    ? 'Tap a number below to log the roll  ·  tap here to pass '
                          'without one  ·  long-press to pause'
                    : 'Tap anywhere to end turn  ·  long-press to pause',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnWarningPill extends StatelessWidget {
  const _TurnWarningPill({required this.limit});

  final Duration limit;

  @override
  Widget build(BuildContext context) {
    // Amber pill with its own dark text, so it stays readable on top of any
    // player background color.
    return Container(
      key: const Key('turn-warning'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC107).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hourglass_bottom, size: 18, color: Colors.black87),
          const SizedBox(width: 6),
          Text(
            'Long turn · over ${formatClock(limit)}',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextPlayerPill extends StatelessWidget {
  const _NextPlayerPill({
    required this.name,
    required this.color,
    required this.foreground,
    required this.onTap,
  });

  final String name;
  final Color color;
  final Color foreground;

  /// Opens the "pass turn to…" picker. Its own tap recognizer wins over the
  /// full-screen one behind it, so choosing a player never also advances.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('next-player-pill'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Next: ',
              style: TextStyle(color: foreground.withValues(alpha: 0.8)),
            ),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: foreground.withValues(alpha: 0.5)),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.swap_horiz,
              size: 16,
              color: foreground.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _PausedOverlay extends StatelessWidget {
  const _PausedOverlay({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.pause_circle_filled,
                size: 88,
                color: Colors.white,
              ),
              const SizedBox(height: 12),
              const Text(
                'PAUSED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap to resume',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.controller,
    required this.onUndo,
    required this.onPauseToggle,
    required this.onSkip,
    required this.onEnd,
  });

  final GameController controller;
  final VoidCallback onUndo;
  final VoidCallback onPauseToggle;
  final VoidCallback onSkip;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paused = controller.isPaused;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Row(
          children: [
            _ControlButton(
              icon: Icons.undo,
              label: 'Undo',
              onPressed: controller.canUndo ? onUndo : null,
            ),
            _ControlButton(
              icon: paused ? Icons.play_arrow : Icons.pause,
              label: paused ? 'Resume' : 'Pause',
              onPressed: onPauseToggle,
            ),
            _ControlButton(
              icon: Icons.skip_next,
              label: 'Skip',
              onPressed: onSkip,
            ),
            _ControlButton(
              icon: Icons.flag,
              label: 'End',
              color: theme.colorScheme.error,
              onPressed: onEnd,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = onPressed == null
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : (color ?? theme.colorScheme.onSurface);
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 26),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
