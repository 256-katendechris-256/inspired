import 'package:flutter_test/flutter_test.dart';
import 'package:inspired/core/working_days.dart';

void main() {
  // 2026-09-21 is a Monday, 2026-09-26 a Saturday, 2026-09-27 a Sunday.
  DateTime d(int day) => DateTime(2026, 9, day);

  test('Monday to Saturday is a full six-day week', () {
    expect(countWorkingDays(d(21), d(26), {}), 6);
  });

  test('Sunday costs nothing', () {
    expect(countWorkingDays(d(27), d(27), {}), 0);
    // Saturday through Monday spans three days but only two are worked.
    expect(countWorkingDays(d(26), d(28), {}), 2);
  });

  test('a gazetted holiday is skipped', () {
    expect(countWorkingDays(d(21), d(23), {'2026-09-22'}), 2);
  });

  test('a single working day counts as one', () {
    expect(countWorkingDays(d(21), d(21), {}), 1);
  });

  test('an inverted range is zero, not negative', () {
    expect(countWorkingDays(d(26), d(21), {}), 0);
  });

  test('calendar days count every day in the span', () {
    expect(countCalendarDays(d(26), d(28)), 3);
    expect(countCalendarDays(d(21), d(21)), 1);
  });

  test('the time of day never changes the count', () {
    expect(
      countWorkingDays(
        DateTime(2026, 9, 21, 23, 59),
        DateTime(2026, 9, 22, 0, 1),
        {},
      ),
      2,
    );
  });
}
