import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/offline/offline_store.dart';

/// One of the manager's people, as they stand this morning.
class TeamMember {
  const TeamMember({
    required this.employeeId,
    required this.fullName,
    required this.department,
    required this.checkedInAt,
    required this.checkedInBy,
    required this.manual,
    required this.onLeave,
    required this.note,
    required this.noteSharedWithHr,
    this.pendingSync = false,
  });

  final String employeeId;
  final String fullName;
  final String department;

  /// "07:42" once they're in, null while they're not.
  final String? checkedInAt;

  /// Set when a manager vouched for them rather than their phone reporting.
  final String? checkedInBy;
  final bool manual;

  /// The leave type they're approved to be away on, if any.
  final String? onLeave;
  final String? note;
  final bool noteSharedWithHr;

  /// Marked on this device while offline, not yet acknowledged by the server.
  final bool pendingSync;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  TeamMember copyWith({bool? pendingSync}) => TeamMember(
    employeeId: employeeId,
    fullName: fullName,
    department: department,
    checkedInAt: checkedInAt,
    checkedInBy: checkedInBy,
    manual: manual,
    onLeave: onLeave,
    note: note,
    noteSharedWithHr: noteSharedWithHr,
    pendingSync: pendingSync ?? this.pendingSync,
  );

  factory TeamMember.fromJson(Map<String, dynamic> j) {
    final note = j['note'] is Map ? Map<String, dynamic>.from(j['note']) : null;
    return TeamMember(
      employeeId: j['employee_id'] as String? ?? '',
      fullName: j['full_name'] as String? ?? '',
      department: j['department'] as String? ?? '',
      checkedInAt: j['checked_in_at'] as String?,
      checkedInBy: j['checked_in_by'] as String?,
      manual: j['manual'] as bool? ?? false,
      onLeave: j['on_leave'] as String?,
      note: note?['text'] as String?,
      noteSharedWithHr: note?['shared_with_hr'] as bool? ?? false,
    );
  }
}

/// The manager's department at a glance, for today.
class TeamRoster {
  const TeamRoster({
    required this.date,
    required this.scope,
    required this.holiday,
    required this.pending,
    required this.present,
    required this.excused,
    this.fromCache = false,
  });

  final String date;

  /// The department code being shown, or "all" for System Admin.
  final String scope;

  /// Non-empty when today is a gazetted public holiday.
  final String holiday;

  /// Not signed in and not on leave — the short list the screen is built for.
  final List<TeamMember> pending;
  final List<TeamMember> present;
  final List<TeamMember> excused;

  /// True when this came off the device rather than the server.
  final bool fromCache;

  int get total => pending.length + present.length + excused.length;

  factory TeamRoster.fromJson(Map<String, dynamic> j, {bool fromCache = false}) {
    List<TeamMember> people(String key) =>
        ((j[key] as List?) ?? const [])
            .map((e) => TeamMember.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
    return TeamRoster(
      date: j['date'] as String? ?? '',
      scope: j['scope'] as String? ?? '',
      holiday: j['holiday'] as String? ?? '',
      pending: people('pending'),
      present: people('present'),
      excused: people('excused'),
      fromCache: fromCache,
    );
  }

  /// Fold in marks this device has made but not yet synced, so a manager who
  /// is offline sees the effect of their own taps instead of a list that
  /// stubbornly still says nobody is in.
  TeamRoster withPendingMarks(Set<String> markedIds) {
    if (markedIds.isEmpty) return this;
    final stillPending = <TeamMember>[];
    final nowPresent = [...present];
    for (final m in pending) {
      if (markedIds.contains(m.employeeId)) {
        nowPresent.add(m.copyWith(pendingSync: true));
      } else {
        stillPending.add(m);
      }
    }
    return TeamRoster(
      date: date,
      scope: scope,
      holiday: holiday,
      pending: stillPending,
      present: nowPresent,
      excused: excused,
      fromCache: fromCache,
    );
  }
}

/// Today's roster for the signed-in manager. Cached on the device, because the
/// gate where a phone-less worker needs marking in is exactly where the signal
/// isn't.
final teamRosterProvider = FutureProvider<TeamRoster>((ref) async {
  final dio = ref.watch(dioProvider);
  final store = ref.watch(offlineStoreProvider);
  try {
    final res = await dio.get('/api/attendance/team/today');
    final raw = Map<String, dynamic>.from(res.data as Map);
    await store.writeTeam(raw);
    return TeamRoster.fromJson(raw).withPendingMarks(store.pendingTeamMarks);
  } on DioException catch (e) {
    if (e.response == null) {
      final cached = store.readTeam();
      if (cached != null) {
        return TeamRoster.fromJson(cached, fromCache: true)
            .withPendingMarks(store.pendingTeamMarks);
      }
    }
    rethrow;
  }
});
