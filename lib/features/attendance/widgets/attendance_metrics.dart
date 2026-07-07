import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/brand.dart';
import '../attendance_data.dart';

class _DayHours {
  _DayHours(this.date, this.minutes);
  final DateTime date;
  int minutes;
}

/// Per-account attendance insights derived from recent history: presence,
/// hours, average shift, items needing review, and a 7-day hours chart.
class AttendanceMetrics extends ConsumerWidget {
  const AttendanceMetrics({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return history.maybeWhen(
      data: (records) => _build(context, records),
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _build(BuildContext context, List<AttendanceRecord> records) {
    final now = DateTime.now();
    final monthRecords = records
        .where((r) => r.checkInAt.year == now.year && r.checkInAt.month == now.month)
        .toList();

    final daysPresent = monthRecords
        .map((r) => DateTime(r.checkInAt.year, r.checkInAt.month, r.checkInAt.day))
        .toSet()
        .length;
    final monthMinutes = monthRecords
        .where((r) => r.durationMinutes != null)
        .fold<int>(0, (s, r) => s + r.durationMinutes!);
    final completed = records.where((r) => r.durationMinutes != null).toList();
    final avgMinutes = completed.isEmpty
        ? 0
        : completed.fold<int>(0, (s, r) => s + r.durationMinutes!) ~/ completed.length;
    final needsReview = records.where((r) => r.needsReview).length;

    // Last 7 days hours.
    final today = DateTime(now.year, now.month, now.day);
    final week = List.generate(
      7,
      (i) => _DayHours(today.subtract(Duration(days: 6 - i)), 0),
    );
    for (final r in records) {
      if (r.durationMinutes == null) continue;
      final d = DateTime(r.checkInAt.year, r.checkInAt.month, r.checkInAt.day);
      for (final wd in week) {
        if (wd.date == d) wd.minutes += r.durationMinutes!;
      }
    }

    String hrs(int m) => m == 0 ? '0' : (m / 60).toStringAsFixed(m % 60 == 0 ? 0 : 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Stat(
              label: 'Days this month',
              value: '$daysPresent',
              icon: Icons.event_available,
              color: Brand.green,
            ),
            const SizedBox(width: 12),
            _Stat(
              label: 'Hours this month',
              value: '${hrs(monthMinutes)}h',
              icon: Icons.timer_outlined,
              color: Brand.blue,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Stat(
              label: 'Avg shift',
              value: avgMinutes == 0
                  ? '—'
                  : '${avgMinutes ~/ 60}h ${avgMinutes % 60}m',
              icon: Icons.av_timer,
              color: Brand.orange,
            ),
            const SizedBox(width: 12),
            _Stat(
              label: 'Needs review',
              value: '$needsReview',
              icon: Icons.flag_outlined,
              color: needsReview > 0 ? Brand.red : Brand.slate,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _WeekChart(week: week),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Brand.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Brand.ink,
              ),
            ),
            Text(label, style: const TextStyle(color: Brand.slate, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.week});
  final List<_DayHours> week;

  @override
  Widget build(BuildContext context) {
    final maxMin = week.fold<int>(60, (m, d) => d.minutes > m ? d.minutes : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hours · last 7 days',
            style: TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
          ),
          const SizedBox(height: 14),
          SizedBox(
            // Fits the tallest column: hours label + max bar (68) + day label.
            // Was 96, which overflowed by ~10px when a bar hit full height.
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: week.map((d) {
                final frac = (d.minutes / maxMin).clamp(0.0, 1.0);
                final isToday = _isToday(d.date);
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        d.minutes == 0 ? '' : (d.minutes / 60).toStringAsFixed(0),
                        style: const TextStyle(fontSize: 10, color: Brand.slate),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        height: 64 * frac + 4,
                        decoration: BoxDecoration(
                          color: isToday ? Brand.green : Brand.green.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('E').format(d.date)[0],
                        style: TextStyle(
                          fontSize: 11,
                          color: isToday ? Brand.ink : Brand.slate,
                          fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }
}
