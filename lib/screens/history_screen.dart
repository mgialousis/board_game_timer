import 'package:flutter/material.dart';

import '../controllers/game_controller.dart';
import '../models/game_record.dart';
import '../utils/date_format.dart';
import '../utils/duration_format.dart';
import 'history_detail_screen.dart';

/// The log of finished games, newest first.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<GameRecord>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await widget.controller.loadHistory();
    if (!mounted) return;
    setState(() => _records = records);
  }

  Future<void> _delete(GameRecord record) async {
    await widget.controller.deleteHistoryEntry(record.id);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    // Deleting is instant rather than gated behind a dialog, so offer an undo:
    // the record is still in memory and keeps its id, so restoring puts it
    // back exactly where it was.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${record.title}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await widget.controller.restoreHistoryEntry(record);
              if (mounted) await _load();
            },
          ),
        ),
      );
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'All past games will be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.clearHistory();
    if (!mounted) return;
    await _load();
  }

  Future<void> _open(GameRecord record) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            HistoryDetailScreen(controller: widget.controller, record: record),
      ),
    );
    // Scores may have changed elsewhere; refresh on the way back.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (records != null && records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear history',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: switch (records) {
        null => const Center(child: CircularProgressIndicator()),
        [] => const _EmptyHistory(),
        _ => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: records.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _HistoryCard(
              record: records[i],
              onTap: () => _open(records[i]),
              onDelete: () => _delete(records[i]),
            ),
          ),
        ),
      },
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No games yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Finished games appear here with their times and scores.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  final GameRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winners = record.winners;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      record.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                  ),
                ],
              ),
              Text(
                formatPlayedAt(record.endedAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              if (winners.isNotEmpty)
                Row(
                  children: [
                    Icon(
                      winners.length > 1
                          ? Icons.handshake_outlined
                          : Icons.emoji_events,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${winners.map((p) => p.name).join(' & ')} '
                        '· ${record.topScore} pts',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'No scores recorded',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final p in record.players.take(8))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: p.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '${record.players.length} players · '
                    '${formatCompact(record.gameLength)}'
                    '${record.hasRolls ? ' · ${record.rollTotals.length} rolls' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
