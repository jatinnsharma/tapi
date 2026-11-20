import 'package:latlong2/latlong.dart';

import 'shared_memory.dart';

/// A capsule is announced when the user comes this close.
const capsuleRevealMeters = 25.0;

/// Nearby capsules are fetched again after this long...
const capsuleRefetchAfter = Duration(minutes: 5);

/// ...or after moving this far from the last fetch.
const capsuleRefetchMeters = 300.0;

/// Whether to ask the server for nearby capsules again.
bool shouldFetchCapsules({
  required DateTime now,
  required LatLng here,
  DateTime? lastAt,
  LatLng? lastWhere,
}) {
  if (lastAt == null || lastWhere == null) return true;
  if (now.difference(lastAt) >= capsuleRefetchAfter) return true;
  return const Distance()(lastWhere, here) >= capsuleRefetchMeters;
}

/// Capsules within [capsuleRevealMeters] of [here] that haven't been
/// announced yet ([announced] ids), nearest first.
List<SharedMemory> capsulesToAnnounce(
  List<SharedMemory> capsules,
  LatLng here, {
  Set<String> announced = const {},
}) {
  const distance = Distance();
  final close = <(SharedMemory, double)>[];
  for (final c in capsules) {
    final lat = c.latitude, lng = c.longitude;
    if (lat == null || lng == null || announced.contains(c.id)) continue;
    final d = distance(here, LatLng(lat, lng));
    if (d <= capsuleRevealMeters) close.add((c, d));
  }
  close.sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (c, _) in close) c];
}
