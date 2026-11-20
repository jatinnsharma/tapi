import 'package:latlong2/latlong.dart';

import '../../explore/domain/city.dart';
import '../../tracking/data/adventure_repository.dart';

/// A visit counts toward a city's stamp when it is this close to the city.
const stampCityRadiusKm = 40.0;

/// A city's passport stamp: earned the first time a counted trip reached a
/// place in or near it.
class PassportStamp {
  const PassportStamp({
    required this.city,
    required this.serial,
    required this.earnedAt,
    required this.placeNames,
  });

  final City city;

  /// 1 for the first city stamped, 2 for the second, and so on.
  final int serial;

  /// When the first place there was reached.
  final DateTime earnedAt;

  /// Different places reached there, first first.
  final List<String> placeNames;

  /// "No. 003".
  String get serialLabel => 'No. ${serial.toString().padLeft(3, '0')}';
}

/// One stamp per city with a counted visit within [stampCityRadiusKm] of it,
/// in the order they were earned. Each visit goes to its nearest city; a
/// visit far from every city in the catalog earns nothing.
List<PassportStamp> buildStamps(List<PlaceVisit> visits, List<City> cities) {
  if (cities.isEmpty) return const [];
  const distance = Distance();
  final byCity = <String, ({City city, DateTime first, List<String> names})>{};

  final ordered = [...visits]
    ..sort((a, b) => a.reachedAt.compareTo(b.reachedAt));
  for (final visit in ordered) {
    final at = LatLng(visit.latitude, visit.longitude);
    City? nearest;
    var best = double.infinity;
    for (final city in cities) {
      final km = distance(at, city.location) / 1000;
      if (km < best) {
        best = km;
        nearest = city;
      }
    }
    if (nearest == null || best > stampCityRadiusKm) continue;

    final entry = byCity[nearest.id];
    if (entry == null) {
      byCity[nearest.id] = (
        city: nearest,
        first: visit.reachedAt,
        names: [visit.name],
      );
    } else if (!entry.names.contains(visit.name)) {
      entry.names.add(visit.name);
    }
  }

  final entries = byCity.values.toList()
    ..sort((a, b) => a.first.compareTo(b.first));
  return [
    for (var i = 0; i < entries.length; i++)
      PassportStamp(
        city: entries[i].city,
        serial: i + 1,
        earnedAt: entries[i].first,
        placeNames: List.unmodifiable(entries[i].names),
      ),
  ];
}
