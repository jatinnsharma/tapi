import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:real_world_exploration/features/heatmap/application/heatmap_service.dart';
import 'package:real_world_exploration/features/heatmap/domain/route_art.dart';
import 'package:real_world_exploration/features/heatmap/presentation/heatmap_screen.dart';
import 'package:real_world_exploration/features/heatmap/presentation/poster_screen.dart';

void main() {
  group('thinRoute', () {
    test('short routes are kept whole', () {
      final route = [const LatLng(1, 1), const LatLng(2, 2)];
      expect(thinRoute(route), same(route));
    });

    test('long routes keep the ends and at most the limit', () {
      final route = [for (var i = 0; i < 1000; i++) LatLng(i / 1000, 0)];
      final thin = thinRoute(route, max: 50);
      expect(thin, hasLength(50));
      expect(thin.first, route.first);
      expect(thin.last, route.last);
    });
  });

  group('projectRoutes', () {
    const size = Size(200, 200);

    test('north is up and east is right', () {
      final out = projectRoutes(
        [
          [const LatLng(10, 10), const LatLng(10.01, 10.01)],
        ],
        size,
        padding: 0,
      );
      final start = out.single.first, end = out.single.last;
      expect(end.dx, greaterThan(start.dx)); // East is right.
      expect(end.dy, lessThan(start.dy)); // North is up.
    });

    test('fits inside the padding and keeps the shape', () {
      // 0.02° east-west by 0.01° north-south at the equator: twice as wide.
      final out = projectRoutes(
        [
          [const LatLng(0, 0), const LatLng(0.01, 0.02)],
        ],
        size,
        padding: 10,
      );
      final xs = out.single.map((o) => o.dx);
      final ys = out.single.map((o) => o.dy);
      for (final x in xs) {
        expect(x, inInclusiveRange(10, 190));
      }
      final w = xs.reduce((a, b) => (a - b).abs());
      final h = ys.reduce((a, b) => (a - b).abs());
      expect(w / h, closeTo(2, 0.01));
      expect(w, closeTo(180, 0.01)); // Width fills the box.
    });

    test('a single spot sits in the middle; nothing gives nothing', () {
      final out = projectRoutes([
        [const LatLng(5, 5), const LatLng(5, 5)],
      ], size);
      expect(out.single.first, const Offset(100, 100));
      expect(projectRoutes(const [], size), isEmpty);
    });
  });

  const footprint = ExplorationFootprint(
    routes: [
      [LatLng(25.30, 83.00), LatLng(25.31, 83.01)],
    ],
    trips: 3,
    trekKm: 12.34,
    cities: 2,
  );

  testWidgets('poster shows the name and totals; palettes switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PosterScreen(footprint: footprint)),
      ),
    );
    expect(find.text('EXPLORER'), findsOneWidget);
    expect(find.text('12.3'), findsOneWidget);
    expect(find.text('KM WALKED'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('Parchment'));
    await tester.pump();
    final poster = tester.widget<Poster>(find.byType(Poster));
    expect(poster.palette.name, 'Parchment');
  });

  testWidgets('heatmap with no routes says so', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          explorationFootprintProvider.overrideWith(
            (ref) async => const ExplorationFootprint(
              routes: [],
              trips: 0,
              trekKm: 0,
              cities: 0,
            ),
          ),
        ],
        child: const MaterialApp(home: HeatmapScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No routes yet'), findsOneWidget);
  });
}
