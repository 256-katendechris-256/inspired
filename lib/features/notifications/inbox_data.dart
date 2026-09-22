import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

/// One message in the employee's inbox — a request that moved, a task
/// assigned, a reminder. Mirrors the backend's Notification row.
class InboxItem {
  const InboxItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.refType,
    required this.refId,
    required this.createdAt,
    required this.readAt,
  });

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        id: j['id'] as int,
        kind: j['kind'] as String? ?? 'system',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        refType: j['ref_type'] as String? ?? '',
        refId: j['ref_id'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        readAt: j['read_at'] == null
            ? null
            : DateTime.parse(j['read_at'] as String).toLocal(),
      );

  final int id;
  final String kind;
  final String title;
  final String body;
  final String refType;
  final String refId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// Where tapping this should take the employee.
  String? get route => switch (refType) {
        'leave_request' => '/requests/leave',
        'store_request' => '/requests/store',
        'finance_requisition' => '/requests/finance',
        'task' => '/tasks',
        _ => null,
      };
}

class Inbox {
  const Inbox({required this.unread, required this.items});
  final int unread;
  final List<InboxItem> items;
}

final inboxProvider = FutureProvider<Inbox>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/api/notifications/inbox', queryParameters: {'limit': 50});
  final raw = (res.data['notifications'] as List).cast<dynamic>();
  return Inbox(
    unread: res.data['unread'] as int? ?? 0,
    items: raw
        .map((e) => InboxItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
});

Future<void> markRead(WidgetRef ref, {List<int>? ids, bool all = false}) async {
  final dio = ref.read(dioProvider);
  await dio.post(
    '/api/notifications/inbox',
    data: all ? {'all': true} : {'ids': ids ?? const []},
  );
  ref.invalidate(inboxProvider);
}
