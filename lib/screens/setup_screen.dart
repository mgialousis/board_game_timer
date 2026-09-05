import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/game_controller.dart';
import '../models/dice_mode.dart';
import '../models/player.dart';
import '../models/screen_mode.dart';
import '../utils/palette.dart';
import '../widgets/player_color_picker.dart';
import 'game_screen.dart';
import 'history_screen.dart';

/// Preset options for the optional soft per-turn time limit.
const List<({String label, Duration duration})> _turnWarningOptions = [
  (label: 'Off', duration: Duration.zero),
  (label: '1 min', duration: Duration(minutes: 1)),
  (label: '2 min', duration: Duration(minutes: 2)),
  (label: '3 min', duration: Duration(minutes: 3)),
  (label: '5 min', duration: Duration(minutes: 5)),
];

/// Screen-behaviour options shown in the settings sheet.
const List<({ScreenMode mode, String title, String subtitle})>
_screenModeOptions = [
  (
    mode: ScreenMode.normal,
    title: 'Normal',
    subtitle: 'Screen sleeps as usual',
  ),
  (
    mode: ScreenMode.keepAwake,
    title: 'Keep screen awake',
    subtitle: 'Display stays on (uses more battery)',
  ),
  (
    mode: ScreenMode.lockedPlay,
    title: 'Locked play (screen off)',
    subtitle: 'Advance turns from the lock screen — most battery-friendly',
  ),
];

/// Editable draft of a player while setting up. The name controller lives here
/// (not rebuilt) so it survives reordering.
class _PlayerDraft {
  _PlayerDraft({
    required this.id,
    required String name,
    required this.colorValue,
  }) : nameController = TextEditingController(text: name);

  final String id;
  final TextEditingController nameController;
  int colorValue;

  void dispose() => nameController.dispose();
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const int _minPlayers = 2;
  static const int _maxPlayers = 8;

  final TextEditingController _gameNameController = TextEditingController();
  final List<_PlayerDraft> _players = [];
  bool _randomizeFirst = false;
  int _seq = 0;

  bool get _supportsLockedPlay =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _addPlayer();
    _addPlayer();
  }

  @override
  void dispose() {
    _gameNameController.dispose();
    for (final p in _players) {
      p.dispose();
    }
    super.dispose();
  }

  int _firstUnusedColor() {
    final used = _players.map((p) => p.colorValue).toSet();
    return kPlayerPalette.firstWhere(
      (c) => !used.contains(c),
      orElse: () => kPlayerPalette[_players.length % kPlayerPalette.length],
    );
  }

  void _addPlayer() {
    if (_players.length >= _maxPlayers) return;
    setState(() {
      _players.add(
        _PlayerDraft(
          id: 'player_${_seq++}',
          name: 'Player ${_players.length + 1}',
          colorValue: _firstUnusedColor(),
        ),
      );
    });
  }

  void _removePlayer(int index) {
    if (_players.length <= _minPlayers) return;
    setState(() {
      _players.removeAt(index).dispose();
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _players.removeAt(oldIndex);
      _players.insert(newIndex, item);
    });
  }

  Future<void> _pickColor(int index) async {
    final chosen = await showColorPickerSheet(
      context,
      _players[index].colorValue,
    );
    if (chosen != null) {
      setState(() => _players[index].colorValue = chosen);
    }
  }

  Future<void> _startGame() async {
    final names = _players.map((p) => p.nameController.text.trim()).toList();
    if (names.any((n) => n.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player names cannot be empty.')),
      );
      return;
    }
    final players = [
      for (var i = 0; i < _players.length; i++)
        Player(
          id: _players[i].id,
          name: names[i],
          colorValue: _players[i].colorValue,
        ),
    ];
    await widget.controller.startGame(
      players: players,
      gameName: _gameNameController.text,
      randomizeFirst: _randomizeFirst,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(controller: widget.controller),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Without this the sheet is capped at 9/16 of the screen and the last
      // rows are unreachable on a phone.
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Settings',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Battery saver'),
                      subtitle: const Text('Disables the active-player pulse'),
                      value: widget.controller.settings.batterySaverMode,
                      onChanged: (v) async {
                        await widget.controller.setBatterySaver(v);
                        setSheetState(() {});
                      },
                    ),
                    const Divider(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Screen during game',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    for (final opt in _screenModeOptions)
                      if (opt.mode != ScreenMode.lockedPlay ||
                          _supportsLockedPlay)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            widget.controller.settings.screenMode == opt.mode
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color:
                                widget.controller.settings.screenMode ==
                                    opt.mode
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                          title: Text(opt.title),
                          subtitle: Text(opt.subtitle),
                          onTap: () async {
                            final applied = await widget.controller
                                .setScreenMode(opt.mode);
                            if (!context.mounted) return;
                            if (!applied) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Locked play needs notifications enabled. '
                                    'Allow them on the lock screen too.',
                                  ),
                                  action: SnackBarAction(
                                    label: 'Settings',
                                    onPressed: widget
                                        .controller
                                        .openNotificationSettings,
                                  ),
                                ),
                              );
                              return;
                            }
                            setSheetState(() {});
                          },
                        ),
                    const Divider(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Turn warning',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Subtle alert once a turn runs long',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final opt in _turnWarningOptions)
                              ChoiceChip(
                                label: Text(opt.label),
                                selected:
                                    widget
                                        .controller
                                        .settings
                                        .turnWarningThreshold ==
                                    opt.duration,
                                onSelected: (_) async {
                                  await widget.controller.setTurnWarning(
                                    opt.duration,
                                  );
                                  setSheetState(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 8),
                    SwitchListTile(
                      key: const Key('dice-toggle'),
                      title: const Text('Track dice rolls'),
                      subtitle: const Text(
                        'Catan-style 2d6. Tap a number to log the roll and pass '
                        'the turn. Rolls can’t be logged from the lock screen.',
                      ),
                      value: widget.controller.settings.diceMode.isOn,
                      onChanged: (v) async {
                        await widget.controller.setDiceMode(
                          v ? DiceMode.twoD6 : DiceMode.off,
                        );
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('TurnTimer'),
        actions: [
          IconButton(
            key: const Key('open-history'),
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryScreen(controller: widget.controller),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Board game turn timer',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _gameNameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Game name (optional)',
                prefixIcon: Icon(Icons.casino_outlined),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('Players', style: theme.textTheme.titleLarge),
                const SizedBox(width: 8),
                Text(
                  '(${_players.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _players.length >= _maxPlayers ? null : _addPlayer,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _players.length,
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final player = _players[index];
                return _PlayerRow(
                  key: ValueKey(player.id),
                  index: index,
                  draft: player,
                  canRemove: _players.length > _minPlayers,
                  onPickColor: () => _pickColor(index),
                  onRemove: () => _removePlayer(index),
                );
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Randomize first player'),
              value: _randomizeFirst,
              onChanged: (v) => setState(() => _randomizeFirst = v),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _startGame,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start game'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    super.key,
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onPickColor,
    required this.onRemove,
  });

  final int index;
  final _PlayerDraft draft;
  final bool canRemove;
  final VoidCallback onPickColor;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final color = Color(draft.colorValue);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator),
                ),
              ),
              GestureDetector(
                onTap: onPickColor,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Icon(Icons.edit, size: 16, color: contrastOn(color)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: draft.nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Name',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove',
                onPressed: canRemove ? onRemove : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
