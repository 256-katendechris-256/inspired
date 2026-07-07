import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/brand.dart';
import '../../../core/location.dart';
import '../../attendance/sites.dart';

/// Dashboard map: a modern basemap showing the campus, every block's precise
/// 50–100 m geofence, the employee's live position, and which block (if any)
/// they're currently within.
class GeofenceMap extends ConsumerWidget {
  const GeofenceMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(activeSiteProvider);
    final sitesAsync = ref.watch(sitesProvider);
    final fix = ref.watch(livePositionProvider).valueOrNull;
    final me = fix?.latLng;
    final accuracy = fix?.accuracyM;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: Brand.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 280,
            child: sitesAsync.isLoading
                ? const Center(child: CircularProgressIndicator())
                : site == null
                ? _NoSite(error: sitesAsync.hasError)
                : _Map(site: site, me: me, accuracyM: accuracy),
          ),
          if (site != null) _RangeBar(site: site, me: me),
        ],
      ),
    );
  }
}

class _Map extends StatelessWidget {
  const _Map({required this.site, required this.me, this.accuracyM});
  final Site site;
  final LatLng? me;
  final double? accuracyM;

  /// Accent color per block, cycled from the brand palette.
  Color _blockColor(int i) => Brand.accents[i % Brand.accents.length];

  @override
  Widget build(BuildContext context) {
    final blocks = site.blocks;
    final points = <LatLng>[
      site.center,
      ...blocks.map((b) => b.center),
      ?me,
    ];

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(48),
          maxZoom: 17,
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
          userAgentPackageName: 'ug.inspireafrica.app',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        // The whole campus / land boundary (the "vicinity"), drawn first so the
        // tighter block geofences sit on top of it. Brighter stroke so it reads
        // on satellite imagery.
        CircleLayer(
          circles: [
            CircleMarker(
              point: site.center,
              radius: site.radiusM.toDouble(),
              useRadiusInMeter: true,
              color: Brand.green.withValues(alpha: 0.06),
              borderColor: Brand.green.withValues(alpha: 0.65),
              borderStrokeWidth: 2,
            ),
          ],
        ),
        CircleLayer(
          circles: [
            for (var i = 0; i < blocks.length; i++)
              CircleMarker(
                point: blocks[i].center,
                radius: blocks[i].radiusM.toDouble(),
                useRadiusInMeter: true,
                color: _blockColor(i).withValues(alpha: 0.18),
                borderColor: _blockColor(i),
                borderStrokeWidth: 2,
              ),
          ],
        ),
        // GPS accuracy halo around the live position.
        if (me != null && accuracyM != null && accuracyM! > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: me!,
                radius: accuracyM!,
                useRadiusInMeter: true,
                color: Brand.blue.withValues(alpha: 0.12),
                borderColor: Brand.blue.withValues(alpha: 0.35),
                borderStrokeWidth: 1,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (var i = 0; i < blocks.length; i++)
              Marker(
                point: blocks[i].center,
                width: 120,
                height: 30,
                child: _BlockPill(label: blocks[i].name, color: _blockColor(i)),
              ),
            if (me != null)
              Marker(
                point: me!,
                width: 22,
                height: 22,
                child: const _MeDot(),
              ),
          ],
        ),
      ],
    );
  }
}

class _BlockPill extends StatelessWidget {
  const _BlockPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
          ],
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: Brand.blue.withValues(alpha: 0.5), blurRadius: 8),
        ],
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.site, required this.me});
  final Site site;
  final LatLng? me;

  static String _fmt(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (site.blocks.isEmpty) {
      return _bar(theme, Icons.info_outline, Brand.slate,
          'No check-in blocks set up for ${site.shortLabel} yet.');
    }
    if (me == null) {
      return _bar(theme, Icons.my_location, Brand.slate,
          'Enable location to see your distance to the check-in point.');
    }

    // Tier 1 — the campus / land vicinity.
    final campusDist = metresBetween(me!, site.center);
    final inCampus = campusDist <= site.radiusM;
    final toEdge = (campusDist - site.radiusM).clamp(0.0, double.infinity);

    // Tier 2 — the designated check-in block (Admin block for now).
    final target = site.designatedBlock!;
    final targetDist = metresBetween(me!, target.center);
    final atTarget = targetDist <= target.radiusM;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _bar(
          theme,
          inCampus ? Icons.verified : Icons.directions_walk,
          inCampus ? Brand.green : Brand.orange,
          inCampus
              ? 'Inside ${site.shortLabel} grounds.'
              : '${_fmt(toEdge)} to the ${site.shortLabel} boundary.',
        ),
        _bar(
          theme,
          atTarget ? Icons.check_circle : Icons.place,
          atTarget ? Brand.green : Brand.blue,
          atTarget
              ? 'At ${target.name} — you can check in now.'
              : '${target.name}: ${_fmt(targetDist)} away · check in within ${target.radiusM} m.',
        ),
      ],
    );
  }

  Widget _bar(ThemeData theme, IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: color.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _NoSite extends StatelessWidget {
  const _NoSite({required this.error});
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(error ? Icons.cloud_off : Icons.map_outlined,
                color: Brand.slate, size: 36),
            const SizedBox(height: 8),
            Text(
              error
                  ? 'Couldn’t load your site. Pull to refresh.'
                  : 'No site assigned to you yet. Contact your administrator.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.slate),
            ),
          ],
        ),
      ),
    );
  }
}
