import 'package:board_game_timer/utils/dice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('probabilities', () {
    test('the ways-to-roll table covers 2..12 and sums to 36', () {
      expect(kWaysToRoll.keys.toList(), [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      expect(kWaysToRoll.values.reduce((a, b) => a + b), 36);
      expect(kWaysToRoll[7], 6); // the most likely total
      expect(kWaysToRoll[2], 1);
      expect(kWaysToRoll[12], 1);
      // Symmetric around 7.
      for (var n = 2; n <= 7; n++) {
        expect(kWaysToRoll[n], kWaysToRoll[14 - n]);
      }
    });

    test('expected counts scale with the number of rolls', () {
      expect(expectedCount(7, 36), closeTo(6, 1e-9));
      expect(expectedCount(8, 36), closeTo(5, 1e-9));
      expect(expectedCount(2, 72), closeTo(2, 1e-9));
      expect(expectedCount(7, 0), 0);
    });

    test('validity is bounded to a two-dice total', () {
      expect(isValidRoll(2), isTrue);
      expect(isValidRoll(12), isTrue);
      expect(isValidRoll(1), isFalse);
      expect(isValidRoll(13), isFalse);
      expect(isValidRoll(0), isFalse);
    });
  });

  group('DiceStats', () {
    test('counts each total and ignores corrupt entries', () {
      final s = DiceStats.from([7, 8, 7, 5, 99, 7, 1]);
      expect(s.totalRolls, 5); // 99 and 1 are not possible totals
      expect(s.countFor(7), 3);
      expect(s.countFor(8), 1);
      expect(s.countFor(5), 1);
      expect(s.countFor(2), 0);
      expect(s.maxCount, 3);
      expect(s.sevens, 3);
      expect(s.isEmpty, isFalse);
    });

    test('an empty game has no distribution', () {
      final s = DiceStats.from(const []);
      expect(s.isEmpty, isTrue);
      expect(s.totalRolls, 0);
      expect(s.maxCount, 0);
      expect(s.hottest, isNull);
      expect(s.coldest, isNull);
      expect(s.expectedFor(7), 0);
    });

    test('deviation compares against the expected count', () {
      // 36 rolls of nothing but 7s: 7 is 30 above expectation, and every other
      // total is short by exactly its own expectation.
      final s = DiceStats.from(List.filled(36, 7));
      expect(s.expectedFor(7), closeTo(6, 1e-9));
      expect(s.deviationFor(7), closeTo(30, 1e-9));
      expect(s.deviationFor(6), closeTo(-5, 1e-9));
      expect(s.hottest, 7);
      expect(s.coldest, anyOf(6, 8)); // the biggest shortfall after 7
    });

    test('attributes sevens to the player who rolled them', () {
      final s = DiceStats.from([7, 8, 7, 7, 4], [0, 1, 0, 2, 1]);
      expect(s.sevensByPlayerIndex, {0: 2, 2: 1});
      expect(s.mostSevensPlayerIndex, 0);
    });

    test('a tie for most sevens is nobody', () {
      final s = DiceStats.from([7, 7], [0, 1]);
      expect(s.mostSevensPlayerIndex, isNull);
    });

    test('rolls without attribution still count', () {
      final s = DiceStats.from([7, 7]);
      expect(s.sevens, 2);
      expect(s.sevensByPlayerIndex, isEmpty);
      expect(s.mostSevensPlayerIndex, isNull);
    });
  });
}
