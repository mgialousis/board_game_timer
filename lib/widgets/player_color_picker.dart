import 'package:flutter/material.dart';

import '../utils/palette.dart';

/// A wrap of selectable color swatches drawn from [kPlayerPalette].
class PlayerColorPicker extends StatelessWidget {
  const PlayerColorPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final value in kPlayerPalette)
          _Swatch(
            value: value,
            isSelected: value == selected,
            onTap: () => onSelected(value),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  final int value;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(value);
    return Semantics(
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            // Always outline the swatch so light colors (white!) stay visible
            // on a light surface; the selected one gets a stronger ring.
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outlineVariant,
              width: isSelected ? 3 : 1.5,
            ),
          ),
          child: isSelected
              ? Icon(Icons.check, color: contrastOn(color))
              : null,
        ),
      ),
    );
  }
}

/// Presents the palette in a modal bottom sheet and resolves to the chosen
/// color value, or null if dismissed.
Future<int?> showColorPickerSheet(BuildContext context, int current) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pick a color',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              PlayerColorPicker(
                selected: current,
                onSelected: (value) => Navigator.of(context).pop(value),
              ),
            ],
          ),
        ),
      );
    },
  );
}
