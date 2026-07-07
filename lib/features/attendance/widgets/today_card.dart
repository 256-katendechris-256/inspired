import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/brand.dart';
import '../attendance_controller.dart';
import '../attendance_data.dart';
import 'analog_clock.dart';

final _timeFmt = DateFormat('h:mm a');

/// Check-out only becomes available from this local hour (17:00 / 5 PM).
const int kCheckoutHour = 17;

String durationText(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h == 0 ? '${m}m' : '${h}h ${m}m';
}

/// The day's clock-in/out surface. On the home dashboard ([compact]) it's a bold
/// gradient hero; on the attendance page it's a detailed elevated card.
class TodayAttendanceCard extends ConsumerStatefulWidget {
  const TodayAttendanceCard({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<TodayAttendanceCard> createState() =>
      _TodayAttendanceCardState();
}

class _TodayAttendanceCardState extends ConsumerState<TodayAttendanceCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _checkoutUnlocked => DateTime.now().hour >= kCheckoutHour;

  Future<void> _run(Future<ActionResult> Function() action) async {
    final result = await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.ok ? Brand.green : Brand.red,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final busy = ref.watch(attendanceControllerProvider);
    final ctrl = ref.read(attendanceControllerProvider.notifier);

    return today.when(
      loading: _loading,
      error: (_, _) => _message('Couldn’t load today’s status.'),
      data: (rec) {
        final active = rec != null && rec.isActive;
        final done = rec != null && !rec.isActive;
        return widget.compact
            ? _Hero(
                rec: rec,
                active: active,
                done: done,
                busy: busy,
                checkoutUnlocked: _checkoutUnlocked,
                onCheckIn: () => _run(ctrl.checkIn),
                onCheckOut: () => _run(ctrl.checkOut),
              )
            : _FullCard(
                rec: rec,
                active: active,
                done: done,
                busy: busy,
                checkoutUnlocked: _checkoutUnlocked,
                onCheckIn: () => _run(ctrl.checkIn),
                onCheckOut: () => _run(ctrl.checkOut),
              );
      },
    );
  }

  Widget _loading() => Container(
    height: widget.compact ? 188 : 150,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: Brand.shadowCard,
    ),
    child: const Center(child: CircularProgressIndicator()),
  );

  Widget _message(String text) => Container(
    height: widget.compact ? 188 : 120,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: Brand.shadowCard,
    ),
    child: Text(text, style: const TextStyle(color: Brand.slate)),
  );
}

// ---------------------------------------------------------------------------
// HERO (home dashboard) — gradient surface with personality.
// ---------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({
    required this.rec,
    required this.active,
    required this.done,
    required this.busy,
    required this.checkoutUnlocked,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  final AttendanceRecord? rec;
  final bool active;
  final bool done;
  final bool busy;
  final bool checkoutUnlocked;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  @override
  Widget build(BuildContext context) {
    final gradient = done ? Brand.slateGradient : Brand.greenGradient;
    final glowColor = done ? Brand.slate : Brand.green;
    final eyebrow = active
        ? 'ON SITE NOW'
        : done
        ? 'SHIFT COMPLETE'
        : 'READY TO CHECK IN';
    final title = active
        ? 'On site'
        : done
        ? 'Checked out'
        : 'Not checked in';
    final subtitle = rec?.place ?? 'Tap below to record your arrival';

    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: Brand.glow(glowColor),
      ),
      child: Stack(
        children: [
          // Decorative watermark circle.
          Positioned(
            right: -28,
            top: -28,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      eyebrow,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const Spacer(),
                    if (rec?.isPendingSync ?? false) const _PendingPill(),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                      child: (!active && !done)
                          ? const AnalogClock(color: Colors.white, size: 24)
                          : Icon(
                              active ? Icons.location_on : Icons.check_circle,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _action(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action() {
    if (done) {
      return _filledStrip(
        color: Colors.white.withValues(alpha: 0.16),
        child: const Text(
          'All done for today 👋',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      );
    }
    if (active && !checkoutUnlocked) {
      return _filledStrip(
        color: Colors.white.withValues(alpha: 0.16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_clock, size: 17, color: Colors.white),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Check-out opens at 5:00 PM',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: active ? Brand.red : Brand.green,
          minimumSize: const Size.fromHeight(46),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        onPressed: busy ? null : (active ? onCheckOut : onCheckIn),
        icon: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: active ? Brand.red : Brand.green,
                ),
              )
            : Icon(active ? Icons.logout : Icons.login, size: 19),
        label: Text(active ? 'Check out' : 'Check in'),
      ),
    );
  }

  Widget _filledStrip({required Color color, required Widget child}) => Container(
    width: double.infinity,
    height: 46,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(13),
    ),
    child: child,
  );
}

class _PendingPill extends StatelessWidget {
  const _PendingPill();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.20),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_off, size: 12, color: Colors.white),
        SizedBox(width: 4),
        Text(
          'Pending sync',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// FULL CARD (attendance page) — elevated white card with the collected data.
// ---------------------------------------------------------------------------

class _FullCard extends StatelessWidget {
  const _FullCard({
    required this.rec,
    required this.active,
    required this.done,
    required this.busy,
    required this.checkoutUnlocked,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  final AttendanceRecord? rec;
  final bool active;
  final bool done;
  final bool busy;
  final bool checkoutUnlocked;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = active
        ? Brand.green
        : done
        ? Brand.blue
        : Brand.slate;
    final title = active
        ? 'On site'
        : done
        ? 'Checked out'
        : 'Not checked in';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: Brand.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  active
                      ? Icons.location_on
                      : done
                      ? Icons.check_circle
                      : Icons.schedule,
                  color: tone,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleLarge),
                    Text(
                      rec == null ? 'Tap to record your arrival.' : rec!.place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Brand.slate),
                    ),
                  ],
                ),
              ),
              if (rec != null) _StatusChip(record: rec!),
            ],
          ),
          if (rec != null) ...[
            const SizedBox(height: 16),
            _CheckInDetails(record: rec!),
          ],
          const SizedBox(height: 18),
          if (done)
            _doneBanner()
          else if (active && !checkoutUnlocked)
            _lockedPill()
          else
            FilledButton.icon(
              style: active
                  ? FilledButton.styleFrom(backgroundColor: Brand.red)
                  : null,
              onPressed: busy ? null : (active ? onCheckOut : onCheckIn),
              icon: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Icon(active ? Icons.logout : Icons.login),
              label: Text(active ? 'Check out' : 'Check in'),
            ),
        ],
      ),
    );
  }

  Widget _lockedPill() => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
    decoration: BoxDecoration(
      color: Brand.surfaceAlt,
      borderRadius: BorderRadius.circular(13),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_clock, size: 18, color: Brand.slate),
        SizedBox(width: 8),
        Text(
          'Check-out opens at 5:00 PM',
          style: TextStyle(color: Brand.slate, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _doneBanner() => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Brand.greenWash,
      borderRadius: BorderRadius.circular(13),
    ),
    child: const Text(
      'You’re done for today. 👋',
      style: TextStyle(color: Brand.green, fontWeight: FontWeight.w600),
    ),
  );
}

class _CheckInDetails extends StatelessWidget {
  const _CheckInDetails({required this.record});
  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Brand.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _row('Checked in', _timeFmt.format(r.checkInAt)),
          if (r.checkInPoint != null) _row('Check-in point', r.checkInPoint!),
          if (r.checkInDistanceM != null)
            _row('Distance from point', '${r.checkInDistanceM} m'),
          if (r.checkInAccuracyM != null)
            _row('GPS accuracy', '±${r.checkInAccuracyM} m'),
          _row('Method', r.methodLabel),
          if (r.checkOutAt != null)
            _row('Checked out', _timeFmt.format(r.checkOutAt!)),
          if (r.durationMinutes != null)
            _row('Duration', durationText(r.durationMinutes!)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Brand.slate, fontSize: 13)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Brand.ink,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.record});
  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final pending = record.isPendingSync;
    final review = record.needsReview;
    final color = (pending || review) ? Brand.orange : Brand.green;
    final label = pending
        ? 'Pending sync'
        : review
        ? 'Needs review'
        : 'Verified';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending) ...[
            Icon(Icons.cloud_off, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
