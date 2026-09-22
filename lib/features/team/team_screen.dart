import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import 'team_controller.dart';
import 'team_data.dart';

/// The manager's department, this morning.
///
/// Built around the short list: the people who haven't signed in. On a normal
/// day that's a handful of names, so marking one in is a tap, not a search
/// through a roster.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(teamRosterProvider);
    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: AppBar(
        title: const Text('My department'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: RefreshIndicator(
        color: Brand.green,
        onRefresh: () async {
          ref.invalidate(teamRosterProvider);
          await ref.read(teamRosterProvider.future);
        },
        child: roster.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              Icon(Icons.cloud_off, size: 36, color: Brand.slate),
              SizedBox(height: 10),
              Center(
                child: Text(
                  'Couldn’t load your department, and nothing is saved on\n'
                  'this phone yet. Pull down to try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Brand.slate),
                ),
              ),
            ],
          ),
          data: (r) => _Body(roster: r),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.roster});
  final TeamRoster roster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _Summary(roster: roster),
        if (roster.fromCache) ...[
          const SizedBox(height: 10),
          const _Banner(
            icon: Icons.wifi_off,
            text:
                'Showing the last list saved on this phone. Anything you '
                'record now is sent when you’re back online.',
          ),
        ],
        if (roster.holiday.isNotEmpty) ...[
          const SizedBox(height: 10),
          _Banner(
            icon: Icons.celebration_outlined,
            text:
                '${roster.holiday} — a public holiday. Anyone working today '
                'is on overtime.',
          ),
        ],
        const SizedBox(height: 20),
        if (roster.pending.isNotEmpty) ...[
          _SectionLabel(
            'Not signed in',
            count: roster.pending.length,
            tone: Brand.orange,
          ),
          const SizedBox(height: 8),
          ...roster.pending.map((m) => _PendingTile(member: m)),
          const SizedBox(height: 20),
        ] else ...[
          const _AllIn(),
          const SizedBox(height: 20),
        ],
        if (roster.present.isNotEmpty) ...[
          _SectionLabel(
            'Signed in',
            count: roster.present.length,
            tone: Brand.green,
          ),
          const SizedBox(height: 8),
          ...roster.present.map((m) => _PresentTile(member: m)),
          const SizedBox(height: 20),
        ],
        if (roster.excused.isNotEmpty) ...[
          _SectionLabel(
            'On leave',
            count: roster.excused.length,
            tone: Brand.blue,
          ),
          const SizedBox(height: 8),
          ...roster.excused.map((m) => _ExcusedTile(member: m)),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.roster});
  final TeamRoster roster;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: Brand.greenGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            roster.scope == 'all' ? 'All departments' : roster.scope,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Stat(value: roster.present.length, label: 'in'),
              _Stat(value: roster.pending.length, label: 'not in'),
              _Stat(value: roster.excused.length, label: 'on leave'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.count, required this.tone});
  final String text;
  final int count;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Brand.ink,
            fontSize: 15,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: tone,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.member, required this.tone});
  final TeamMember member;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        member.initials,
        style: TextStyle(
          color: tone,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _PendingTile extends ConsumerWidget {
  const _PendingTile({required this.member});
  final TeamMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(teamControllerProvider);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Avatar(member: member, tone: Brand.orange),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Brand.ink,
                      ),
                    ),
                    Text(
                      member.employeeId,
                      style: const TextStyle(color: Brand.mute, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => _note(context, ref),
                style: TextButton.styleFrom(
                  foregroundColor: Brand.slate,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                ),
                child: Text(member.note == null ? 'Why?' : 'Note'),
              ),
              const SizedBox(width: 2),
              FilledButton(
                onPressed: busy ? null : () => _mark(context, ref),
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.green,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('Sign in'),
              ),
            ],
          ),
          if (member.note != null) ...[
            const SizedBox(height: 8),
            _NoteStrip(member: member),
          ],
        ],
      ),
    );
  }

  Future<void> _mark(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Sign in ${member.fullName}?'),
        content: const Text(
          'Only do this for someone who is here but can’t sign in from their '
          'own phone. It is recorded against your name.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sign them in'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final res = await ref
        .read(teamControllerProvider.notifier)
        .mark(member.employeeId, member.fullName);
    if (context.mounted) _toast(context, res.message, ok: res.ok);
  }

  Future<void> _note(BuildContext context, WidgetRef ref) =>
      showAbsenceNoteSheet(context, ref, member);
}

class _PresentTile extends StatelessWidget {
  const _PresentTile({required this.member});
  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    final sub = member.pendingSync
        ? 'Marked in by you — waiting to sync'
        : member.checkedInBy != null
        ? '${member.checkedInAt} · signed in by ${member.checkedInBy}'
        : '${member.checkedInAt} · own phone';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        children: [
          _Avatar(member: member, tone: Brand.green),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Brand.ink,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(color: Brand.slate, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Icon(
            member.pendingSync ? Icons.schedule : Icons.check_circle,
            color: member.pendingSync ? Brand.orange : Brand.green,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _ExcusedTile extends StatelessWidget {
  const _ExcusedTile({required this.member});
  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        children: [
          _Avatar(member: member, tone: Brand.blue),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Brand.ink,
                  ),
                ),
                Text(
                  'Approved ${member.onLeave ?? 'leave'}',
                  style: const TextStyle(color: Brand.blue, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteStrip extends StatelessWidget {
  const _NoteStrip({required this.member});
  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Brand.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            member.noteSharedWithHr ? Icons.forward_to_inbox : Icons.notes,
            size: 13,
            color: member.noteSharedWithHr ? Brand.blue : Brand.slate,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              member.noteSharedWithHr
                  ? '${member.note}  ·  sent to HR'
                  : member.note!,
              style: const TextStyle(
                color: Brand.slate,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Brand.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Brand.slate),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Brand.slate,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllIn extends StatelessWidget {
  const _AllIn();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26),
      alignment: Alignment.center,
      child: const Column(
        children: [
          Icon(Icons.verified_outlined, color: Brand.green, size: 32),
          SizedBox(height: 8),
          Text(
            'Everyone is accounted for.',
            style: TextStyle(color: Brand.slate),
          ),
        ],
      ),
    );
  }
}

/// Write (or correct) the reason someone isn't at work, and optionally put it
/// in front of HR.
Future<void> showAbsenceNoteSheet(
  BuildContext context,
  WidgetRef ref,
  TeamMember member,
) async {
  final controller = TextEditingController(text: member.note ?? '');
  var share = member.noteSharedWithHr;
  var saving = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
      ),
      child: StatefulBuilder(
        builder: (c, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              member.fullName,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Brand.ink,
              ),
            ),
            const Text(
              'Why are they not at work today?',
              style: TextStyle(color: Brand.slate, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. Sent word he is unwell, expects to be in '
                    'tomorrow.',
              ),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: share,
              onChanged: saving
                  ? null
                  : (v) => setSheetState(() => share = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Brand.green,
              title: const Text(
                'Send to HR',
                style: TextStyle(fontSize: 14, color: Brand.ink),
              ),
              subtitle: const Text(
                'Puts it in their inbox and emails them. Leave it off to '
                'keep your own record.',
                style: TextStyle(fontSize: 11.5, color: Brand.slate),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;
                        setSheetState(() => saving = true);
                        final res = await ref
                            .read(teamControllerProvider.notifier)
                            .note(
                              member.employeeId,
                              member.fullName,
                              text,
                              shareWithHr: share,
                            );
                        if (c.mounted) Navigator.pop(c);
                        if (context.mounted) {
                          _toast(context, res.message, ok: res.ok);
                        }
                      },
                child: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(share ? 'Save and send to HR' : 'Save note'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  controller.dispose();
}

void _toast(BuildContext context, String message, {required bool ok}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: ok ? Brand.green : Brand.red,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
