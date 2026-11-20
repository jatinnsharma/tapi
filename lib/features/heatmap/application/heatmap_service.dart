import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../passport/application/passport_service.dart';
import '../../tracking/data/adventure_repository.dart';
import '../domain/route_art.dart';

/// Everything the heatmap and the poster draw: the routes of counted trips
/// and the totals printed on the poster.
class ExplorationFootprint {
  const ExplorationFootprint({
    required this.routes,
    required this.trips,
    required this.trekKm,
    required this.cities,
  });

  /// One thinned route per counted trip with a recorded path.
  final List<List<LatLng>> routes;
  final int trips;

  /// On-foot (trek) distance of counted trips; journeys by vehicle excluded.
  final double trekKm;

  /// Cities stamped in the passport.
  final int cities;

  bool get isEmpty => routes.isEmpty;
}

final explorationFootprintProvider =
    FutureProvider.autoDispose<ExplorationFootprint>((ref) async {
      final repository = ref.watch(adventureRepositoryProvider);
      final paths = await repository.getAllCompletedRoutePaths();
      final trips = await repository.getCompletedAdventures();
      final stamps = await ref.watch(passportStampsProvider.future);
      return ExplorationFootprint(
        routes: [
          for (final path in paths)
            if (path.length >= 2)
              thinRoute([
                for (final p in path) LatLng(p.latitude, p.longitude),
              ]),
        ],
        trips: trips.length,
        trekKm: trips.fold<double>(0, (km, t) => km + t.trekMeters / 1000),
        cities: stamps.length,
      );
    });
