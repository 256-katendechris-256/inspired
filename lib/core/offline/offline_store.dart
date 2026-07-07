import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Local persistence for offline-first attendance:
///   - cached reference data (the employee's sites/blocks) so the geofence
///     works with no connection,
///   - the last known "today" record so the card shows status offline,
///   - a FIFO queue of check-in/out actions taken offline, awaiting sync.
///
/// Backed by SharedPreferences (JSON). Attendance volume is tiny (a couple of
/// actions per person per day), so a heavier store isn't warranted yet; the
/// project also bundles sqflite if the queue ever needs to scale.
class OfflineStore {
  OfflineStore(this._prefs);
  final SharedPreferences _prefs;

  static const _kSites = 'offline.sites.v1';
  static const _kToday = 'offline.today.v1';
  static const _kQueue = 'offline.queue.v1';

  // --- Cached sites (the raw 'sites' list from /me/sites) ---
  List<dynamic>? readSites() {
    final s = _prefs.getString(_kSites);
    if (s == null) return null;
    final v = jsonDecode(s);
    return v is List ? v : null;
  }

  Future<void> writeSites(List<dynamic> sites) =>
      _prefs.setString(_kSites, jsonEncode(sites));

  // --- Cached today record (the 'record' map, or null if not checked in) ---
  Map<String, dynamic>? readToday() {
    final s = _prefs.getString(_kToday);
    if (s == null) return null;
    final v = jsonDecode(s);
    return v is Map<String, dynamic> ? v : null;
  }

  Future<void> writeToday(Map<String, dynamic>? record) => record == null
      ? _prefs.remove(_kToday)
      : _prefs.setString(_kToday, jsonEncode(record));

  // --- Pending action queue (FIFO) ---
  List<Map<String, dynamic>> readQueue() {
    final s = _prefs.getString(_kQueue);
    if (s == null) return [];
    final v = jsonDecode(s);
    if (v is! List) return [];
    return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  Future<void> writeQueue(List<Map<String, dynamic>> queue) =>
      _prefs.setString(_kQueue, jsonEncode(queue));

  Future<void> enqueue(Map<String, dynamic> action) =>
      writeQueue(readQueue()..add(action));

  Future<void> removeFromQueue(String clientId) => writeQueue(
        readQueue()..removeWhere((a) => a['client_id'] == clientId),
      );

  bool get hasPending => readQueue().isNotEmpty;
}

final offlineStoreProvider = Provider<OfflineStore>(
  (ref) => OfflineStore(ref.watch(sharedPreferencesProvider)),
);
