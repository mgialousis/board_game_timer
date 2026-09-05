import 'package:board_game_timer/utils/duration_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatClock', () {
    test('formats minutes and seconds with zero padding', () {
      expect(formatClock(const Duration(seconds: 5)), '00:05');
      expect(formatClock(const Duration(minutes: 5, seconds: 23)), '05:23');
      expect(formatClock(const Duration(minutes: 12, seconds: 3)), '12:03');
    });

    test('includes hours when >= 1 hour', () {
      expect(
        formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('clamps negative durations to zero', () {
      expect(formatClock(const Duration(seconds: -10)), '00:00');
    });
  });

  group('formatCompact', () {
    test('drops empty leading units', () {
      expect(formatCompact(const Duration(seconds: 3)), '3s');
      expect(formatCompact(const Duration(minutes: 2, seconds: 3)), '2m 3s');
      expect(
        formatCompact(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1h 2m 3s',
      );
    });

    test('shows 0s for zero', () {
      expect(formatCompact(Duration.zero), '0s');
    });

    test('clamps negative durations to zero', () {
      expect(formatCompact(const Duration(seconds: -5)), '0s');
    });
  });
}
