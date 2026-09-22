import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/brand.dart';
import 'inbox_data.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);

    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: [
          if ((inbox.value?.unread ?? 0) > 0)
            TextButton(
              onPressed: () => markRead(ref, all: true),
              child: const Text(
                'Mark all read',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: Brand.green,
        onRefresh: () => ref.refresh(inboxProvider.future),
        child: inbox.when(
          data: (data) {
            if (data.items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.notifications_none, size: 48, color: Brand.mute),
                  SizedBox(height: 12),
                  Center(
                    child: Text(
                      'No notifications yet.',
                      style: TextStyle(color: Brand.slate),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: data.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _InboxTile(item: data.items[i]),
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: Brand.green),
          ),
          error: (_, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              Center(
                child: Text(
                  "Couldn't load notifications. Pull down to try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Brand.slate),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxTile extends ConsumerWidget {
  const _InboxTile({required this.item});
  final InboxItem item;

  IconData get _icon => switch (item.kind) {
        'leave' => Icons.beach_access_outlined,
        'store' => Icons.inventory_2_outlined,
        'finance' => Icons.payments_outlined,
        'task' => Icons.checklist_rtl,
        'attendance' => Icons.schedule_outlined,
        _ => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = item.isRead;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        if (!read) await markRead(ref, ids: [item.id]);
        final route = item.route;
        if (route != null && context.mounted) context.push(route);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: read ? Colors.white : Brand.green.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: read ? Brand.line : Brand.green.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, color: read ? Brand.mute : Brand.green, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: read ? FontWeight.w600 : FontWeight.w700,
                      color: read ? Brand.slate : Brand.ink,
                    ),
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: TextStyle(
                        color: read ? Brand.mute : Brand.slate,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('MMM d, y · h:mm a').format(item.createdAt),
                    style: const TextStyle(color: Brand.mute, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (item.route != null)
              const Icon(Icons.chevron_right, color: Brand.mute, size: 20),
          ],
        ),
      ),
    );
  }
}
