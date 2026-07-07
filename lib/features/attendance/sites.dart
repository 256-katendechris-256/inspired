import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_client.dart';
import '../../core/location.dart';
import '../../core/offline/offline_store.dart';

/// A precise geofenced area within a campus (building, yard, gate…).
class Block {
  const Block({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusM,
  });

  final int id;
  final String name;
  final double lat;
  final double lng;
  final int radiusM;

  LatLng get center => LatLng(lat, lng);

  factory Block.fromJson(Map<String, dynamic> json) => Block(
    id: json['id'] as int,
    name: json['name'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    radiusM: json['radius_m'] as int,
  );
}

/// A campus site the employee may check in at, with its geofenced blocks.
class Site {
  const Site({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.blocks,
  });

  final int id;
  final String name;
  final double lat;
  final double lng;
  final int radiusM;
  final List<Block> blocks;

  LatLng get center => LatLng(lat, lng);

  /// "Africa Coffee Park (Ntungamo)" → "ACP Ntungamo" when an acronym fits,
  /// otherwise the plain name.
  String get shortLabel {
    final match = RegExp(r'\(([^)]+)\)').firstMatch(name);
    final place = match?.group(1);
    final base = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    final words = base.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 2 && place != null) {
      final acronym = words.map((w) => w[0].toUpperCase()).join();
      return '$acronym $place';
    }
    return place != null ? '$base · $place' : base;
  }

  /// The block treated as the primary check-in point. For now this is the
  /// "Admin" block by name; if none matches we fall back to the first block.
  /// TODO: replace with a server-set `is_designated` flag on Block.
  Block? get designatedBlock {
    if (blocks.isEmpty) return null;
    for (final b in blocks) {
      if (b.name.toLowerCase().contains('admin')) return b;
    }
    return blocks.first;
  }

  factory Site.fromJson(Map<String, dynamic> json) => Site(
    id: json['id'] as int,
    name: json['name'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    radiusM: json['radius_m'] as int,
    blocks: ((json['blocks'] as List?) ?? const [])
        .map((e) => Block.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

List<Site> _parseSites(List<dynamic> raw) => raw
    .map((e) => Site.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

/// The employee's assigned sites (home_site first). Cached on the device so the
/// map and on-device geofence keep working with no connection.
final sitesProvider = FutureProvider<List<Site>>((ref) async {
  final dio = ref.watch(dioProvider);
  final store = ref.watch(offlineStoreProvider);
  try {
    final res = await dio.get('/api/attendance/me/sites');
    final raw = (res.data['sites'] as List).cast<dynamic>();
    await store.writeSites(raw);
    return _parseSites(raw);
  } on DioException catch (e) {
    // Offline (no server response): fall back to the last cached sites.
    if (e.response == null) {
      final cached = store.readSites();
      if (cached != null) return _parseSites(cached);
    }
    rethrow;
  }
});

/// Result of an on-device geofence match.
class GeoMatch {
  const GeoMatch(this.site, this.block, this.distanceM);
  final Site site;
  final Block? block;
  final double distanceM;
}

/// On-device, GPS-only geofence — mirrors the server's block-precise matching
/// so check-in works offline: among [sites], the nearest active block within
/// its radius wins; a site with no blocks falls back to its own radius.
/// Returns null if [here] is out of range of everything.
GeoMatch? matchCheckInPoint(List<Site> sites, LatLng here) {
  GeoMatch? best;
  double bestD = double.infinity;
  for (final site in sites) {
    if (site.blocks.isNotEmpty) {
      for (final b in site.blocks) {
        final d = metresBetween(here, b.center);
        if (d <= b.radiusM && d < bestD) {
          bestD = d;
          best = GeoMatch(site, b, d);
        }
      }
    } else {
      final d = metresBetween(here, site.center);
      if (d <= site.radiusM && d < bestD) {
        bestD = d;
        best = GeoMatch(site, null, d);
      }
    }
  }
  return best;
}

/// The single site the dashboard map focuses on (the first assigned one).
final activeSiteProvider = Provider<Site?>((ref) {
  final sites = ref.watch(sitesProvider).valueOrNull;
  return (sites == null || sites.isEmpty) ? null : sites.first;
});
