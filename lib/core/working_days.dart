/// The working-day rule, client side.
///
/// The server is authoritative: `LeaveRequest.days` is what gets stored and
/// approved, computed by apps/core/calendar.py. This exists only so the form
/// can show the cost of a date range as it is picked, without a round trip
/// per tap. Keep the two in step — the rule is deliberately small.
///
/// The week is Monday–Saturday. Sundays are rest days, and gazetted public
/// holidays don't count either, so Saturday-to-Monday costs 2 days, not 3.
library;

/// "YYYY-MM-DD" for [d], the key public holidays arrive under.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Whether [d] is a day this employer expects work on.
bool isWorkingDay(DateTime d, Set<String> holidays) =>
    d.weekday != DateTime.sunday && !holidays.contains(isoDate(d));

/// Working days in [start]..[end] inclusive. Returns 0 if the range is
/// inverted, so a half-filled form never shows a negative cost.
int countWorkingDays(DateTime start, DateTime end, Set<String> holidays) {
  final from = DateTime(start.year, start.month, start.day);
  final to = DateTime(end.year, end.month, end.day);
  if (to.isBefore(from)) return 0;
  var days = 0;
  // Step by calendar day rather than adding 24 hours, which would drift
  // across a DST boundary.
  for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    if (isWorkingDay(d, holidays)) days++;
  }
  return days;
}

/// Every day in the range, working or not — what "you'll be away from …"
/// means to the person asking.
int countCalendarDays(DateTime start, DateTime end) {
  final from = DateTime(start.year, start.month, start.day);
  final to = DateTime(end.year, end.month, end.day);
  if (to.isBefore(from)) return 0;
  return to.difference(from).inDays + 1;
}
