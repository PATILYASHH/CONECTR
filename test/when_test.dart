import 'package:conectr/core/format/when.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // intl puts a narrow no-break space (U+202F) before AM/PM.
  final now = DateTime(2026, 10, 24, 15);

  String at(DateTime t) => formatWhen(t, now: now);

  test('under a minute is "Just now"', () {
    expect(at(now.subtract(const Duration(seconds: 30))), 'Just now');
  });

  test('under an hour counts minutes', () {
    expect(at(now.subtract(const Duration(minutes: 5))), '5 min ago');
  });

  test('earlier today shows the time', () {
    expect(at(DateTime(2026, 10, 24, 9, 40)), 'Today, 9:40 AM');
  });

  test('yesterday says so', () {
    expect(at(DateTime(2026, 10, 23, 18, 2)), 'Yesterday, 6:02 PM');
  });

  test('this year shows day and month', () {
    expect(at(DateTime(2026, 9, 3, 8, 5)), 'Sep 3, 8:05 AM');
  });

  test('another year shows the full date', () {
    expect(at(DateTime(2025, 12, 31, 23)), 'Dec 31, 2025');
  });
}
