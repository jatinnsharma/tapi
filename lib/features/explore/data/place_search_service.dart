import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../locations/data/location_repository.dart';
import '../../locations/domain/location.dart';
import '../domain/search_ranking.dart';
import '../domain/search_result.dart';
import 'city_repository.dart';

final placeSearchServiceProvider = Provider<PlaceSearchService>((ref) {
  return PlaceSearchService(
    dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
    cityRepository: ref.watch(cityRepositoryProvider),
    savedPlaces: () => ref.read(locationRepositoryProvider).getAll(),
  );
});

/// The online search couldn't be reached (offline, server down).
class SearchUnavailableException implements Exception {
  const SearchUnavailableException();
}

/// Search across India:
///  * on the phone, instantly: the city catalog (typos and old names like
///    "Banaras" allowed) and the places the app has already found;
///  * online, as you type: OpenStreetMap places via Photon, which is made for
///    search-as-you-type (Nominatim's usage policy forbids that), limited to
///    India and biased toward the user;
///  * Nominatim only for an explicit search (the keyboard's search key) when
///    Photon has nothing.
class PlaceSearchService {
  PlaceSearchService({
    required this.dio,
    required this.cityRepository,
    this.savedPlaces,
  });

  final Dio dio;
  final CityRepository cityRepository;

  /// The app's own places (from Wikipedia/OpenStreetMap fetches).
  final Future<List<ExploreLocation>> Function()? savedPlaces;

  static const _userAgent = 'com.example.real_world_exploration';

  /// Nominatim's usage policy allows one request a second.
  static Future<void> _geocodeQueue = Future.value();
  static DateTime? _lastGeocode;

  /// Finds one named place (a landmark from an itinerary) near [near]. Returns
  /// null when nothing within [withinKm] matches or the lookup fails.
  Future<SearchResult?> geocodePlace(
    String name, {
    required LatLng near,
    String? cityName,
    double withinKm = 40,
  }) {
    final turn = _geocodeQueue.then((_) async {
      final last = _lastGeocode;
      if (last != null) {
        final wait =
            const Duration(milliseconds: 1100) -
            DateTime.now().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _lastGeocode = DateTime.now();
      return _geocodeNow(
        name,
        near: near,
        cityName: cityName,
        withinKm: withinKm,
      );
    });
    _geocodeQueue = turn.then((_) {}, onError: (_) {});
    return turn;
  }

  Future<SearchResult?> _geocodeNow(
    String name, {
    required LatLng near,
    String? cityName,
    required double withinKm,
  }) async {
    // A box around the city keeps "Assi Ghat" in Varanasi rather than the
    // first match in India.
    const degPerKm = 1 / 111.0;
    final d = withinKm * degPerKm;
    try {
      final response = await dio.get<List<dynamic>>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': cityName == null ? name : '$name, $cityName',
          'format': 'jsonv2',
          'countrycodes': 'in',
          'limit': 3,
          'viewbox':
              '${near.longitude - d},${near.latitude + d},${near.longitude + d},${near.latitude - d}',
          'bounded': 1,
          'accept-language': 'en',
        },
        options: Options(
          headers: {'User-Agent': _userAgent},
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 5),
        ),
      );
      const distance = Distance();
      for (final raw in response.data ?? const []) {
        if (raw is! Map<String, dynamic>) continue;
        final lat = double.tryParse('${raw['lat']}');
        final lon = double.tryParse('${raw['lon']}');
        if (lat == null || lon == null) continue;
        final point = LatLng(lat, lon);
        if (distance(near, point) / 1000 > withinKm) continue;
        return SearchResult(
          title: raw['name'] as String? ?? name,
          subtitle: raw['display_name'] as String? ?? '',
          location: point,
          type: SearchResultType.place,
          placeId: 'osm-${raw['place_id']}',
        );
      }
    } catch (_) {}
    return null;
  }

  /// India, for limiting online results.
  static const _indiaBbox = '68.1,6.5,97.5,35.7';
  static const _indiaCenter = LatLng(22.5, 79.0);

  /// Online answers by query and rough area, so retyping or going back to a
  /// query doesn't search again.
  static final _onlineCache =
      <String, List<SearchResult>>{}; // In insertion order.
  static const _onlineCacheSize = 40;

  /// Phone-only results, instantly: matching catalog cities, then saved
  /// places, best match first.
  Future<List<SearchResult>> searchLocal(
    String query, {
    LatLng? near,
    int limit = 12,
  }) async {
    if (query.trim().isEmpty) return const [];

    final cities = (await cityRepository.searchCitiesScored(query))
        .take(6)
        .map(
          (e) => (
            score: e.score,
            result: SearchResult(
              title: e.city.name,
              subtitle: '${e.city.state} · ${_prettyCategory(e.city.category)}',
              location: e.city.location,
              type: SearchResultType.city,
              city: e.city,
              kind: 'City',
              state: e.city.state,
            ).withDistanceFrom(near),
          ),
        )
        .toList();

    final places = <({int score, SearchResult result})>[];
    final loader = savedPlaces;
    if (loader != null) {
      try {
        for (final p in await loader()) {
          final score = nameScore(query, p.name);
          if (score < 55) continue;
          places.add((
            score: score,
            result: SearchResult(
              title: p.name,
              subtitle: [
                p.category.label,
                if (p.city.isNotEmpty) p.city,
              ].join(' · '),
              location: LatLng(p.latitude, p.longitude),
              type: SearchResultType.place,
              placeId: p.id,
              kind: p.category.label,
              category: p.category,
              savedPlace: p,
              locality: p.city,
              state: p.region,
            ).withDistanceFrom(near),
          ));
        }
      } catch (_) {}
    }
    places.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return (a.result.distanceKm ?? 0).compareTo(b.result.distanceKm ?? 0);
    });

    // Strong city matches first, then places, then weaker cities (a state or
    // category match shouldn't bury the place you named).
    return [
      for (final c in cities)
        if (c.score >= 80) c.result,
      for (final p in places.take(6)) p.result,
      for (final c in cities)
        if (c.score < 80) c.result,
    ].take(limit).toList();
  }

  /// Places across India from OpenStreetMap (Photon), nearest-biased.
  /// Throws [SearchUnavailableException] when it can't be reached.
  Future<List<SearchResult>> searchOnline(
    String query, {
    LatLng? near,
    int limit = 10,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final bias = near ?? _indiaCenter;
    final key =
        '${normalizeForSearch(q)}@${bias.latitude.toStringAsFixed(1)},${bias.longitude.toStringAsFixed(1)}';
    final cached = _onlineCache.remove(key);
    if (cached != null) {
      _onlineCache[key] = cached; // Most recent last.
      return [for (final r in cached) r.withDistanceFrom(near)];
    }

    final Response<Map<String, dynamic>> response;
    try {
      response = await dio.get<Map<String, dynamic>>(
        'https://photon.komoot.io/api/',
        queryParameters: {
          'q': q,
          'limit': limit + 5, // Some get filtered out below.
          'lang': 'en',
          'lat': bias.latitude,
          'lon': bias.longitude,
          'bbox': _indiaBbox,
        },
        options: Options(
          headers: {'User-Agent': _userAgent},
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
    } on DioException {
      throw const SearchUnavailableException();
    }

    final results = parsePhoton(response.data, near: near).take(limit).toList();
    _onlineCache[key] = results;
    while (_onlineCache.length > _onlineCacheSize) {
      _onlineCache.remove(_onlineCache.keys.first);
    }
    return results;
  }

  /// Photon's GeoJSON answer as results, India only, without nameless
  /// entries or duplicates.
  static List<SearchResult> parsePhoton(
    Map<String, dynamic>? data, {
    LatLng? near,
  }) {
    final results = <SearchResult>[];
    final seen = <String>{};
    for (final feature in (data?['features'] as List<dynamic>?) ?? const []) {
      if (feature is! Map<String, dynamic>) continue;
      final props = feature['properties'] as Map<String, dynamic>? ?? const {};
      final coords =
          (feature['geometry'] as Map<String, dynamic>?)?['coordinates']
              as List<dynamic>?;
      final name = (props['name'] as String?)?.trim() ?? '';
      if (name.isEmpty || coords == null || coords.length < 2) continue;
      if ((props['countrycode'] as String?)?.toUpperCase() != 'IN') continue;

      final locality =
          (props['city'] ?? props['county'] ?? props['district']) as String?;
      final state = props['state'] as String?;
      final dedupeKey = '${normalizeForSearch(name)}|${locality ?? ''}';
      if (!seen.add(dedupeKey)) continue;

      final (kind, category) = describeOsmPlace(
        props['osm_key'] as String?,
        props['osm_value'] as String?,
      );
      final where = [
        if (locality != null && locality != name) locality,
        if (state != null && state != name) state,
      ].join(', ');
      results.add(
        SearchResult(
          title: name,
          subtitle: [kind, if (where.isNotEmpty) where].join(' · '),
          location: LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          ),
          type: SearchResultType.place,
          placeId: 'osm-${props['osm_type'] ?? ''}${props['osm_id'] ?? name}',
          kind: kind,
          category: category,
          locality: locality,
          state: state,
        ).withDistanceFrom(near),
      );
    }
    return results;
  }

  /// One-off search with Nominatim, for the keyboard's search key when
  /// Photon found nothing. Not for search-as-you-type (their policy).
  Future<List<SearchResult>> searchNominatim(
    String query, {
    LatLng? near,
  }) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    final Response<List<dynamic>> response;
    try {
      response = await dio.get<List<dynamic>>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': q,
          'format': 'jsonv2',
          'countrycodes': 'in',
          'limit': 8,
          'addressdetails': 1,
          'accept-language': 'en',
        },
        options: Options(
          headers: {'User-Agent': _userAgent},
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 5),
        ),
      );
    } on DioException {
      throw const SearchUnavailableException();
    }
    final results = <SearchResult>[];
    for (final raw in response.data ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      final lat = double.tryParse('${raw['lat']}');
      final lon = double.tryParse('${raw['lon']}');
      final name = (raw['name'] as String?)?.trim();
      if (lat == null || lon == null || name == null || name.isEmpty) {
        continue;
      }
      final address = raw['address'] as Map<String, dynamic>? ?? const {};
      final locality =
          (address['city'] ?? address['town'] ?? address['county']) as String?;
      final state = address['state'] as String?;
      final (kind, category) = describeOsmPlace(
        raw['category'] as String?,
        raw['type'] as String?,
      );
      final where = [?locality, ?state].join(', ');
      final osmType = '${raw['osm_type'] ?? ''}';
      results.add(
        SearchResult(
          title: name,
          subtitle: [kind, if (where.isNotEmpty) where].join(' · '),
          location: LatLng(lat, lon),
          type: SearchResultType.place,
          placeId:
              'osm-${osmType.isEmpty ? '' : osmType[0].toUpperCase()}${raw['osm_id'] ?? raw['place_id']}',
          kind: kind,
          category: category,
          locality: locality,
          state: state,
        ).withDistanceFrom(near),
      );
    }
    return results;
  }

  /// Phone and online results together, for callers that want one list
  /// (the trip planner). The online part is skipped when unreachable.
  Future<List<SearchResult>> search(String query, {LatLng? near}) async {
    if (query.trim().isEmpty) return const [];
    final local = await searchLocal(query, near: near);
    List<SearchResult> online;
    try {
      online = await searchOnline(query, near: near);
    } on SearchUnavailableException {
      online = const [];
    }
    return mergeResults(local, online);
  }

  /// [local] followed by the [online] results that aren't already there: an
  /// online town that is a catalog city, or the same place under the same
  /// name nearby, is left out.
  static List<SearchResult> mergeResults(
    List<SearchResult> local,
    List<SearchResult> online,
  ) {
    const distance = Distance();
    bool duplicate(SearchResult o) => local.any((l) {
      final km = distance(l.location, o.location) / 1000;
      if (l.isCity) {
        // The town itself ("Panaji" for "Panaji (Goa)"), not every place
        // whose name starts with the city's ("Varanasi Junction").
        return km < 25 && nameScore(o.title, l.title) >= 80;
      }
      final sameName =
          nameScore(o.title, l.title) >= 80 ||
          nameScore(l.title, o.title) >= 80;
      return sameName && km < 1;
    });
    return [...local, ...online.where((o) => !duplicate(o))];
  }

  static String _prettyCategory(String category) {
    final words = category.replaceAll('_', ' ');
    return words.isEmpty ? '' : words[0].toUpperCase() + words.substring(1);
  }
}

/// A readable kind ("Temple", "Fort", "Railway station") and app category for
/// an OpenStreetMap tag.
(String, LocationCategory) describeOsmPlace(String? key, String? value) {
  String pretty(String? v) {
    final words = (v == null || v.isEmpty ? 'place' : v).replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }

  return switch ((key, value)) {
    ('amenity', 'place_of_worship') => (
      'Place of worship',
      LocationCategory.heritage,
    ),
    ('historic', final v) => (pretty(v), LocationCategory.heritage),
    ('tourism', 'viewpoint') => ('Viewpoint', LocationCategory.viewpoint),
    ('tourism', 'museum') => ('Museum', LocationCategory.heritage),
    ('tourism', 'camp_site') => ('Campsite', LocationCategory.camping),
    ('tourism', 'attraction') => ('Attraction', LocationCategory.photography),
    ('tourism', final v) => (pretty(v), LocationCategory.city),
    ('amenity', 'restaurant' || 'cafe' || 'fast_food' || 'food_court') => (
      pretty(value),
      LocationCategory.food,
    ),
    ('natural', 'peak' || 'volcano' || 'ridge') => (
      pretty(value),
      LocationCategory.mountain,
    ),
    ('natural', 'water') => ('Lake', LocationCategory.lake),
    ('natural', 'beach') => ('Beach', LocationCategory.nature),
    ('waterway', 'waterfall') => ('Waterfall', LocationCategory.waterfall),
    ('natural', final v) => (pretty(v), LocationCategory.nature),
    ('leisure', 'park' || 'garden' || 'nature_reserve') => (
      pretty(value),
      LocationCategory.nature,
    ),
    ('boundary', 'national_park' || 'protected_area') => (
      'National park',
      LocationCategory.nature,
    ),
    ('railway', 'station' || 'halt') => (
      'Railway station',
      LocationCategory.city,
    ),
    ('aeroway', 'aerodrome') => ('Airport', LocationCategory.city),
    ('place', final v) => (pretty(v), LocationCategory.city),
    _ => (pretty(value), LocationCategory.city),
  };
}
