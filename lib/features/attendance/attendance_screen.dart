import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import 'attendance_data.dart';
import 'widgets/attendance_stats.dart';
import 'widgets/month_calendar.dart';
import 'widgets/today_card.dart';

/// Attendance, top to bottom: this month at a glance (days / hours / average
/// shift), the on-site card for today, and the month calendar.
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
          final thisMonth = monthCalendarProvider(monthKey(DateTime.now()));
          ref.invalidate(todayProvider);
          ref.invalidate(thisMonth);
          await ref.read(thisMonth.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: const [
            AttendanceStats(),
            SizedBox(height: 16),
            TodayAttendanceCard(),
            SizedBox(height: 16),
            MonthCalendarCard(),
          ],
        ),
      ),
    );
  }
}
