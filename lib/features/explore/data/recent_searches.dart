import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/search_result.dart';
import 'city_repository.dart';

final recentSearchesProvider = Provider<RecentSearches>((ref) {
  return RecentSearches(ref.watch(cityRepositoryProvider));
});

/// The places and cities the user last opened from search, newest first, on
/// this phone.
class RecentSearches {
  RecentSearches(this._cities);

  final CityRepository _cities;

  static const _key = 'recent_searches_v1';
  static const maxItems = 8;

  Future<List<SearchResult>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final results = <SearchResult>[];
      for (final raw in prefs.getStringList(_key) ?? const <String>[]) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final cityId = json['cityId'] as String?;
        final city = cityId == null ? null : await _cities.getCityById(cityId);
        results.add(SearchResult.fromJson(json, city: city));
      }
      return results;
    } catch (_) {
      return const []; // Unreadable history: start fresh.
    }
  }

  Future<List<SearchResult>> add(SearchResult result) async {
    final current = await load();
    final updated = [
      result,
      for (final r in current)
        if (!_same(r, result)) r,
    ].take(maxItems).toList();
    await _save(updated);
    return updated;
  }

  Future<List<SearchResult>> remove(SearchResult result) async {
    final updated = [
      for (final r in await load())
        if (!_same(r, result)) r,
    ];
    await _save(updated);
    return updated;
  }

  Future<void> clear() => _save(const []);

  Future<void> _save(List<SearchResult> results) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, [
        for (final r in results) jsonEncode(r.toJson()),
      ]);
    } catch (_) {}
  }

  static bool _same(SearchResult a, SearchResult b) =>
      (a.city != null && a.city?.id == b.city?.id) ||
      (a.placeId != null && a.placeId == b.placeId) ||
      (a.title == b.title &&
          (a.location.latitude - b.location.latitude).abs() < 0.001 &&
          (a.location.longitude - b.location.longitude).abs() < 0.001);
}
