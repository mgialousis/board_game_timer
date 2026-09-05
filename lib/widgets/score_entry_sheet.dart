import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_record.dart';

/// Only ever produces a valid score string: an optional minus sign followed by
/// up to six digits (some games score below zero). An empty field is allowed
/// and means "not scored".
final TextInputFormatter _scoreFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) =>
      RegExp(r'^-?\d{0,6}$').hasMatch(newValue.text) ? newValue : oldValue,
);

/// Asks for each player's final score.
///
/// Resolves to a map of player id → score (null clears one), or null if the
/// player dismissed or skipped — scoring is optional.
Future<Map<String, int?>?> showScoreEntrySheet(
  BuildContext context,
  GameRecord record,
) {
  return showModalBottomSheet<Map<String, int?>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ScoreEntrySheet(record: record),
  );
}

class _ScoreEntrySheet extends StatefulWidget {
  const _ScoreEntrySheet({required this.record});

  final GameRecord record;

  @override
  State<_ScoreEntrySheet> createState() => _ScoreEntrySheetState();
}

class _ScoreEntrySheetState extends State<_ScoreEntrySheet> {
  late final Map<String, TextEditingController> _controllers = {
    for (final p in widget.record.players)
      p.id: TextEditingController(text: p.score?.toString() ?? ''),
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final scores = <String, int?>{
      for (final entry in _controllers.entries)
        // A blank (or lone "-") field leaves that player unscored.
        entry.key: int.tryParse(entry.value.text.trim()),
    };
    Navigator.of(context).pop(scores);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final players = widget.record.players;

    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Final scores', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Highest score wins. Leave blank to skip a player.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < players.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: players[i].color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            players[i].name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            key: Key('score-field-${players[i].id}'),
                            controller: _controllers[players[i].id],
                            autofocus: i == 0,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                            ),
                            inputFormatters: [_scoreFormatter],
                            textInputAction: i == players.length - 1
                                ? TextInputAction.done
                                : TextInputAction.next,
                            onSubmitted: (_) {
                              if (i == players.length - 1) _save();
                            },
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '—',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: const Text('Skip'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('save-scores'),
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: const Text('Save scores'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
