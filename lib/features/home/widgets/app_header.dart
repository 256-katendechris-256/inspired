import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand.dart';
import '../../notifications/inbox_data.dart';
import '../../attendance/sites.dart';
import '../../auth/auth_controller.dart';

/// Compact colored top bar: menu button, then "Inspire Africa" with the
/// greeting inline, the active site below, and a notification bell.
class AppHeader extends ConsumerWidget {
  const AppHeader({super.key, required this.onMenu, required this.onNotifications});

  final VoidCallback onMenu;
  final VoidCallback onNotifications;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final site = ref.watch(activeSiteProvider);

    return Container(
      padding: EdgeInsets.fromLTRB(
        6,
        MediaQuery.of(context).padding.top + 6,
        10,
        16,
      ),
      decoration: BoxDecoration(
        gradient: Brand.greenGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: Brand.glow(Brand.green),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenu,
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Menu',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Company + greeting, same line.
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Inspire Africa',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: '  ·  ${_greeting()}, ${user?.firstName ?? 'there'}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white70, size: 13),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        site?.shortLabel ?? 'No site assigned',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _BellButton(onTap: onNotifications),
        ],
      ),
    );
  }
}

class _BellButton extends ConsumerWidget {
  const _BellButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(inboxProvider).value?.unread ?? 0;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          onPressed: onTap,
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          tooltip: 'Notifications',
        ),
        if (unread > 0)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Brand.orange,
                shape: BoxShape.circle,
                border: Border.all(color: Brand.green, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
