import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small live analog clock — hour, minute and second hands that tick in real
/// time. Sized to drop into an icon slot (default 24px).
class AnalogClock extends StatefulWidget {
  const AnalogClock({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  State<AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<AnalogClock> {
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(painter: _ClockPainter(_now, widget.color)),
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter(this.time, this.color);

  final DateTime time;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Rim.
    final rimWidth = math.max(1.2, size.width * 0.07);
    canvas.drawCircle(
      center,
      radius - rimWidth / 2,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..isAntiAlias = true,
    );

    void hand(double fraction, double lengthFactor, double width, Color c) {
      final angle = fraction * 2 * math.pi - math.pi / 2;
      final end =
          center + Offset(math.cos(angle), math.sin(angle)) * radius * lengthFactor;
      canvas.drawLine(
        center,
        end,
        Paint()
          ..color = c
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    final hourFraction = (time.hour % 12 + time.minute / 60.0) / 12;
    final minuteFraction = (time.minute + time.second / 60.0) / 60;
    final secondFraction = time.second / 60;

    hand(hourFraction, 0.48, math.max(1.6, size.width * 0.09), color);
    hand(minuteFraction, 0.70, math.max(1.2, size.width * 0.07), color);
    hand(secondFraction, 0.80, math.max(0.8, size.width * 0.04),
        color.withValues(alpha: 0.6));

    // Centre cap.
    canvas.drawCircle(
      center,
      math.max(1.2, size.width * 0.06),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ClockPainter old) => old.time != time;
}
