import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../domain/city.dart';
import '../domain/search_ranking.dart';

final cityRepositoryProvider = Provider<CityRepository>((ref) {
  return CityRepository();
});

class SelectedCityNotifier extends Notifier<City?> {
  @override
  City? build() => null;

  void select(City? city) => state = city;
  void clear() => state = null;
}

/// The currently selected city to explore, or null for user's live GPS location.
final selectedCityProvider = NotifierProvider<SelectedCityNotifier, City?>(
  SelectedCityNotifier.new,
);

class CityRepository {
  CityRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  List<City>? _cachedCities;
  static const Distance _distance = Distance();

  Future<List<City>> getCities() async {
    if (_cachedCities != null) return _cachedCities!;
    final jsonString = await _bundle.loadString(
      'assets/data/india_cities.json',
    );
    final List<dynamic> list = json.decode(jsonString) as List<dynamic>;
    _cachedCities = list
        .map((e) => City.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return _cachedCities!;
  }

  Future<City?> getCityById(String id) async {
    final cities = await getCities();
    for (final c in cities) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Cities matching [query], best first: by name (typos and old names like
  /// "Banaras" allowed), then state or kind of place. Ties go to the city
  /// nearest [near], when given.
  Future<List<City>> searchCities(String query, {LatLng? near}) async {
    if (query.trim().isEmpty) return getCities();
    final scored = await searchCitiesScored(query);
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0 || near == null) return byScore;
      return _distance(
        near,
        a.city.location,
      ).compareTo(_distance(near, b.city.location));
    });
    return [for (final e in scored) e.city];
  }

  /// Like [searchCities], with each city's match score (0–100).
  Future<List<({City city, int score})>> searchCitiesScored(
    String query,
  ) async {
    final cities = await getCities();
    return [
        for (final c in cities)
          (
            city: c,
            score: cityScore(
              query,
              name: c.name,
              state: c.state,
              category: c.category,
            ),
          ),
      ].where((e) => e.score > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  Future<List<City>> getNearbyCities(
    LatLng from, {
    int limit = 10,
    double? maxDistanceKm,
  }) async {
    final cities = await getCities();
    final withDist = cities.map((c) {
      final km = _distance(from, c.location) / 1000;
      return (city: c, distanceKm: km);
    }).toList();

    withDist.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    var filtered = withDist;
    if (maxDistanceKm != null) {
      filtered = filtered
          .where((item) => item.distanceKm <= maxDistanceKm)
          .toList();
    }

    return filtered.take(limit).map((item) => item.city).toList();
  }

  Future<City?> findNearestCity(LatLng from) async {
    final nearby = await getNearbyCities(from, limit: 1);
    return nearby.isNotEmpty ? nearby.first : null;
  }
}
