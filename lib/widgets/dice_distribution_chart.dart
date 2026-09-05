import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/dice.dart';

/// The 2..12 roll distribution of a finished game, with each total's *expected*
/// count marked on top of what was actually rolled.
///
/// One series (the counts) plus a reference marker, so it needs a single hue:
/// bars are the theme primary, the expectation line is a neutral outline, and
/// every number on the chart is drawn in a text token rather than the series
/// color. Both roles are named in the legend, so nothing is identified by color
/// alone. Light and dark come from the Material 3 scheme, which steps primary
/// against each surface rather than inverting it.
class DiceDistributionChart extends StatelessWidget {
  const DiceDistributionChart({super.key, required this.stats});

  final DiceStats stats;

  static const double _barsHeight = 120;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (stats.isEmpty) return const SizedBox.shrink();

    // Bars start at zero and share one scale that fits the tallest of either
    // the actual counts or the expectation markers.
    final maxExpected = stats.expectedFor(7);
    final scale = math.max(stats.maxCount.toDouble(), maxExpected);
    final hottest = stats.hottest;
    final coldest = stats.coldest;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dice rolls',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${stats.totalRolls} rolls  ·  ${stats.sevens} sevens'
              '${hottest != null ? '  ·  hottest $hottest' : ''}'
              '${coldest != null ? '  ·  coldest $coldest' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            // No fixed height: the row sizes to the label + bar + label stack,
            // so text scaling can never clip it.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var n = kMinRoll; n <= kMaxRoll; n++)
                  Expanded(
                    child: Padding(
                      // >= 2px of surface between neighbouring fills.
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: _Column(
                        total: n,
                        count: stats.countFor(n),
                        expected: stats.expectedFor(n),
                        scale: scale,
                        barsHeight: _barsHeight,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const _Legend(),
          ],
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.total,
    required this.count,
    required this.expected,
    required this.scale,
    required this.barsHeight,
  });

  final int total;
  final int count;
  final double expected;
  final double scale;
  final double barsHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barHeight = scale <= 0
        ? 0.0
        : (count / scale * barsHeight).clamp(count > 0 ? 3.0 : 0.0, barsHeight);
    final expectedY = scale <= 0 ? 0.0 : expected / scale * barsHeight;

    return Semantics(
      label:
          '$total came up $count ${count == 1 ? 'time' : 'times'}, '
          'expected ${expected.toStringAsFixed(1)}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: barsHeight,
            child: Stack(
              children: [
                // Recessive track, so an empty column still reads as a column.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.05,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: (expectedY - 2).clamp(0.0, barsHeight - 4),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline,
                      // A hairline of the card's own surface above and below,
                      // so the marker stays legible where it crosses a bar —
                      // in either theme.
                      border: Border.symmetric(
                        horizontal: BorderSide(
                          color: theme.colorScheme.surfaceContainerLow,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$total',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: total == 7 ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text('Rolled', style: style),
        const SizedBox(width: 16),
        Container(width: 12, height: 2, color: theme.colorScheme.outline),
        const SizedBox(width: 6),
        Expanded(child: Text('Expected for a fair pair of dice', style: style)),
      ],
    );
  }
}
