import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/utils/polyline_codec.dart';
import 'package:real_world_exploration/features/social/domain/footprint.dart';
import 'package:real_world_exploration/features/tracking/domain/directions.dart';

RouteDirections _route(List<LatLng> path, {double duration = 600}) =>
    RouteDirections(
      distanceMeters: 1000,
      durationSeconds: duration,
      steps: const [
        DirectionStep(
          instruction: 'Start walking',
          icon: Icons.directions_walk_rounded,
          location: LatLng(30.7333, 76.7794),
          distanceMeters: 1000,
        ),
      ],
      path: path,
    );

void main() {
  group('RouteDirections.distanceFromPath (drives automatic re-routing)', () {
    // A straight east-west route along latitude 30.7333.
    const a = LatLng(30.7333, 76.7700);
    const b = LatLng(30.7333, 76.7900);

    test('is ~0 for a point on the line', () {
      final d = _route([a, b]).distanceFromPath(const LatLng(30.7333, 76.78));
      expect(d, closeTo(0, 0.5));
    });

    test('measures straight across to the line, not to its ends', () {
      // 0.001 degrees of latitude ≈ 111.3 m north of the middle of the line.
      final d = _route([a, b]).distanceFromPath(const LatLng(30.7343, 76.7800));
      expect(d, closeTo(111.3, 1.5));
    });

    test('measures to the nearest end beyond the line', () {
      // 0.001 degrees of longitude east of the end ≈ 95.7 m at this latitude.
      final d = _route([a, b]).distanceFromPath(const LatLng(30.7333, 76.7910));
      expect(d, closeTo(95.7, 1.5));
    });

    test('is null without a route line', () {
      expect(
        _route(const []).distanceFromPath(const LatLng(30.7, 76.7)),
        isNull,
      );
      expect(_route([a]).distanceFromPath(const LatLng(30.7, 76.7)), isNull);
    });
  });

  group('RouteDirections.metersPerSecond', () {
    test('is the route average', () {
      expect(_route([], duration: 500).metersPerSecond, 2.0);
    });

    test('falls back to walking pace for a zero duration', () {
      expect(_route([], duration: 0).metersPerSecond, 1.4);
    });
  });

  group('Destination', () {
    const place = Destination(
      id: 'wiki-1',
      name: 'Sukhna Lake',
      latitude: 30.742,
      longitude: 76.818,
      xpReward: 60,
    );

    test('becomes a 40 m arrival checkpoint carrying its XP', () {
      final checkpoint = place.toCheckpoint();
      expect(checkpoint.id, '${Destination.checkpointIdPrefix}wiki-1');
      expect(checkpoint.radiusMeters, 40);
      expect(checkpoint.xpReward, 60);
      expect(checkpoint.name, 'Sukhna Lake');
    });

    test('compares by place, so the route is fetched once per place', () {
      const same = Destination(
        id: 'wiki-1',
        name: 'Renamed',
        latitude: 30.742,
        longitude: 76.818,
      );
      expect(place, equals(same));
      expect(place.hashCode, same.hashCode);
    });
  });

  group('PolylineCodec (route lines from the router and footprints)', () {
    test('round-trips coordinates at 5 decimal places', () {
      const points = [
        LatLng(30.73331, 76.77942),
        LatLng(30.74201, 76.81805),
        LatLng(30.70003, 76.70001),
      ];
      final decoded = PolylineCodec.decode(PolylineCodec.encode(points));
      expect(decoded, hasLength(points.length));
      for (var i = 0; i < points.length; i++) {
        expect(decoded[i].latitude, closeTo(points[i].latitude, 1e-5));
        expect(decoded[i].longitude, closeTo(points[i].longitude, 1e-5));
      }
    });

    test('decodes a real route line from the walking router', () {
      // The `geometry` of a walking route in Chandigarh, exactly as returned
      // by routing.openstreetmap.de on 2026-10-11 (overview=full,
      // geometries=polyline).
      const geometry =
          r'yhuzDwixsMJMFKDGLKDO?UAO?ABKNu@C_AEA_@WLYOIL[xB}Bn@|@nB|@dD~AxAp@v@n@|@`CRt@rGgF^[aAsBaCyFc@{AGSa@iBUsAIe@LiB?w@Bg@L{@HaAPa@ZQDG';
      final decoded = PolylineCodec.decode(geometry);
      expect(decoded, hasLength(42));
      expect(decoded.first.latitude, closeTo(30.75229, 1e-5));
      expect(decoded.first.longitude, closeTo(76.80684, 1e-5));
      expect(decoded.last.latitude, closeTo(30.74826, 1e-5));
      expect(decoded.last.longitude, closeTo(76.81334, 1e-5));
    });
  });

  group('FootprintVisibility', () {
    test('defaults to private for unknown or missing values', () {
      expect(FootprintVisibility.fromName(null), FootprintVisibility.private);
      expect(
        FootprintVisibility.fromName('everyone'),
        FootprintVisibility.private,
      );
      expect(
        FootprintVisibility.fromName('friends'),
        FootprintVisibility.friends,
      );
    });
  });

  group('navigation progress', () {
    // An L-shaped route: 500 m east, then 500 m north.
    final route = _route(const [
      LatLng(30.7400, 76.8100),
      LatLng(30.7400, 76.81522),
      LatLng(30.74449, 76.81522),
    ]);

    test('snaps to the line and measures what is left', () {
      // A little off the first leg, about 200 m along it.
      final p = route.progressAt(const LatLng(30.74005, 76.81209))!;
      expect(p.segmentIndex, 0);
      expect(p.snapped.latitude, closeTo(30.7400, 1e-6));
      expect(p.remainingMeters, closeTo(800, 15));
      expect(p.remainingPath.first, p.snapped);
      expect(p.remainingPath.last, route.path.last);
    });

    test('moves on to the next leg after the corner', () {
      final p = route.progressAt(
        const LatLng(30.7420, 76.81525),
        fromSegment: 0,
      )!;
      expect(p.segmentIndex, 1);
      expect(p.remainingMeters, closeTo(277, 15));
    });

    test('re-finds the route after a long detour', () {
      // Searching from the last segment still finds the first one.
      final p = route.progressAt(
        const LatLng(30.7401, 76.8110),
        fromSegment: 1,
      )!;
      expect(p.segmentIndex, 0);
    });

    test('no line, no progress', () {
      expect(_route(const []).progressAt(const LatLng(30.74, 76.81)), isNull);
    });
  });

  group('bearingBetween', () {
    test('points the right way', () {
      const here = LatLng(30.74, 76.81);
      expect(bearingBetween(here, const LatLng(30.75, 76.81)), closeTo(0, 0.5));
      expect(
        bearingBetween(here, const LatLng(30.74, 76.82)),
        closeTo(90, 0.5),
      );
      expect(
        bearingBetween(here, const LatLng(30.73, 76.81)),
        closeTo(180, 0.5),
      );
      expect(
        bearingBetween(here, const LatLng(30.74, 76.80)),
        closeTo(270, 0.5),
      );
    });
  });
}
