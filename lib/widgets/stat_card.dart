import 'package:flutter/material.dart';

/// A small labelled statistic, e.g. ("Turns", "5").
typedef StatItem = ({String label, String value});

/// One player's row on the summary screen: a color accent, name, a headline
/// value (total time) and a grid of secondary stats, plus optional highlight
/// badges (e.g. "Slowest").
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.accent,
    required this.title,
    required this.headlineValue,
    required this.headlineLabel,
    required this.stats,
    this.badges = const [],
  });

  final Color accent;
  final String title;
  final String headlineValue;
  final String headlineLabel;
  final List<StatItem> stats;
  final List<String> badges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      headlineValue,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      headlineLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                for (final s in stats)
                  _MiniStat(label: s.label, value: s.value),
              ],
            ),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in badges)
                    Chip(
                      label: Text(b),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      side: BorderSide.none,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

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
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
