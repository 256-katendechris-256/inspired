import 'dart:async';
import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/location.dart';
import '../../core/notifications/reminder_service.dart';
import '../../core/offline/offline_store.dart';
import 'attendance_data.dart';
import 'sites.dart';

/// Result of a check-in / check-out attempt, surfaced to the UI.
class ActionResult {
  const ActionResult.success(this.message) : ok = true;
  const ActionResult.failure(this.message) : ok = false;
  final bool ok;
  final String message;
}

final attendanceControllerProvider =
    StateNotifierProvider<AttendanceController, bool>(
  (ref) => AttendanceController(ref),
);

/// Offline-first attendance.
///
/// Every action tries the server first. If the server is unreachable (no
/// response — e.g. out of WiFi range at the gate), the action is verified
/// on-device against the cached geofence, recorded optimistically, and queued.
/// Queued actions flush automatically when connectivity returns; the server
/// re-verifies them on arrival, so it stays the source of truth.
class AttendanceController extends StateNotifier<bool> {
  AttendanceController(this._ref) : super(false) {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        syncPending();
        // Back online → pick up any holiday/leave changes for the reminders.
        ReminderService.instance.sync(_dio);
      }
    });
    syncPending(); // attempt to drain any backlog on startup
  }

  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  OfflineStore get _store => _ref.read(offlineStoreProvider);
  Dio get _dio => _ref.read(dioProvider);

  static const _checkInPath = '/api/attendance/check-in';
  static const _checkOutPath = '/api/attendance/check-out';

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<ActionResult> checkIn() async {
    if (state) return const ActionResult.failure('Please wait…');
    state = true;
    try {
      await syncPending();
      final fix = await currentPosition();
      if (fix == null) {
        return const ActionResult.failure(
          'Turn on location (and grant permission) to record attendance.',
        );
      }
      final bssid = await _bssid();
      final deviceId = await _deviceId();
      final at = DateTime.now();
      try {
        await _dio.post(_checkInPath, data: _payload(fix, bssid, at, deviceId: deviceId));
        _refresh();
        unawaited(ReminderService.instance.onCheckedIn());
        return const ActionResult.success('Checked in.');
      } on DioException catch (e) {
        if (e.response != null) return ActionResult.failure(_message(e));
        return _offlineCheckIn(fix, bssid, at, deviceId);
      }
    } finally {
      state = false;
    }
  }

  Future<ActionResult> checkOut() async {
    if (state) return const ActionResult.failure('Please wait…');
    state = true;
    try {
      await syncPending();
      final fix = await currentPosition();
      if (fix == null) {
        return const ActionResult.failure(
          'Turn on location (and grant permission) to record attendance.',
        );
      }
      final bssid = await _bssid();
      final deviceId = await _deviceId();
      final at = DateTime.now();
      try {
        await _dio.post(_checkOutPath, data: _payload(fix, bssid, at, deviceId: deviceId));
        _refresh();
        return const ActionResult.success('Checked out.');
      } on DioException catch (e) {
        if (e.response != null) return ActionResult.failure(_message(e));
        return _offlineCheckOut(fix, bssid, at, deviceId);
      }
    } finally {
      state = false;
    }
  }

  // --- Offline paths ---------------------------------------------------------

  Future<ActionResult> _offlineCheckIn(
    PositionFix fix,
    String bssid,
    DateTime at,
    String deviceId,
  ) async {
    final cached = _store.readSites();
    if (cached == null) {
      return const ActionResult.failure(
        'You’re offline and your sites aren’t loaded yet. '
        'Connect once, then you can check in offline.',
      );
    }
    final sites = cached
        .map((e) => Site.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final match = matchCheckInPoint(sites, fix.latLng);
    if (match == null) {
      return const ActionResult.failure(
        'You are not within range of any assigned site.',
      );
    }
    if (_store.readToday()?['is_active'] == true) {
      return const ActionResult.failure('Already checked in.');
    }

    final rec = AttendanceRecord.localCheckIn(
      siteName: match.site.name,
      blockName: match.block?.name,
      point: match.block?.name ?? match.site.name,
      distanceM: match.distanceM.round(),
      accuracyM: fix.accuracyM?.round(),
      bssid: bssid,
      lat: fix.latLng.latitude,
      lng: fix.latLng.longitude,
      at: at,
    );
    await _store.writeToday(rec.toJson());
    await _store.enqueue({
      'type': 'check_in',
      ..._payload(fix, bssid, at, id: at, deviceId: deviceId),
    });
    _refresh();
    // Queued or not, they've checked in — no more nudges today.
    unawaited(ReminderService.instance.onCheckedIn());
    return const ActionResult.success(
      'Checked in offline — it will sync when you’re back online.',
    );
  }

  Future<ActionResult> _offlineCheckOut(
    PositionFix fix,
    String bssid,
    DateTime at,
    String deviceId,
  ) async {
    final today = _store.readToday();
    if (today == null || today['is_active'] != true) {
      return const ActionResult.failure('No active check-in to close.');
    }
    today['check_out_at'] = at.toUtc().toIso8601String();
    today['is_active'] = false;
    today['pending_sync'] = true;
    final ci = DateTime.tryParse(today['check_in_at'] as String? ?? '');
    if (ci != null) {
      today['duration_minutes'] = at.toUtc().difference(ci.toUtc()).inMinutes;
    }
    await _store.writeToday(today);
    await _store.enqueue({
      'type': 'check_out',
      ..._payload(fix, bssid, at, id: at, deviceId: deviceId),
    });
    _refresh();
    return const ActionResult.success(
      'Checked out offline — it will sync when you’re back online.',
    );
  }

  // --- Sync ------------------------------------------------------------------

  /// Best-effort flush of the queued offline actions. Safe to call anytime.
  Future<void> syncPending() async {
    final queue = _store.readQueue();
    if (queue.isEmpty) return;
    for (final action in List<Map<String, dynamic>>.from(queue)) {
      final path =
          action['type'] == 'check_out' ? _checkOutPath : _checkInPath;
      try {
        await _dio.post(path, data: {
          'lat': action['lat'],
          'lng': action['lng'],
          'bssid': action['bssid'] ?? '',
          if (action['accuracy_m'] != null) 'accuracy_m': action['accuracy_m'],
          'occurred_at': action['occurred_at'],
          if (action['device_id'] != null) 'device_id': action['device_id'],
          if (action['mock_location'] == true) 'mock_location': true,
        });
        await _store.removeFromQueue(action['client_id'] as String);
      } on DioException catch (e) {
        if (e.response == null) return; // still offline — retry later
        // Server rejected it (duplicate / out of range); drop so it can't
        // block the queue forever.
        await _store.removeFromQueue(action['client_id'] as String);
      }
    }
    _refresh(); // queue drained → server is now the source of truth
  }

  // --- Helpers ---------------------------------------------------------------

  Map<String, dynamic> _payload(
    PositionFix fix,
    String bssid,
    DateTime at, {
    DateTime? id,
    String deviceId = '',
  }) => {
    if (id != null) 'client_id': id.microsecondsSinceEpoch.toString(),
    'lat': fix.latLng.latitude,
    'lng': fix.latLng.longitude,
    'bssid': bssid,
    if (fix.accuracyM != null) 'accuracy_m': fix.accuracyM!.round(),
    'occurred_at': at.toUtc().toIso8601String(),
    if (deviceId.isNotEmpty) 'device_id': deviceId,
    // The server records this flag; it only knows if we tell it.
    if (fix.isMocked) 'mock_location': true,
  };

  Future<String> _bssid() async {
    try {
      return (await NetworkInfo().getWifiBSSID()) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Hardware device identifier, read only at this check-in/out moment (same
  /// privacy posture as location — see docs/SPRINT_0.md §12a). Used
  /// server-side (hashed, never stored raw) purely to catch one phone being
  /// used to check in/out for more than one employee in a day.
  ///
  /// On Android this MUST be Settings.Secure.ANDROID_ID (via the android_id
  /// plugin), not device_info_plus's `androidInfo.id` — that field is
  /// android.os.Build.ID, the OS *build* label (e.g. "TQ3A.230901.001"),
  /// identical across every device running the same firmware image. Using
  /// it here caused mass false "device sharing" flags across unrelated
  /// employees whose phones simply share a build — see docs/notes on the
  /// 2026-08 device-sharing false-positive incident.
  Future<String> _deviceId() async {
    try {
      if (Platform.isAndroid) {
        return await const AndroidId().getId() ?? '';
      }
      if (Platform.isIOS) {
        final info = DeviceInfoPlugin();
        return (await info.iosInfo).identifierForVendor ?? '';
      }
    } catch (_) {}
    return '';
  }

  void _refresh() {
    _ref.invalidate(todayProvider);
    _ref.invalidate(historyProvider);
    // A check-in/out changes this month's calendar and the stats above it.
    _ref.invalidate(monthCalendarProvider(monthKey(DateTime.now())));
  }

  String _message(DioException e) {
    if (e.response == null) {
      return 'Can’t reach the server. Check your connection and try again.';
    }
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return 'Something went wrong. Please try again.';
  }
}
