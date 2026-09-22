import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/brand.dart';
import '../attendance_data.dart';

// The dashboard's calendar palette (Tailwind), kept identical so a day reads
// the same colour on the phone as on an HOD's screen.
const _present = Color(0xFF10B981); // emerald-500
const _late = Color(0xFFF59E0B); // amber-500
const _absent = Color(0xFFF43F5E); // rose-500
const _leave = Color(0xFF3B82F6); // blue-500
const _overtime = Color(0xFF7C3AED); // violet-600
const _holidayBg = Color(0xFFF3E8FF); // purple-100
const _holidayFg = Color(0xFF7E22CE); // purple-700
const _restBg = Color(0xFFF4F4F5); // zinc-100
const _restFg = Color(0xFFA1A1AA); // zinc-400

final _monthFmt = DateFormat('MMMM yyyy');
final _longDay = DateFormat('EEEE, d MMMM');

/// How one calendar cell looks and reads. Single source of truth for both
/// the grid and the tap-through detail, mirroring `classify()` in iams-dash.
class _DayView {
  const _DayView(this.bg, this.fg, this.status, {this.detail, this.filled = true});
  final Color bg;
  final Color fg;
  final String status;
  final String? detail;

  /// Solid cells carry white text; tinted ones (holiday, rest) carry a hue.
  final bool filled;
}

_DayView _classify(MonthCalendar md, String ds, String today) {
  final rec = md.days[ds];
  final holiday = md.holidays[ds];
  final times = rec == null
      ? null
      : 'In ${rec.checkIn}'
            '${rec.checkOut == null ? ' · still checked in' : ' · Out ${rec.checkOut}'}'
            ' (${_hours(rec.hours)})';

  if (rec != null && rec.overtime) {
    return _DayView(_overtime, Colors.white, 'Overtime (${holiday ?? 'Sunday'})',
        detail: times);
  }
  if (rec != null) {
    return rec.late
        ? _DayView(_late, Colors.white, 'Late', detail: times)
        : _DayView(_present, Colors.white, 'Present', detail: times);
  }
  if (holiday != null) {
    return _DayView(_holidayBg, _holidayFg, 'Public holiday',
        detail: holiday, filled: false);
  }
  if (md.leaveDates.contains(ds)) {
    return const _DayView(_leave, Colors.white, 'On leave');
  }
  if (_isSunday(ds)) {
    return const _DayView(_restBg, _restFg, 'Rest day', filled: false);
  }
  if (ds.compareTo(today) > 0) {
    return const _DayView(_restBg, _restFg, 'Upcoming', filled: false);
  }
  return const _DayView(_absent, Colors.white, 'Absent');
}

DateTime _parseISO(String ds) {
  final p = ds.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

bool _isSunday(String ds) => _parseISO(ds).weekday == DateTime.sunday;

String _iso(DateTime d) =>
    '${monthKey(d)}-${d.day.toString().padLeft(2, '0')}';

/// 8.0 -> "8h", 7.5 -> "7.5h" — the same as the dashboard renders.
String _hours(double h) =>
    '${h.toStringAsFixed(h == h.roundToDouble() ? 0 : 1)}h';

/// A month of attendance, one cell per day, with the same colour language as
/// the employee profile calendar on the dashboard. Pages back and forth by
/// month; tapping a day shows what happened on it.
class MonthCalendarCard extends ConsumerStatefulWidget {
  const MonthCalendarCard({super.key});

  @override
  ConsumerState<MonthCalendarCard> createState() => _MonthCalendarCardState();
}

class _MonthCalendarCardState extends ConsumerState<MonthCalendarCard> {
  late DateTime _month; // always the 1st of the month shown

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
  }

  bool get _isCurrent {
    final n = DateTime.now();
    return _month.year == n.year && _month.month == n.month;
  }

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final key = monthKey(_month);
    final data = ref.watch(monthCalendarProvider(key));

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      _monthFmt.format(_month),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Brand.ink,
                        fontSize: 15,
                      ),
                    ),
                    if (_isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Brand.greenWash,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Current',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Brand.green,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _NavButton(icon: Icons.chevron_left, onTap: () => _shift(-1)),
              const SizedBox(width: 2),
              _NavButton(
                icon: Icons.chevron_right,
                // No point paging into a month that hasn't started.
                onTap: _isCurrent ? null : () => _shift(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          data.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  const Icon(Icons.cloud_off, color: Brand.slate, size: 28),
                  const SizedBox(height: 8),
                  const Text(
                    'Couldn’t load this month.',
                    style: TextStyle(color: Brand.slate),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(monthCalendarProvider(key)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (md) => _Grid(month: _month, data: md),
          ),
          const SizedBox(height: 14),
          const _Legend(),
          const SizedBox(height: 10),
          const Text(
            'Working week is Monday to Saturday. Sundays and public holidays '
            'are rest days — work recorded on them counts as overtime.',
            style: TextStyle(color: Brand.mute, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 22,
          color: onTap == null ? Brand.line : Brand.slate,
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.month, required this.data});
  final DateTime month;
  final MonthCalendar data;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = month.weekday - DateTime.monday; // Mon = 0
    final today = _iso(DateTime.now());

    final cells = <String?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        _iso(DateTime(month.year, month.month, d)),
    ];

    return Column(
      children: [
        Row(
          children: _weekdays
              .map(
                (w) => Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Brand.mute,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: cells.length,
          itemBuilder: (context, i) {
            final ds = cells[i];
            if (ds == null) return const SizedBox.shrink();
            final view = _classify(data, ds, today);
            final rec = data.days[ds];
            final isToday = ds == today;
            return _Cell(
              day: int.parse(ds.substring(8)),
              view: view,
              hours: rec?.hours,
              isToday: isToday,
              onTap: () => _showDay(context, ds, view),
            );
          },
        ),
      ],
    );
  }

  void _showDay(BuildContext context, String ds, _DayView view) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _longDay.format(_parseISO(ds)),
              style: const TextStyle(color: Brand.slate, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: view.bg,
                    borderRadius: BorderRadius.circular(3),
                    border: view.filled
                        ? null
                        : Border.all(color: view.fg.withValues(alpha: 0.4)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  view.status,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Brand.ink,
                  ),
                ),
              ],
            ),
            if (view.detail != null) ...[
              const SizedBox(height: 6),
              Text(
                view.detail!,
                style: const TextStyle(color: Brand.slate, fontSize: 13.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.view,
    required this.hours,
    required this.isToday,
    required this.onTap,
  });
  final int day;
  final _DayView view;
  final double? hours;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: view.bg,
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: Brand.ink, width: 1.5)
              : view.filled
              ? null
              : Border.all(color: view.fg.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: view.fg,
                height: 1,
              ),
            ),
            if (hours != null) ...[
              const SizedBox(height: 2),
              Text(
                _hours(hours!),
                style: TextStyle(
                  fontSize: 8.5,
                  color: view.fg.withValues(alpha: 0.9),
                  height: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    const items = [
      (_present, Colors.white, 'Present'),
      (_late, Colors.white, 'Late'),
      (_absent, Colors.white, 'Absent'),
      (_leave, Colors.white, 'On leave'),
      (_overtime, Colors.white, 'Overtime'),
      (_holidayBg, _holidayFg, 'Public holiday'),
      (_restBg, _restFg, 'Sunday / upcoming'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: items
          .map(
            (it) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: it.$1,
                    borderRadius: BorderRadius.circular(3),
                    border: it.$2 == Colors.white
                        ? null
                        : Border.all(color: it.$2.withValues(alpha: 0.35)),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  it.$3,
                  style: const TextStyle(fontSize: 11, color: Brand.slate),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}
