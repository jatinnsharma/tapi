import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../locations/data/location_repository.dart';
import '../../locations/domain/location.dart';

/// Implements the "fog of exploration" mechanic: locations are hidden until
/// the user has either physically come close enough to reveal them
/// permanently, or are currently near enough to preview them faintly.
class FogService {
  FogService(this._repository);

  final LocationRepository _repository;
  static const Distance _distanceCalculator = Distance();

  /// Within this radius a location is permanently discovered.
  static const double revealRadiusMeters = 250;

  /// Within this (larger) radius an undiscovered location is still shown,
  /// faintly, as a "nearby" hint — matching the spec's 👀 Nearby state.
  static const double nearbyPreviewRadiusMeters = 1000;

  /// Checks [locations] against [position] and permanently reveals any
  /// that are within [revealRadiusMeters]. Returns the updated list.
  Future<List<ExploreLocation>> processPosition(
    LatLng position,
    List<ExploreLocation> locations,
  ) async {
    final updated = <ExploreLocation>[];
    for (final location in locations) {
      if (location.isDiscovered) {
        updated.add(location);
        continue;
      }
      final distance = _distanceCalculator(
        position,
        LatLng(location.latitude, location.longitude),
      );
      if (distance <= revealRadiusMeters) {
        await _repository.markDiscovered(location.id);
        updated.add(location.copyWith(discoveredAt: DateTime.now()));
      } else {
        updated.add(location);
      }
    }
    return updated;
  }

  /// Locations visible on the map right now: always the discovered ones,
  /// plus any undiscovered ones within the nearby preview radius — unless
  /// [showAll] is set (the "view full map" planning toggle from the spec).
  List<ExploreLocation> visibleLocations(
    List<ExploreLocation> locations,
    LatLng position, {
    bool showAll = false,
  }) {
    if (showAll) return locations;
    return locations.where((location) {
      if (location.isDiscovered) return true;
      final distance = _distanceCalculator(
        position,
        LatLng(location.latitude, location.longitude),
      );
      return distance <= nearbyPreviewRadiusMeters;
    }).toList();
  }
}

final fogServiceProvider = Provider<FogService>((ref) {
  return FogService(ref.watch(locationRepositoryProvider));
});
