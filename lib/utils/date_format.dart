// Minimal date formatting for the history log.
//
// Deliberately dependency-free: `intl` would pull in a large package (and
// locale data) for what amounts to two short strings.

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// e.g. `12 Aug 2026, 14:05`.
String formatDateTime(DateTime dt) =>
    '${dt.day} ${_months[dt.month - 1]} ${dt.year}, '
    '${_two(dt.hour)}:${_two(dt.minute)}';

/// Friendlier label for recent games: `Today, 14:05` / `Yesterday, 21:30`,
/// falling back to the full date.
String formatPlayedAt(DateTime dt, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(day).inDays;
  final time = '${_two(dt.hour)}:${_two(dt.minute)}';
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Yesterday, $time';
  return formatDateTime(dt);
}
