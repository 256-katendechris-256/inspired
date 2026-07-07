import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/offline/offline_store.dart';

/// One attendance record as returned by the API.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.siteName,
    required this.blockName,
    required this.checkInAt,
    required this.checkInStatus,
    required this.checkInMethod,
    required this.checkOutAt,
    required this.durationMinutes,
    required this.isActive,
    required this.mockLocationFlag,
    required this.checkInPoint,
    required this.checkInDistanceM,
    required this.checkInAccuracyM,
    required this.checkInBssid,
    required this.checkInLat,
    required this.checkInLng,
    this.isPendingSync = false,
  });

  /// An optimistic record built on-device for an offline check-in, before it
  /// has reached the server. Marked [isPendingSync].
  factory AttendanceRecord.localCheckIn({
    required String siteName,
    required String? blockName,
    required String? point,
    required int? distanceM,
    required int? accuracyM,
    required String bssid,
    required double lat,
    required double lng,
    required DateTime at,
  }) => AttendanceRecord(
    id: -1,
    siteName: siteName,
    blockName: blockName,
    checkInAt: at,
    checkInStatus: 'verified',
    checkInMethod: 'gps_only',
    checkOutAt: null,
    durationMinutes: null,
    isActive: true,
    mockLocationFlag: false,
    checkInPoint: point,
    checkInDistanceM: distanceM,
    checkInAccuracyM: accuracyM,
    checkInBssid: bssid.isEmpty ? null : bssid,
    checkInLat: lat,
    checkInLng: lng,
    isPendingSync: true,
  );

  final int id;
  final String siteName;
  final String? blockName;
  final DateTime checkInAt;

  /// "Admin Block · Africa Coffee Park" when a block is known, else the site.
  String get place => blockName == null ? siteName : '$blockName · $siteName';
  final String checkInStatus; // verified | needs_review
  final String checkInMethod; // gps_wifi | gps_only
  final DateTime? checkOutAt;
  final int? durationMinutes;
  final bool isActive;
  final bool mockLocationFlag;

  /// The matched check-in point (block name, else site name).
  final String? checkInPoint;

  /// Metres between where they checked in and the centre of the check-in point.
  final int? checkInDistanceM;

  /// Reported GPS horizontal accuracy at check-in (metres).
  final int? checkInAccuracyM;
  final String? checkInBssid;
  final double? checkInLat;
  final double? checkInLng;

  /// True for a record recorded offline that hasn't been confirmed by the
  /// server yet.
  final bool isPendingSync;

  bool get needsReview => checkInStatus == 'needs_review';

  /// Human label for the verification method.
  String get methodLabel =>
      checkInMethod == 'gps_wifi' ? 'GPS + WiFi' : 'GPS only';

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) {
    final site = (j['site'] as Map?)?.cast<String, dynamic>();
    return AttendanceRecord(
      id: j['id'] as int,
      siteName: site?['name'] as String? ?? 'Site',
      blockName: j['block'] as String?,
      checkInAt: DateTime.parse(j['check_in_at'] as String).toLocal(),
      checkInStatus: j['check_in_status'] as String? ?? 'verified',
      checkInMethod: j['check_in_method'] as String? ?? 'gps_only',
      checkOutAt: j['check_out_at'] == null
          ? null
          : DateTime.parse(j['check_out_at'] as String).toLocal(),
      durationMinutes: j['duration_minutes'] as int?,
      isActive: j['is_active'] as bool? ?? false,
      mockLocationFlag: j['mock_location_flag'] as bool? ?? false,
      checkInPoint: j['check_in_point'] as String?,
      checkInDistanceM: j['check_in_distance_m'] as int?,
      checkInAccuracyM: j['check_in_accuracy_m'] as int?,
      checkInBssid: j['check_in_bssid'] as String?,
      checkInLat: (j['check_in_lat'] as num?)?.toDouble(),
      checkInLng: (j['check_in_lng'] as num?)?.toDouble(),
      isPendingSync: j['pending_sync'] as bool? ?? false,
    );
  }

  /// Serialise to the same shape [fromJson] reads, for the local today cache.
  Map<String, dynamic> toJson() => {
    'id': id,
    'site': {'name': siteName},
    'block': blockName,
    'check_in_point': checkInPoint,
    'check_in_at': checkInAt.toUtc().toIso8601String(),
    'check_in_status': checkInStatus,
    'check_in_method': checkInMethod,
    'check_in_lat': checkInLat,
    'check_in_lng': checkInLng,
    'check_in_accuracy_m': checkInAccuracyM,
    'check_in_bssid': checkInBssid,
    'check_in_distance_m': checkInDistanceM,
    'check_out_at': checkOutAt?.toUtc().toIso8601String(),
    'duration_minutes': durationMinutes,
    'is_active': isActive,
    'mock_location_flag': mockLocationFlag,
    'pending_sync': isPendingSync,
  };
}

AttendanceRecord? _recordOrNull(dynamic rec) => rec == null
    ? null
    : AttendanceRecord.fromJson(Map<String, dynamic>.from(rec as Map));

/// Today's most recent record (null if no check-in yet today).
///
/// Offline-aware: while there are unsynced local actions, the optimistic cached
/// record is shown; otherwise the server is the source of truth and is cached
/// for the next time the app is offline.
final todayProvider = FutureProvider<AttendanceRecord?>((ref) async {
  final dio = ref.watch(dioProvider);
  final store = ref.watch(offlineStoreProvider);
  try {
    final res = await dio.get('/api/attendance/me/today');
    final rec = res.data['record'];
    if (store.hasPending) {
      // Keep showing the optimistic local state until the queue drains.
      final cached = store.readToday();
      return cached == null
          ? _recordOrNull(rec)
          : AttendanceRecord.fromJson(cached);
    }
    await store.writeToday(
      rec == null ? null : Map<String, dynamic>.from(rec as Map),
    );
    return _recordOrNull(rec);
  } on DioException catch (e) {
    if (e.response == null) {
      // Offline: show the last known / optimistic record.
      final cached = store.readToday();
      return cached == null ? null : AttendanceRecord.fromJson(cached);
    }
    rethrow;
  }
});

/// Recent attendance history (most recent first).
final historyProvider = FutureProvider<List<AttendanceRecord>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/api/attendance/me/history');
  final raw = (res.data['records'] as List).cast<dynamic>();
  return raw
      .map((e) => AttendanceRecord.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
});
