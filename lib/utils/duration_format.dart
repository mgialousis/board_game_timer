// Pure formatting helpers for [Duration] values shown in the UI.
//
// Every formatter clamps negative durations to zero. The timer logic should
// never produce a negative value, but clamping here is a cheap last line of
// defence for the "no negative durations" requirement.

String _two(int n) => n.toString().padLeft(2, '0');

/// Clock style used for the big live timers: `mm:ss` or `h:mm:ss`.
String formatClock(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${_two(minutes)}:${_two(seconds)}';
  }
  return '${_two(minutes)}:${_two(seconds)}';
}

/// Compact human style used in statistics: `1h 2m 3s`, `2m 3s`, `3s`.
String formatCompact(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final parts = <String>[];
  if (hours > 0) parts.add('${hours}h');
  if (minutes > 0) parts.add('${minutes}m');
  if (seconds > 0 || parts.isEmpty) parts.add('${seconds}s');
  return parts.join(' ');
}
