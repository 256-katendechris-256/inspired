import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../core/location.dart';
import '../attendance/attendance_data.dart';
import '../attendance/sites.dart';
import 'widgets/app_drawer.dart';
import 'widgets/app_header.dart';
import 'widgets/geofence_map.dart';
import 'widgets/home_carousel.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Builder(
            builder: (ctx) => AppHeader(
              onMenu: () => Scaffold.of(ctx).openDrawer(),
              onNotifications: () => ctx.go('/notifications'),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: Brand.green,
              onRefresh: () async {
                ref.invalidate(sitesProvider);
                ref.invalidate(currentLocationProvider);
                ref.invalidate(livePositionProvider);
                ref.invalidate(todayProvider);
                await ref.read(sitesProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  const SizedBox(height: 2),
                  const HomeCarousel(),
                  const SizedBox(height: 26),
                  _SectionLabel('WHERE TO CHECK IN'),
                  const SizedBox(height: 12),
                  const GeofenceMap(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Brand.mute,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

