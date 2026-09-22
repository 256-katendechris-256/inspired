import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/offline/offline_store.dart';
import '../attendance/attendance_controller.dart' show ActionResult;
import 'team_data.dart';

/// Marking someone in, and saying why someone isn't here — both of which have
/// to work at a gate with no signal, so both go through the same queue as an
/// ordinary check-in.
class TeamController extends StateNotifier<bool> {
  TeamController(this._ref) : super(false) {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) syncPending();
    });
    _lifecycle = AppLifecycleListener(onResume: syncPending);
    syncPending();
  }

  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  AppLifecycleListener? _lifecycle;
  bool _syncing = false;

  OfflineStore get _store => _ref.read(offlineStoreProvider);
  Dio get _dio => _ref.read(dioProvider);

  static const _markPath = '/api/attendance/team/mark';
  static const _notePath = '/api/attendance/team/absence-note';

  @override
  void dispose() {
    _connSub?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Record attendance for [employeeId]. Tries the server, queues if it can't
  /// be reached — the manager gets the same answer either way, because from
  /// where they're standing the person is present regardless.
  Future<ActionResult> mark(String employeeId, String fullName) async {
    final at = DateTime.now();
    final action = {
      'type': 'mark',
      'client_id': '$employeeId-${at.microsecondsSinceEpoch}',
      'employee_id': employeeId,
      'occurred_at': at.toUtc().toIso8601String(),
    };
    try {
      await _dio.post(_markPath, data: {
        'employee_id': employeeId,
        'occurred_at': action['occurred_at'],
      });
      _refresh();
      return ActionResult.success('$fullName signed in.');
    } on DioException catch (e) {
      if (e.response != null) return ActionResult.failure(_message(e));
      await _store.enqueueTeam(action);
      _refresh();
      return ActionResult.success(
        '$fullName marked in — it will sync when you’re back online.',
      );
    }
  }

  /// Record why someone isn't here, optionally raising it to HR.
  Future<ActionResult> note(
    String employeeId,
    String fullName,
    String text, {
    required bool shareWithHr,
  }) async {
    final at = DateTime.now();
    final action = {
      'type': 'note',
      'client_id': '$employeeId-note-${at.microsecondsSinceEpoch}',
      'employee_id': employeeId,
      'note': text,
      'share_with_hr': shareWithHr,
    };
    try {
      await _dio.post(_notePath, data: {
        'employee_id': employeeId,
        'note': text,
        'share_with_hr': shareWithHr,
      });
      _refresh();
      return ActionResult.success(
        shareWithHr ? 'Noted and sent to HR.' : 'Noted.',
      );
    } on DioException catch (e) {
      if (e.response != null) return ActionResult.failure(_message(e));
      await _store.enqueueTeam(action);
      _refresh();
      return ActionResult.success(
        shareWithHr
            ? 'Saved — HR will be told when you’re back online.'
            : 'Saved — it will sync when you’re back online.',
      );
    }
  }

  /// Flush queued marks and notes. Same rules as the attendance queue: only a
  /// considered no from the server retires an action.
  Future<void> syncPending() async {
    if (_syncing) return;
    final queue = _store.readTeamQueue();
    if (queue.isEmpty) return;
    final token = _ref.read(authTokenStoreProvider).accessToken;
    if (token == null || token.isEmpty) return;
    _syncing = true;
    try {
      for (final action in List<Map<String, dynamic>>.from(queue)) {
        final isNote = action['type'] == 'note';
        try {
          await _dio.post(
            isNote ? _notePath : _markPath,
            data: isNote
                ? {
                    'employee_id': action['employee_id'],
                    'note': action['note'],
                    'share_with_hr': action['share_with_hr'] ?? false,
                  }
                : {
                    'employee_id': action['employee_id'],
                    'occurred_at': action['occurred_at'],
                  },
          );
          await _store.removeFromTeamQueue(action['client_id'] as String);
        } on DioException catch (e) {
          if (e.response == null) return; // still offline
          final code = e.response!.statusCode ?? 0;
          if (code == 401 || code == 403 || code >= 500) return;
          await _store.removeFromTeamQueue(action['client_id'] as String);
        }
      }
      _refresh();
    } finally {
      _syncing = false;
    }
  }

  void _refresh() => _ref.invalidate(teamRosterProvider);

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return 'Something went wrong. Please try again.';
  }
}

final teamControllerProvider = StateNotifierProvider<TeamController, bool>(
  (ref) => TeamController(ref),
);
