import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/config/service_area.dart';
import '../../../core/database/database_service.dart';
import '../domain/location.dart';
import 'location_seed.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(ref.watch(databaseServiceProvider));
});

class LocationRepository {
  LocationRepository(this._databaseService);

  /// Kinds of place version 1 doesn't show: treks and mountains, cafés,
  /// camping and waterfalls.
  static const hiddenCategories = {
    LocationCategory.trek,
    LocationCategory.mountain,
    LocationCategory.food,
    LocationCategory.camping,
    LocationCategory.waterfall,
  };

  final DatabaseService _databaseService;

  Future<List<ExploreLocation>> getAll() async {
    final db = await _databaseService.database;
    // Built-in places are an optional fallback on first launch if the database
    // is completely empty. If locations are already stored (e.g. from online
    // fetches), we don't force re-seeding.
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM locations'),
        ) ??
        0;
    if (count == 0 && locationSeed.isNotEmpty) {
      await _seed(db);
    }

    // Force cleanup of legacy static locations in case hot-reload bypassed the DB migration
    await db.execute('''
      DELETE FROM locations WHERE id IN (
        'loc-secret-waterfall', 'loc-old-fort-ruins', 'loc-sunrise-peak', 
        'loc-pine-forest-trail', 'loc-city-skyline-view', 'loc-gateway-of-india', 
        'loc-old-clock-tower', 'loc-rock-pool', 'loc-upper-falls-viewpoint', 
        'loc-trail-water-point', 'loc-trail-rest-point', 'loc-riverside-cafe', 
        'loc-amber-fort', 'loc-hawa-mahal', 'loc-nahargarh-viewpoint', 
        'loc-jaipur-bazaar', 'loc-jal-mahal', 'loc-rock-garden', 'loc-sukhna-lake', 
        'loc-rose-garden', 'loc-fateh-burj', 'loc-mohali-stadium', 'loc-nada-sahib', 
        'loc-cactus-garden'
      )
    ''');
    final rows = await db.query('locations');
    // Version 1 is Chandigarh only, and leaves out a few kinds of place.
    // Places outside the area or of a hidden kind (earlier fetches, AI
    // suggestions) are kept in the database but not shown, so changing
    // either rule later brings them back.
    return rows
        .map(ExploreLocation.fromMap)
        .where((l) => ServiceArea.containsCoordinates(l.latitude, l.longitude))
        .where((l) => !hiddenCategories.contains(l.category))
        .toList();
  }

  Future<void> _seed(Database db) async {
    final batch = db.batch();
    for (final location in locationSeed) {
      batch.insert(
        'locations',
        location.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertMany(List<ExploreLocation> locations) async {
    final db = await _databaseService.database;
    final batch = db.batch();
    for (final location in locations) {
      batch.insert(
        'locations',
        location.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ExploreLocation>> getByCategory(LocationCategory category) async {
    final all = await getAll();
    return all.where((location) => location.category == category).toList();
  }

  List<ExploreLocation> sortedByDistance(
    List<ExploreLocation> locations,
    LatLng from,
  ) {
    const distanceCalculator = Distance();
    final sorted = [...locations];
    sorted.sort((a, b) {
      final distanceA = distanceCalculator(
        from,
        LatLng(a.latitude, a.longitude),
      );
      final distanceB = distanceCalculator(
        from,
        LatLng(b.latitude, b.longitude),
      );
      return distanceA.compareTo(distanceB);
    });
    return sorted;
  }

  double distanceFrom(ExploreLocation location, LatLng from) {
    const distanceCalculator = Distance();
    return distanceCalculator(
      from,
      LatLng(location.latitude, location.longitude),
    );
  }

  Future<List<RegionProgress>> getNeighborhoodCompletion() =>
      _completionBy((l) => l.neighborhood);
  Future<List<RegionProgress>> getCityCompletion() =>
      _completionBy((l) => l.city);
  Future<List<RegionProgress>> getDistrictCompletion() =>
      _completionBy((l) => l.district);
  Future<List<RegionProgress>> getRegionCompletion() =>
      _completionBy((l) => l.region);
  Future<List<RegionProgress>> getCountryCompletion() =>
      _completionBy((l) => l.country);

  /// Groups all locations by [keyOf] (city, region, or country — the spec's
  /// §28 hierarchy collapses to the same discovered/total shape at every
  /// level) and computes discovered/total for each group.
  Future<List<RegionProgress>> _completionBy(
    String Function(ExploreLocation) keyOf,
  ) async {
    final all = await getAll();
    final counts = <String, (int discovered, int total)>{};
    for (final location in all) {
      final key = keyOf(location);
      final existing = counts[key] ?? (0, 0);
      counts[key] = (
        existing.$1 + (location.isDiscovered ? 1 : 0),
        existing.$2 + 1,
      );
    }
    return [
      for (final entry in counts.entries)
        RegionProgress(
          name: entry.key,
          discovered: entry.value.$1,
          total: entry.value.$2,
        ),
    ];
  }

  Future<void> markDiscovered(String id) async {
    final db = await _databaseService.database;
    await db.update(
      'locations',
      {'discovered_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND discovered_at IS NULL',
      whereArgs: [id],
    );
  }
}
