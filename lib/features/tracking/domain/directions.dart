import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'checkpoint.dart';

/// Where an adventure is heading: a single place the user chose to walk to.
/// Doubles as a provider key, so it has value equality.
class Destination {
  const Destination({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.xpReward = 50,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int xpReward;

  LatLng get point => LatLng(latitude, longitude);

  /// Id prefix of the checkpoint created for a destination.
  static const checkpointIdPrefix = 'dest-';

  /// The checkpoint that rewards arriving: reaching within 40 m awards XP
  /// through the normal checkpoint logic.
  Checkpoint toCheckpoint() => Checkpoint(
    id: '$checkpointIdPrefix$id',
    adventureId: '',
    name: name,
    latitude: latitude,
    longitude: longitude,
    radiusMeters: 40,
    xpReward: xpReward,
  );

  @override
  bool operator ==(Object other) =>
      other is Destination &&
      other.id == id &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(id, latitude, longitude);
}

/// One manoeuvre of a route: what to do, and where.
class DirectionStep {
  const DirectionStep({
    required this.instruction,
    required this.icon,
    required this.location,
    required this.distanceMeters,
  });

  /// e.g. "Turn left onto Uttar Marg".
  final String instruction;
  final IconData icon;

  /// Where the manoeuvre happens.
  final LatLng location;

  /// Length of the stretch that follows this manoeuvre, up to the next one.
  final double distanceMeters;
}

/// Where the user is along a route: the part still ahead (for drawing, so the
/// line shrinks behind them as in Google Maps) and how far is left.
class RouteProgress {
  const RouteProgress({
    required this.segmentIndex,
    required this.snapped,
    required this.remainingPath,
    required this.remainingMeters,
  });

  /// Index of the path segment the user is on (path[i] to path[i + 1]).
  final int segmentIndex;

  /// The user's position moved onto the route line.
  final LatLng snapped;

  /// From [snapped] to the end of the route.
  final List<LatLng> remainingPath;
  final double remainingMeters;
}

/// Compass bearing from [from] to [to], 0–360° clockwise from north.
double bearingBetween(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLng = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

class RouteDirections {
  const RouteDirections({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
    this.path = const [],
    this.driving = false,
  });

  final double distanceMeters;
  final double durationSeconds;
  final List<DirectionStep> steps;

  /// A road route for a vehicle rather than a walking route. Guidance looks
  /// further ahead when driving.
  final bool driving;

  /// The user's progress along [path]. Searches from [fromSegment] onward
  /// (the last known segment, so a route that doubles back can't jump the
  /// progress backward or far ahead), a limited way, and falls back to the
  /// whole line. Null without a line.
  RouteProgress? progressAt(LatLng point, {int fromSegment = 0}) {
    if (path.length < 2) return null;
    const metersPerDegLat = 111320.0;
    final metersPerDegLng =
        metersPerDegLat * math.cos(point.latitude * math.pi / 180);
    double x(LatLng p) => (p.longitude - point.longitude) * metersPerDegLng;
    double y(LatLng p) => (p.latitude - point.latitude) * metersPerDegLat;

    ({int index, double t, double d}) nearestIn(int start, int end) {
      var best = (index: start, t: 0.0, d: double.infinity);
      for (var i = start; i < end; i++) {
        final ax = x(path[i]), ay = y(path[i]);
        final bx = x(path[i + 1]), by = y(path[i + 1]);
        final dx = bx - ax, dy = by - ay;
        final len2 = dx * dx + dy * dy;
        final t = len2 == 0
            ? 0.0
            : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
        final cx = ax + t * dx, cy = ay + t * dy;
        final d = math.sqrt(cx * cx + cy * cy);
        if (d < best.d) best = (index: i, t: t, d: d);
      }
      return best;
    }

    final start = fromSegment.clamp(0, path.length - 2);
    var hit = nearestIn(start, math.min(path.length - 1, start + 40));
    // Lost the thread (big jump, re-snap after a detour): search everything.
    if (hit.d > 80) hit = nearestIn(0, path.length - 1);

    final a = path[hit.index], b = path[hit.index + 1];
    final snapped = LatLng(
      a.latitude + (b.latitude - a.latitude) * hit.t,
      a.longitude + (b.longitude - a.longitude) * hit.t,
    );
    const distance = Distance();
    final remainingPath = [snapped, ...path.skip(hit.index + 1)];
    var remaining = 0.0;
    for (var i = 0; i < remainingPath.length - 1; i++) {
      remaining += distance(remainingPath[i], remainingPath[i + 1]);
    }
    return RouteProgress(
      segmentIndex: hit.index,
      snapped: snapped,
      remainingPath: remainingPath,
      remainingMeters: remaining,
    );
  }

  /// The full route line, for drawing it and for telling whether the user
  /// has wandered off it.
  final List<LatLng> path;

  /// Shortest distance in metres from [point] to the route line, or null if
  /// there's no line. Uses a flat-earth approximation, which is accurate to
  /// well under a metre over the few hundred metres that matter here.
  double? distanceFromPath(LatLng point) {
    if (path.length < 2) return null;
    const metersPerDegLat = 111320.0;
    final metersPerDegLng =
        metersPerDegLat * math.cos(point.latitude * math.pi / 180);

    // Work in metres relative to [point], which sits at the origin.
    double x(LatLng p) => (p.longitude - point.longitude) * metersPerDegLng;
    double y(LatLng p) => (p.latitude - point.latitude) * metersPerDegLat;

    var best = double.infinity;
    for (var i = 0; i < path.length - 1; i++) {
      final ax = x(path[i]), ay = y(path[i]);
      final bx = x(path[i + 1]), by = y(path[i + 1]);
      final dx = bx - ax, dy = by - ay;
      final lengthSquared = dx * dx + dy * dy;
      // Closest point on segment AB to the origin.
      final t = lengthSquared == 0
          ? 0.0
          : (-(ax * dx + ay * dy) / lengthSquared).clamp(0.0, 1.0);
      final cx = ax + t * dx, cy = ay + t * dy;
      final d = math.sqrt(cx * cx + cy * cy);
      if (d < best) best = d;
    }
    return best;
  }

  /// Average speed along the route, used to estimate time remaining.
  double get metersPerSecond =>
      durationSeconds > 0 ? distanceMeters / durationSeconds : 1.4;
}
