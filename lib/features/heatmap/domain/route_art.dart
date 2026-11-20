import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

/// Most points kept per route when drawing: enough for a smooth line,
/// few enough to draw years of trips at once.
const maxPointsPerRoute = 400;

/// [route] thinned to at most [max] points, keeping the first and last.
List<LatLng> thinRoute(List<LatLng> route, {int max = maxPointsPerRoute}) {
  if (route.length <= max) return route;
  final step = (route.length - 1) / (max - 1);
  return [for (var i = 0; i < max; i++) route[(i * step).round()]];
}

/// Fits every route into [size] (minus [padding] on each side), keeping
/// their shape: one degree of longitude is drawn as wide as it really is at
/// that latitude. A single point, or routes in one spot, sit in the middle.
List<List<Offset>> projectRoutes(
  List<List<LatLng>> routes,
  Size size, {
  double padding = 24,
}) {
  final points = [for (final r in routes) ...r];
  if (points.isEmpty) return const [];

  var minLat = points.first.latitude, maxLat = minLat;
  var minLng = points.first.longitude, maxLng = minLng;
  for (final p in points) {
    minLat = math.min(minLat, p.latitude);
    maxLat = math.max(maxLat, p.latitude);
    minLng = math.min(minLng, p.longitude);
    maxLng = math.max(maxLng, p.longitude);
  }

  final midLat = (minLat + maxLat) / 2 * math.pi / 180;
  final xScale = math.cos(midLat); // Degrees of longitude shrink northwards.
  final spanX = (maxLng - minLng) * xScale;
  final spanY = maxLat - minLat;

  final width = math.max(0.0, size.width - 2 * padding);
  final height = math.max(0.0, size.height - 2 * padding);
  final span = math.max(spanX, spanY);
  final scale = span == 0
      ? 0.0
      : math.min(
          spanX == 0 ? double.infinity : width / spanX,
          spanY == 0 ? double.infinity : height / spanY,
        );

  // Centre the drawing in the box.
  final offsetX = padding + (width - spanX * scale) / 2;
  final offsetY = padding + (height - spanY * scale) / 2;

  return [
    for (final route in routes)
      [
        for (final p in route)
          Offset(
            offsetX + (p.longitude - minLng) * xScale * scale,
            // North at the top.
            offsetY + (maxLat - p.latitude) * scale,
          ),
      ],
  ];
}

/// Colours of a poster.
class PosterPalette {
  const PosterPalette(this.name, this.background, this.route, this.text);

  final String name;
  final Color background;
  final Color route;
  final Color text;
}

const posterPalettes = [
  PosterPalette(
    'Midnight',
    Color(0xFF0B1220),
    Color(0xFF5EEAD4),
    Color(0xFFE2E8F0),
  ),
  PosterPalette(
    'Amber',
    Color(0xFF1A1206),
    Color(0xFFF5A623),
    Color(0xFFFDE7C2),
  ),
  PosterPalette(
    'Parchment',
    Color(0xFFF3E9D2),
    Color(0xFF8E2C2C),
    Color(0xFF3B2A1A),
  ),
  PosterPalette(
    'Forest',
    Color(0xFF0F3D2B),
    Color(0xFFC4E4CF),
    Color(0xFFF7FBF5),
  ),
];
