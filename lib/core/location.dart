import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// A position reading with its reported horizontal accuracy (metres).
class PositionFix {
  const PositionFix(this.latLng, this.accuracyM);
  final LatLng latLng;
  final double? accuracyM;
}

/// Best-effort current position with accuracy. Returns null if location is off
/// or the user denies permission — callers degrade gracefully.
Future<PositionFix?> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return PositionFix(LatLng(pos.latitude, pos.longitude), pos.accuracy);
  } catch (_) {
    return null;
  }
}

/// Best-effort current position (lat/lng only). Returns null if unavailable.
Future<LatLng?> currentLatLng() async => (await currentPosition())?.latLng;

final currentLocationProvider = FutureProvider<LatLng?>(
  (ref) => currentLatLng(),
);

/// Live device position (lat/lng + accuracy), updating as you move. Auto-stops
/// when nothing is watching it (e.g. you leave the map) to save battery.
/// Emits null if location is off or permission is denied.
final livePositionProvider = StreamProvider.autoDispose<PositionFix?>((ref) async* {
  if (!await Geolocator.isLocationServiceEnabled()) {
    yield null;
    return;
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.deniedForever) {
    yield null;
    return;
  }
  PositionFix? last;
  final first = await currentPosition();
  if (first != null) {
    last = first;
    yield first;
  }
  await for (final p in Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  )) {
    // Drop unusable fixes.
    if (p.accuracy <= 0 || p.accuracy > 100) continue;
    final fix = PositionFix(LatLng(p.latitude, p.longitude), p.accuracy);
    // Dead-band: ignore movement smaller than the GPS noise floor so the dot
    // stays put when you're stationary instead of bouncing around. It only
    // moves once you've genuinely walked beyond the uncertainty.
    if (last != null) {
      final moved = metresBetween(last.latLng, fix.latLng);
      final noiseFloor = (p.accuracy * 0.6).clamp(10.0, 35.0);
      if (moved < noiseFloor) continue;
    }
    last = fix;
    yield fix;
  }
});

/// Metres between two points (great-circle).
double metresBetween(LatLng a, LatLng b) =>
    const Distance().as(LengthUnit.Meter, a, b);
