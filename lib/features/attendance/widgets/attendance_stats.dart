import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand.dart';
import '../attendance_data.dart';

/// One row of three compact indicators for the current month: days present,
/// ordinary hours, and average shift length. Numbers come from the same
/// month summary the calendar below draws from, so they always agree.
class AttendanceStats extends ConsumerWidget {
  const AttendanceStats({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthCalendarProvider(monthKey(DateTime.now())));
    final data = month.asData?.value;
    final loading = month.isLoading && data == null;

    String hrs(double h) =>
        h == 0 ? '0' : h.toStringAsFixed(h == h.roundToDouble() ? 0 : 1);
    String avg(double h) {
      if (h == 0) return '—';
      final m = (h * 60).round();
      return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
    }

    return Row(
      children: [
        _Stat(
          label: 'Days',
          value: loading ? '…' : '${data?.daysPresent ?? 0}',
          sub: data == null || data.expectedDays == 0
              ? 'this month'
              : 'of ${data.expectedDays}',
          icon: Icons.event_available,
          color: Brand.green,
        ),
        const SizedBox(width: 10),
        _Stat(
          label: 'Hours',
          value: loading ? '…' : '${hrs(data?.totalHours ?? 0)}h',
          sub: 'this month',
          icon: Icons.timer_outlined,
          color: Brand.blue,
        ),
        const SizedBox(width: 10),
        _Stat(
          label: 'Avg shift',
          value: loading ? '…' : avg(data?.avgHours ?? 0),
          sub: 'per day',
          icon: Icons.av_timer,
          color: Brand.orange,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 15),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    color: Brand.slate,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Brand.ink,
                  height: 1.1,
                ),
              ),
            ),
            Text(sub, style: const TextStyle(color: Brand.mute, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}
