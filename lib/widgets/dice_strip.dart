import 'package:flutter/material.dart';

import '../utils/dice.dart';

/// The result of the roll-correction sheet: null means "cancelled", while a
/// [RollEdit] with a null [total] means "remove the roll".
class RollEdit {
  const RollEdit(this.total);
  final int? total;
}

/// The in-game dice bar: eleven number buttons that double as a live histogram
/// of what has been rolled so far.
///
/// It lives *below* the full-screen tap area rather than inside it, so a number
/// tap can never also register as "pass the turn". Nothing here rebuilds on the
/// per-second tick — only on a roll or a turn change.
class DiceStrip extends StatelessWidget {
  const DiceStrip({
    super.key,
    required this.stats,
    required this.currentRoll,
    required this.currentPlayerName,
    required this.nextPlayerName,
    required this.foreground,
    required this.onRoll,
    required this.onEditRoll,
  });

  final DiceStats stats;

  /// The roll already logged for the turn in progress, if any. This is what
  /// decides whether a number tap logs or passes — and the header says which.
  final int? currentRoll;

  final String currentPlayerName;
  final String nextPlayerName;

  /// Contrast color for the active player's background.
  final Color foreground;

  final ValueChanged<int> onRoll;
  final VoidCallback onEditRoll;

  static const double _barHeight = 34;

  @override
  Widget build(BuildContext context) {
    final rolled = currentRoll != null;
    final muted = foreground.withValues(alpha: 0.75);
    final scale = stats.maxCount == 0 ? 1 : stats.maxCount;

    return Container(
      key: const Key('dice-strip'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.10),
        border: Border(
          top: BorderSide(color: foreground.withValues(alpha: 0.15)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 30,
            child: rolled
                ? _CurrentRollChip(
                    key: const Key('dice-current-roll'),
                    roll: currentRoll!,
                    playerName: currentPlayerName,
                    nextPlayerName: nextPlayerName,
                    foreground: foreground,
                    onTap: onEditRoll,
                  )
                : Center(
                    child: Text(
                      'Tap $currentPlayerName’s roll',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var n = kMinRoll; n <= kMaxRoll; n++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: _RollButton(
                      total: n,
                      count: stats.countFor(n),
                      scale: scale,
                      barHeight: _barHeight,
                      foreground: foreground,
                      onTap: () => onRoll(n),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentRollChip extends StatelessWidget {
  const _CurrentRollChip({
    super.key,
    required this.roll,
    required this.playerName,
    required this.nextPlayerName,
    required this.foreground,
    required this.onTap,
  });

  final int roll;
  final String playerName;
  final String nextPlayerName;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '$playerName rolled $roll',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.edit,
                size: 14,
                color: foreground.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '→ $nextPlayerName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RollButton extends StatelessWidget {
  const _RollButton({
    required this.total,
    required this.count,
    required this.scale,
    required this.barHeight,
    required this.foreground,
    required this.onTap,
  });

  final int total;
  final int count;
  final int scale;
  final double barHeight;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = count == 0
        ? 0.0
        : (count / scale * barHeight).clamp(3.0, barHeight);

    return Semantics(
      button: true,
      label: 'Roll $total, rolled $count ${count == 1 ? 'time' : 'times'}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('dice-btn-$total'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: barHeight + 18,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              // The count so far, growing from the bottom of the button.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: fill,
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: 0.30),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(6),
                      top: Radius.circular(4),
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  '$total',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: total == 7 ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for fixing a mistyped roll: pick another number, or remove it.
Future<RollEdit?> showRollEditSheet(BuildContext context, int current) {
  return showModalBottomSheet<RollEdit>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Correct this roll',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Currently $current. Pick the right number, or remove it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var n = kMinRoll; n <= kMaxRoll; n++)
                    ChoiceChip(
                      key: Key('fix-roll-$n'),
                      label: Text('$n'),
                      selected: n == current,
                      onSelected: (_) => Navigator.pop(context, RollEdit(n)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    key: const Key('remove-roll'),
                    onPressed: () =>
                        Navigator.pop(context, const RollEdit(null)),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove roll'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
