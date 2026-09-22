import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// "You haven't signed in yet" nudges that work with no signal.
///
/// Push can't do this: a phone at a rural site at 08:45 may have no data.
/// So the reminders are local alarms scheduled on the device. The backend
/// tells us *which days* (Mon–Sat, minus public holidays, minus approved
/// leave — see /api/attendance/me/reminder-plan) and *what times*; we cache
/// that plan and schedule two weeks of alarms from it. Whenever we're back
/// online the plan is refreshed and the alarms rebuilt, and the moment the
/// employee checks in, today's remaining alarms are cancelled.
///
/// If the app has never been online, we fall back to Mon–Sat at the default
/// times — better a reminder on an unknown holiday than none on a workday.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const _kPlan = 'reminders.plan.v1';
  static const _kCheckedInDate = 'reminders.checked_in.v1';
  static const _defaultTimes = ['08:45', '09:00'];
  static const _defaultZone = 'Africa/Kampala';
  static const _horizonDays = 14;

  // Notification ids live in their own range so cancelling ours never
  // touches a push shown by PushService.
  static const _idBase = 5000;
  static const _idSpan = _horizonDays * 4; // generous: dates × times

  static const _channel = AndroidNotificationChannel(
    'inspired_signin_reminders',
    'Sign-in reminders',
    description: 'A nudge if you haven’t signed in by the start of the day.',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  SharedPreferences? _prefs;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    tzdata.initializeTimeZones();
    _prefs ??= await SharedPreferences.getInstance();
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
  }

  /// Pull the latest plan from the server (best-effort) and rebuild alarms.
  /// Safe to call often: on sign-in, app start, and whenever we come online.
  Future<void> sync(Dio dio) async {
    try {
      await _ensureInitialized();
      final res = await dio.get(
        '/api/attendance/me/reminder-plan',
        queryParameters: {'days': _horizonDays},
      );
      final plan = Map<String, dynamic>.from(res.data as Map);
      await _prefs!.setString(_kPlan, jsonEncode(plan));
      if (plan['checked_in_today'] == true) {
        await _prefs!.setString(_kCheckedInDate, _today());
      }
    } catch (_) {
      // Offline or signed out — schedule from whatever we have cached.
    }
    await reschedule();
  }

  /// Rebuild every alarm from the cached plan (or the Mon–Sat fallback).
  Future<void> reschedule() async {
    try {
      await _ensureInitialized();
      await _cancelOurs();

      final plan = _cachedPlan();
      final zone = _zone(plan?['timezone'] as String?);
      final times = _parseTimes(plan?['times']);
      final dates = _dates(plan, zone);
      final skipToday = _prefs!.getString(_kCheckedInDate) == _today();
      final now = tz.TZDateTime.now(zone);

      var id = _idBase;
      for (final d in dates) {
        if (skipToday && _isSameDay(d, now)) continue;
        for (final (h, m) in times) {
          final when = tz.TZDateTime(zone, d.year, d.month, d.day, h, m);
          if (!when.isAfter(now)) continue;
          if (id >= _idBase + _idSpan) return;
          await _scheduleOne(id++, when, secondNudge: m == times.last.$2 && h == times.last.$1);
        }
      }
    } catch (e) {
      debugPrint('reminders: reschedule failed: $e');
    }
  }

  /// Call when the employee has checked in (online or queued offline) so
  /// today's remaining nudges are dropped.
  Future<void> onCheckedIn() async {
    await _ensureInitialized();
    await _prefs!.setString(_kCheckedInDate, _today());
    await reschedule();
  }

  /// On sign-out nothing should fire for an account that's no longer here.
  Future<void> clear() async {
    await _ensureInitialized();
    await _cancelOurs();
    await _prefs!.remove(_kPlan);
    await _prefs!.remove(_kCheckedInDate);
  }

  // --- internals -----------------------------------------------------------

  Future<void> _scheduleOne(int id, tz.TZDateTime when, {required bool secondNudge}) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
    );
    final title = secondNudge ? 'You’re not signed in yet' : 'Sign in when you arrive';
    final body = secondNudge
        ? 'It’s ${_clock(when)} — open the app and check in so today counts.'
        : 'Reminder: check in at your site once you’re on the ground.';
    try {
      await _local.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Exact alarms can be refused on some Android builds; a slightly late
      // nudge beats none.
      await _local.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> _cancelOurs() async {
    for (var id = _idBase; id < _idBase + _idSpan; id++) {
      await _local.cancel(id);
    }
  }

  Map<String, dynamic>? _cachedPlan() {
    final raw = _prefs!.getString(_kPlan);
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  tz.Location _zone(String? name) {
    try {
      return tz.getLocation(name ?? _defaultZone);
    } catch (_) {
      return tz.getLocation(_defaultZone);
    }
  }

  List<(int, int)> _parseTimes(dynamic raw) {
    final list = raw is List ? raw.cast<dynamic>().map((e) => '$e').toList() : _defaultTimes;
    final out = <(int, int)>[];
    for (final s in list) {
      final parts = s.split(':');
      if (parts.length != 2) continue;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) out.add((h, m));
    }
    return out.isEmpty ? const [(8, 45), (9, 0)] : out;
  }

  /// Dates to remind on. From the cached plan if it still covers the
  /// future; otherwise the next two weeks of Mon–Sat.
  List<tz.TZDateTime> _dates(Map<String, dynamic>? plan, tz.Location zone) {
    final now = tz.TZDateTime.now(zone);
    final today = tz.TZDateTime(zone, now.year, now.month, now.day);
    final fromPlan = <tz.TZDateTime>[];
    final raw = plan?['dates'];
    if (raw is List) {
      for (final s in raw) {
        final d = DateTime.tryParse('$s');
        if (d == null) continue;
        final t = tz.TZDateTime(zone, d.year, d.month, d.day);
        if (!t.isBefore(today)) fromPlan.add(t);
      }
    }
    if (fromPlan.isNotEmpty) return fromPlan;

    final fallback = <tz.TZDateTime>[];
    for (var i = 0; fallback.length < _horizonDays && i < _horizonDays * 2; i++) {
      final d = today.add(Duration(days: i));
      if (d.weekday != DateTime.sunday) fallback.add(d);
    }
    return fallback;
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static bool _isSameDay(tz.TZDateTime a, tz.TZDateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _clock(tz.TZDateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
  }
}
