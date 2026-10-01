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
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  @override
  void initState() {
    super.initState();
    // Months are cached for the life of the app, so leave approved (or a
    // holiday added) since a month was first opened never showed up — on
    // the web, where a tab stays open for days, effectively never. Re-read
    // every month each time the screen is opened; the cached copy stays on
    // screen until the fresh one arrives.
    Future.microtask(() {
      if (mounted) ref.invalidate(monthCalendarProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
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
          ref.invalidate(monthCalendarProvider); // every month, not just this one
          await ref.read(monthCalendarProvider(monthKey(DateTime.now())).future);
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
