import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand.dart';
import '../../auth/auth_controller.dart';

class _Entry {
  const _Entry(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final void Function(BuildContext, WidgetRef) onTap;
}

/// Slide-out navigation. Holds the app's full menu; the dashboard body stays
/// focused on attendance.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  static void _go(BuildContext context, String route) {
    Navigator.pop(context);
    context.go(route);
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You’ll need your password to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await ref.read(authControllerProvider.notifier).logout();
      if (context.mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;

    final items = <_Entry>[
      _Entry(Icons.dashboard_outlined, 'Dashboard', Brand.green, (c, r) {
        Navigator.pop(c);
      }),
      _Entry(Icons.history, 'Attendance', Brand.green, (c, r) {
        Navigator.pop(c);
        c.go('/history');
      }),
      _Entry(Icons.checklist_rtl, 'Tasks', Brand.blue,
          (c, r) => _go(c, '/tasks')),
      _Entry(Icons.outbox_outlined, 'Requests', Brand.orange,
          (c, r) => _go(c, '/requests')),
      _Entry(Icons.insights_outlined, 'Reports', Brand.blue,
          (c, r) => _go(c, '/reports')),
      _Entry(Icons.person_outline, 'Profile', Brand.green,
          (c, r) => _go(c, '/profile')),
    ];

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(user: user),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...items.map(
              (e) => ListTile(
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: e.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(e.icon, color: e.color, size: 20),
                ),
                title: Text(e.label),
                onTap: () => e.onTap(context, ref),
              ),
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Brand.red),
              title: const Text('Sign out', style: TextStyle(color: Brand.red)),
              onTap: () => _logout(context, ref),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user});
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
          Image.asset(Brand.markAsset, height: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.fullName ?? 'Inspire Africa',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Brand.ink,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _roleLabel(user?.role),
                  style: const TextStyle(color: Brand.slate, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _roleLabel(String? role) => switch (role) {
    'hod' => 'Head of Department',
    'hr' => 'Human Resources',
    'admin' => 'System Admin',
    'exec' => 'Executive',
    _ => 'IAG Staff',
  };
}
