import 'package:flutter/material.dart';

import '../models/game_record.dart';
import '../utils/duration_format.dart';
import '../utils/palette.dart';
import 'dice_distribution_chart.dart';
import 'stat_card.dart';

/// Renders a finished game's results: headline totals, the winner (once scores
/// have been entered) and a stat card per player.
///
/// Shared by the post-game results screen and the history detail view so the
/// layout exists in exactly one place.
class GameResultBody extends StatelessWidget {
  const GameResultBody({
    super.key,
    required this.record,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 24),
  });

  final GameRecord record;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slowestTotalId = record.slowestByTotal?.id;
    final slowestAvgId = record.slowestByAverage?.id;
    final mostSevensId = record.mostSevensPlayer?.id;

    return ListView(
      padding: padding,
      children: [
        Text(
          record.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 20,
          runSpacing: 4,
          children: [
            _Headline(
              label: 'Thinking time',
              value: formatCompact(record.totalPlayedTime),
            ),
            _Headline(
              label: 'Game length',
              value: formatCompact(record.gameLength),
            ),
            _Headline(label: 'Players', value: '${record.players.length}'),
            if (record.hasRolls)
              _Headline(label: 'Rolls', value: '${record.rollTotals.length}'),
          ],
        ),
        if (record.hasScores) ...[
          const SizedBox(height: 16),
          WinnerBanner(record: record),
        ],
        // Hidden entirely for games played without dice tracking — which is
        // every game archived before the feature existed.
        if (record.hasRolls) ...[
          const SizedBox(height: 16),
          DiceDistributionChart(
            key: const Key('dice-chart'),
            stats: record.diceStats,
          ),
        ],
        const SizedBox(height: 16),
        for (final p in record.ranked)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StatCard(
              accent: p.color,
              title: p.name,
              headlineValue: p.score != null
                  ? '${p.score}'
                  : formatCompact(p.accumulatedDuration),
              headlineLabel: p.score != null
                  ? 'points'
                  : '${record.percentFor(p).toStringAsFixed(0)}%',
              stats: [
                if (p.score != null)
                  (label: 'Time', value: formatCompact(p.accumulatedDuration)),
                (label: 'Turns', value: '${p.turnCount}'),
                (label: 'Avg turn', value: formatCompact(p.averageTurn)),
                (label: 'Longest', value: formatCompact(p.longestTurn)),
                if (record.hasRolls)
                  (label: 'Rolls', value: '${record.rollCountFor(p)}'),
                if (record.hasRolls)
                  (label: 'Sevens', value: '${record.sevensRolledBy(p)}'),
              ],
              badges: [
                if (record.isWinner(p))
                  record.winners.length > 1 ? 'Tied 1st' : 'Winner',
                if (p.id == slowestTotalId) 'Most time',
                if (p.id == slowestAvgId) 'Slowest avg',
                if (p.id == mostSevensId) 'Most 7s',
              ],
            ),
          ),
      ],
    );
  }
}

/// Highlights who won — or that the game was a draw.
class WinnerBanner extends StatelessWidget {
  const WinnerBanner({super.key, required this.record});

  final GameRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winners = record.winners;
    if (winners.isEmpty) return const SizedBox.shrink();

    final tied = winners.length > 1;
    final names = winners.map((p) => p.name).join(' & ');

    return Container(
      key: const Key('winner-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            tied ? Icons.handshake_outlined : Icons.emoji_events,
            size: 32,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tied ? 'Draw' : 'Winner',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  names,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final w in winners.take(4))
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: w.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: contrastOn(w.color)),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Text(
                '${record.topScore}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
