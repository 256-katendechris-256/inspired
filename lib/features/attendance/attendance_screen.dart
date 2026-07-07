import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/brand.dart';
import 'attendance_data.dart';
import 'widgets/attendance_metrics.dart';
import 'widgets/today_card.dart';

final _timeFmt = DateFormat('h:mm a');
final _dayFmt = DateFormat('EEE, d MMM');

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: AppBar(
        title: const Text('Attendance'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: RefreshIndicator(
        color: Brand.green,
        onRefresh: () async {
          ref.invalidate(todayProvider);
          ref.invalidate(historyProvider);
          await ref.read(historyProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const TodayAttendanceCard(),
            const SizedBox(height: 24),
            _label(context, 'Insights'),
            const SizedBox(height: 10),
            const AttendanceMetrics(),
            const SizedBox(height: 24),
            _label(context, 'Last 5 days'),
            const SizedBox(height: 10),
            const _History(),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: Brand.ink,
    ),
  );
}

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _Empty(text: 'Couldn’t load your history.'),
      data: (records) {
        // Only the last 5 days.
        final cutoff = DateTime.now().subtract(const Duration(days: 5));
        final recent =
            records.where((r) => r.checkInAt.isAfter(cutoff)).toList();
        if (recent.isEmpty) {
          return const _Empty(text: 'No attendance in the last 5 days.');
        }
        return Column(
          children: recent.map((r) => _HistoryTile(record: r)).toList(),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});
  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final tone = record.isActive
        ? Brand.green
        : record.needsReview
        ? Brand.orange
        : Brand.blue;
    final span = record.checkOutAt == null
        ? 'In ${_timeFmt.format(record.checkInAt)}'
        : '${_timeFmt.format(record.checkInAt)} – ${_timeFmt.format(record.checkOutAt!)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        children: [
          Container(width: 4, height: 38, color: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dayFmt.format(record.checkInAt),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Brand.ink,
                  ),
                ),
                Text('${record.blockName ?? record.siteName} · $span',
                    style: const TextStyle(color: Brand.slate, fontSize: 12.5)),
              ],
            ),
          ),
          Text(
            record.durationMinutes != null
                ? durationText(record.durationMinutes!)
                : (record.isActive ? 'Active' : '—'),
            style: TextStyle(color: tone, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.history, color: Brand.slate, size: 32),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: Brand.slate)),
        ],
      ),
    );
  }
}
