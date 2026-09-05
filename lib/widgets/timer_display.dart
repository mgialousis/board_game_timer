import 'package:flutter/material.dart';

import '../utils/duration_format.dart';

/// Shows a [Duration] in clock form. Uses tabular (monospaced) figures so the
/// digits don't shift width as the seconds tick, which keeps the big timer
/// visually stable and avoids per-second relayout.
class TimerDisplay extends StatelessWidget {
  const TimerDisplay({super.key, required this.duration, required this.style});

  final Duration duration;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        formatClock(duration),
        maxLines: 1,
        style: style.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
