import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/game_controller.dart';
import '../models/game_record.dart';
import '../utils/duration_format.dart';
import '../widgets/game_result_body.dart';
import '../widgets/score_entry_sheet.dart';
import 'game_screen.dart';
import 'setup_screen.dart';

/// Post-game results. Renders the frozen [result] record (stable even once the
/// controller starts another game) and uses the controller only for actions:
/// entering scores, rematching, or starting fresh.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({
    super.key,
    required this.controller,
    required this.result,
    this.promptForScores = false,
  });

  final GameController controller;
  final GameRecord result;

  /// Opens the score sheet as soon as the screen appears — used when arriving
  /// straight from ending a game.
  final bool promptForScores;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late GameRecord _record = widget.result;

  @override
  void initState() {
    super.initState();
    if (widget.promptForScores) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editScores();
      });
    }
  }

  Future<void> _editScores() async {
    final scores = await showScoreEntrySheet(context, _record);
    if (scores == null || !mounted) return;
    await widget.controller.setScores(scores);
    if (!mounted) return;
    setState(() => _record = widget.controller.lastResult ?? _record);
  }

  String _buildShareText() {
    final buffer = StringBuffer();
    buffer.writeln('${_record.title} — TurnTimer results');
    if (_record.hasScores) {
      final winners = _record.winners;
      final label = winners.length > 1 ? 'Draw' : 'Winner';
      buffer.writeln(
        '$label: ${winners.map((p) => p.name).join(' & ')} '
        '(${_record.topScore})',
      );
    }
    buffer.writeln(
      'Total thinking time: ${formatCompact(_record.totalPlayedTime)}',
    );
    buffer.writeln('');
    var rank = 1;
    for (final p in _record.ranked) {
      final score = p.score != null ? '${p.score} pts · ' : '';
      final pct = _record.percentFor(p).toStringAsFixed(0);
      buffer.writeln(
        '$rank. ${p.name}: $score${formatCompact(p.accumulatedDuration)} '
        '($pct%) · ${p.turnCount} turns · avg ${formatCompact(p.averageTurn)} '
        '· longest ${formatCompact(p.longestTurn)}',
      );
      rank++;
    }
    return buffer.toString();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _buildShareText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Summary copied to clipboard')),
    );
  }

  Future<void> _rematch() async {
    await widget.controller.rematchSamePlayers();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(controller: widget.controller),
      ),
    );
  }

  Future<void> _newGame() async {
    await widget.controller.discardGame();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SetupScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _newGame();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Results'),
          actions: [
            IconButton(
              key: const Key('edit-scores'),
              icon: const Icon(Icons.scoreboard_outlined),
              tooltip: _record.hasScores ? 'Edit scores' : 'Add scores',
              onPressed: _editScores,
            ),
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: 'Copy summary',
              onPressed: _copy,
            ),
          ],
        ),
        body: GameResultBody(
          record: _record,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _newGame,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('New game'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _rematch,
                    icon: const Icon(Icons.replay),
                    label: const Text('Rematch'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
