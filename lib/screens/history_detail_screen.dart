import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/game_controller.dart';
import '../models/game_record.dart';
import '../utils/date_format.dart';
import '../utils/duration_format.dart';
import '../widgets/game_result_body.dart';
import 'game_screen.dart';

/// A past game's full results, rendered with the same body as the post-game
/// results screen.
class HistoryDetailScreen extends StatelessWidget {
  const HistoryDetailScreen({
    super.key,
    required this.controller,
    required this.record,
  });

  final GameController controller;
  final GameRecord record;

  String _buildShareText() {
    final buffer = StringBuffer();
    buffer.writeln('${record.title} — TurnTimer results');
    buffer.writeln(formatDateTime(record.endedAt));
    if (record.hasScores) {
      final winners = record.winners;
      final label = winners.length > 1 ? 'Draw' : 'Winner';
      buffer.writeln(
        '$label: ${winners.map((p) => p.name).join(' & ')} (${record.topScore})',
      );
    }
    buffer.writeln('');
    var rank = 1;
    for (final p in record.ranked) {
      final score = p.score != null ? '${p.score} pts · ' : '';
      buffer.writeln(
        '$rank. ${p.name}: $score${formatCompact(p.accumulatedDuration)} '
        '· ${p.turnCount} turns',
      );
      rank++;
    }
    return buffer.toString();
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _buildShareText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Results copied')));
  }

  /// Starts a brand new game with this game's line-up (names and colors).
  Future<void> _playAgain(BuildContext context) async {
    if (controller.hasActiveGame) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current game?'),
          content: const Text(
            'A game is already in progress. Starting this line-up will '
            'discard it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start anyway'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await controller.startGame(
      players: record.players,
      gameName: record.gameName,
    );
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => GameScreen(controller: controller)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(formatPlayedAt(record.endedAt)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy results',
            onPressed: () => _copy(context),
          ),
        ],
      ),
      body: GameResultBody(
        record: record,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: () => _playAgain(context),
            icon: const Icon(Icons.replay),
            label: const Text('Play again with these players'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
        ),
      ),
    );
  }
}
