import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';

class _RequestType {
  const _RequestType(this.title, this.subtitle, this.icon, this.color, this.route);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
}

const _types = [
  _RequestType(
    'Leave',
    'Annual, medical, maternity/paternity, unpaid, others',
    Icons.beach_access_outlined,
    Brand.green,
    '/requests/leave',
  ),
  _RequestType(
    'Store request',
    'Materials or items from stores',
    Icons.inventory_2_outlined,
    Brand.orange,
    '/requests/store',
  ),
  _RequestType(
    'Finance requisition',
    'Funds for an itemised purchase',
    Icons.receipt_long_outlined,
    Brand.blue,
    '/requests/finance',
  ),
];

class RequestsHubScreen extends StatelessWidget {
  const RequestsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: AppBar(
        title: const Text('Requests'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _types
            .map(
              (t) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: Brand.shadowCard,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(t.icon, color: t.color),
                  ),
                  title: Text(
                    t.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Brand.ink,
                    ),
                  ),
                  subtitle: Text(
                    t.subtitle,
                    style: const TextStyle(color: Brand.slate, fontSize: 12.5),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Brand.mute),
                  onTap: () => context.push(t.route),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
