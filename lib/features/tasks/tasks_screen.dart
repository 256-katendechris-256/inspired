import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/brand.dart';

/// A job your HOD has handed you. You move it from open → in progress →
/// done (with a note); only the HOD can cancel or reassign it.
class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.description,
    required this.assignedByName,
    required this.dueDate,
    required this.priority,
    required this.status,
    required this.completionNote,
    required this.isOverdue,
  });

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
        id: j['id'] as int,
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        assignedByName: j['assigned_by_name'] as String? ?? 'Your HOD',
        dueDate: j['due_date'] as String?,
        priority: j['priority'] as String? ?? 'normal',
        status: j['status'] as String? ?? 'open',
        completionNote: j['completion_note'] as String? ?? '',
        isOverdue: j['is_overdue'] as bool? ?? false,
      );

  final int id;
  final String title;
  final String description;
  final String assignedByName;
  final String? dueDate;
  final String priority;
  final String status;
  final String completionNote;
  final bool isOverdue;

  bool get isActive => status == 'open' || status == 'in_progress';
}

final tasksProvider = FutureProvider<List<TaskItem>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/api/tasks/');
  return (res.data['tasks'] as List)
      .map((e) => TaskItem.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
});

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: AppBar(
        title: const Text('My tasks'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: RefreshIndicator(
        color: Brand.green,
        onRefresh: () => ref.refresh(tasksProvider.future),
        child: tasks.when(
          data: (list) {
            final active = list.where((t) => t.isActive).toList();
            final finished = list.where((t) => !t.isActive).toList();
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.task_alt, size: 48, color: Brand.mute),
                  SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Nothing assigned to you right now.',
                      style: TextStyle(color: Brand.slate),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (active.isNotEmpty) ...[
                  const _SectionLabel('To do'),
                  for (final t in active) _TaskCard(task: t),
                ],
                if (finished.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const _SectionLabel('Done'),
                  for (final t in finished) _TaskCard(task: t),
                ],
              ],
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
                  "Couldn't load your tasks. Pull down to try again.",
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Brand.mute,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _TaskCard extends ConsumerStatefulWidget {
  const _TaskCard({required this.task});
  final TaskItem task;

  @override
  ConsumerState<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<_TaskCard> {
  bool _busy = false;

  Future<void> _update(String status, {String? note}) async {
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).patch(
        '/api/tasks/${widget.task.id}',
        data: {'status': status, 'completion_note': ?note},
      );
      ref.invalidate(tasksProvider);
    } on DioException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update the task. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markDone() async {
    final ctrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as done'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Anything your HOD should know? (optional)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (note == null) return;
    await _update('done', note: note);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final (color, label) = switch (t.status) {
      'done' => (Brand.green, 'Done'),
      'cancelled' => (Brand.mute, 'Cancelled'),
      'in_progress' => (Brand.blue, 'In progress'),
      _ => t.isOverdue ? (Brand.red, 'Overdue') : (Brand.orange, 'Open'),
    };
    final due = t.dueDate == null
        ? null
        : DateFormat('EEE d MMM').format(DateTime.parse(t.dueDate!));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: Brand.shadowCard,
        border: t.isOverdue && t.isActive
            ? Border.all(color: Brand.red.withValues(alpha: 0.4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  t.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: t.isActive ? Brand.ink : Brand.slate,
                    decoration: t.status == 'cancelled' ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11.5),
                ),
              ),
            ],
          ),
          if (t.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              t.description,
              style: const TextStyle(color: Brand.slate, fontSize: 13, height: 1.35),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (t.priority == 'high') ...[
                const Icon(Icons.priority_high, size: 14, color: Brand.red),
                const SizedBox(width: 2),
              ],
              Icon(Icons.person_outline, size: 14, color: Brand.mute),
              const SizedBox(width: 4),
              Text(t.assignedByName, style: const TextStyle(color: Brand.mute, fontSize: 12)),
              if (due != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.event_outlined, size: 14, color: t.isOverdue ? Brand.red : Brand.mute),
                const SizedBox(width: 4),
                Text(
                  due,
                  style: TextStyle(color: t.isOverdue ? Brand.red : Brand.mute, fontSize: 12),
                ),
              ],
            ],
          ),
          if (t.completionNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('“${t.completionNote}”',
                style: const TextStyle(color: Brand.green, fontSize: 12.5, fontStyle: FontStyle.italic)),
          ],
          if (t.isActive) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (t.status == 'open')
                  OutlinedButton(
                    onPressed: _busy ? null : () => _update('in_progress'),
                    child: const Text('Start'),
                  ),
                if (t.status == 'open') const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _markDone,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Mark done'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
