import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/service_area.dart';
import '../domain/location.dart';
import 'location_repository.dart';

final nearbyPlacesServiceProvider = Provider<NearbyPlacesService>((ref) {
  return NearbyPlacesService(Dio(), ref.watch(locationRepositoryProvider));
});

/// Finds real places around the user from OpenStreetMap (the public Overpass
/// API, no key needed) and stores them in the local `locations` table, so
/// Home and Map have nearby places without any AI key or hand-made seed data.
///
/// Fetches are cached: places are only re-fetched when the user has moved
/// well away from the last fetch point or the last fetch is a week old.
class NearbyPlacesService {
  NearbyPlacesService(this._dio, this._repository);

  final Dio _dio;
  final LocationRepository _repository;

  /// Public Overpass instances, tried in order until one answers.
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];
  static const _userAgent = 'com.example.real_world_exploration';

  static const _latKey = 'nearby_fetch_lat';
  static const _lngKey = 'nearby_fetch_lng';
  static const _atKey = 'nearby_fetch_at';

  /// How far from the last fetch point the user may roam before we fetch
  /// again, and how old a fetch may get.
  static const _refetchDistanceKm = 10.0;
  static const _maxAge = Duration(days: 7);

  /// Fetches and stores nearby places if the cache is stale (or [force]).
  /// Returns how many places were fetched; throws if every endpoint fails so
  /// callers can decide whether to surface it. A failed fetch isn't cached,
  /// so the next call retries.
  Future<int> ensureFresh(LatLng around, {bool force = false}) async {
    if (!force && !await _isStale(around)) return 0;

    final region = await _reverseGeocode(around);

    // Two sources, both tolerated to fail on their own:
    //  - Wikipedia geosearch: fast and reliable, famous landmarks with photos.
    //  - OpenStreetMap Overpass: richer and finds lesser-known "hidden gems",
    //    but the public servers are often slow or overloaded.
    // Wikipedia is awaited. Overpass gets a short head start, then carries on
    // in the background and saves its results whenever it finishes, so a slow
    // server never keeps the screen waiting.
    final wikiFuture = _fetchWikipedia(around, region);
    final osmFuture = _fetchOverpass(around, region);
    unawaited(
      osmFuture.then((places) => _saveNew(places)).catchError((Object _) => 0),
    );

    var wikiPlaces = <ExploreLocation>[];
    Object? wikiError;
    try {
      wikiPlaces = await wikiFuture;
    } catch (e) {
      wikiError = e;
    }
    var osmPlaces = <ExploreLocation>[];
    Object? osmError;
    try {
      osmPlaces = await osmFuture.timeout(_osmHeadStart);
    } catch (e) {
      osmError = e; // Timed out or failed; a late success is saved above.
    }

    final saved = await _saveNew([...wikiPlaces, ...osmPlaces]);

    // Both sources failing means we learned nothing: report it and don't
    // mark this area as fetched, so the next visit tries again.
    if (wikiError != null && osmError != null && saved == 0) {
      throw StateError('Could not reach the places services: $wikiError');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_latKey, around.latitude);
    await prefs.setDouble(_lngKey, around.longitude);
    await prefs.setInt(_atKey, DateTime.now().millisecondsSinceEpoch);
    await _recordAreaCache(around, region.city);
    return saved;
  }

  /// How long to wait for Overpass before showing what we have.
  static const _osmHeadStart = Duration(seconds: 8);

  static const _areaCacheKey = 'nearby_fetch_areas_v1';

  Future<void> _recordAreaCache(LatLng around, String city) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_areaCacheKey);
    final list = raw != null ? (jsonDecode(raw) as List<dynamic>) : <dynamic>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    // Prune entries older than _maxAge
    final filtered = list.where((item) {
      if (item is! Map) return false;
      final at = item['at'] as int?;
      if (at == null) return false;
      return (now - at) <= _maxAge.inMilliseconds;
    }).toList();

    filtered.add({
      'lat': around.latitude,
      'lng': around.longitude,
      'at': now,
      'city': city,
    });
    await prefs.setString(_areaCacheKey, jsonEncode(filtered));
  }

  /// Stores places that aren't already known: skips any whose name matches a
  /// stored place within 500 m (the same landmark often appears in both
  /// sources). Returns how many were added.
  Future<int> _saveNew(List<ExploreLocation> found) async {
    // Searches reach up to 30 km out; only places inside the service area
    // (India) are kept.
    final candidates = found
        .where((p) => ServiceArea.containsCoordinates(p.latitude, p.longitude))
        .toList();
    if (candidates.isEmpty) return 0;
    final existing = await _repository.getAll();
    const distance = Distance();

    bool known(ExploreLocation place) => existing.any(
      (e) =>
          e.id == place.id ||
          (e.name.toLowerCase() == place.name.toLowerCase() &&
              distance(
                    LatLng(e.latitude, e.longitude),
                    LatLng(place.latitude, place.longitude),
                  ) <
                  500),
    );

    final fresh = <ExploreLocation>[];
    for (final place in candidates) {
      if (known(place)) continue;
      fresh.add(place);
      existing.add(place); // also dedupes within this batch
    }
    if (fresh.isNotEmpty) await _repository.insertMany(fresh);
    return fresh.length;
  }

  Future<bool> _isStale(LatLng around) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_areaCacheKey);
    const distance = Distance();
    final now = DateTime.now().millisecondsSinceEpoch;

    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          if (item is! Map) continue;
          final lat = item['lat'] as num?;
          final lng = item['lng'] as num?;
          final at = item['at'] as int?;
          if (lat == null || lng == null || at == null) continue;
          if ((now - at) > _maxAge.inMilliseconds) continue;

          final movedKm =
              distance(around, LatLng(lat.toDouble(), lng.toDouble())) / 1000;
          if (movedKm <= _refetchDistanceKm) {
            return false; // Found a fresh cached fetch for this area!
          }
        }
      } catch (_) {}
    }

    // Fallback to legacy single-point cache if available
    final lat = prefs.getDouble(_latKey);
    final lng = prefs.getDouble(_lngKey);
    final at = prefs.getInt(_atKey);
    if (lat != null && lng != null && at != null) {
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(at),
      );
      if (age <= _maxAge) {
        final movedKm = distance(around, LatLng(lat, lng)) / 1000;
        if (movedKm <= _refetchDistanceKm) {
          return false;
        }
      }
    }

    return true;
  }

  // -------------------------------------------------------------------------
  // Fetching
  // -------------------------------------------------------------------------

  Future<List<ExploreLocation>> _fetchOverpass(
    LatLng around,
    _Region region,
  ) async {
    final elements = await _queryOverpass(_buildQuery(around));

    final seen = <String>{};
    final places = <ExploreLocation>[];
    for (final element in elements) {
      final place = _toLocation(element, region);
      if (place != null && seen.add(place.id)) places.add(place);
    }
    return places;
  }

  /// One statement per kind of place so that a flood of one kind (cafés in a
  /// city, say) can't crowd out the others. Radii and limits are kept modest:
  /// the public servers reject heavy queries.
  String _buildQuery(LatLng c) {
    String statement(String filter, int radiusMeters, int limit) =>
        'nwr(around:$radiusMeters,${c.latitude},${c.longitude})$filter["name"];'
        'out center $limit;';

    return [
      '[out:json][timeout:20];',
      statement('["tourism"="viewpoint"]', 15000, 30),
      statement('["natural"="spring"]', 15000, 15),
      statement('["natural"="cave_entrance"]', 20000, 10),
      statement('["tourism"="attraction"]', 10000, 20),
      statement('["historic"]', 10000, 30),
      statement('["natural"="water"]["water"="lake"]', 20000, 15),
      statement('["leisure"="nature_reserve"]', 20000, 15),
    ].join();
  }

  // -------------------------------------------------------------------------
  // Wikipedia geosearch
  // -------------------------------------------------------------------------

  /// Landmarks within 10 km (the API's maximum) that have a Wikipedia article,
  /// with the article's photo. Wikipedia lists everything near a point
  /// (schools, hospitals, states...), so only articles whose one-line
  /// description names a kind of place worth visiting are kept.
  Future<List<ExploreLocation>> _fetchWikipedia(
    LatLng around,
    _Region region,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://en.wikipedia.org/w/api.php',
      queryParameters: {
        'action': 'query',
        'generator': 'geosearch',
        'ggscoord': '${around.latitude}|${around.longitude}',
        'ggsradius': 10000,
        'ggslimit': 50,
        'prop': 'coordinates|pageimages|description',
        'piprop': 'thumbnail',
        'pithumbsize': 500,
        'colimit': 50,
        'format': 'json',
        'formatversion': 2,
      },
      options: Options(
        headers: {'User-Agent': _userAgent},
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    final pages =
        (response.data?['query']?['pages'] as List<dynamic>?) ?? const [];
    final places = <ExploreLocation>[];
    for (final raw in pages) {
      final page = raw as Map<String, dynamic>;
      final coords = (page['coordinates'] as List?)?.firstOrNull as Map?;
      final lat = coords?['lat'] as num?;
      final lon = coords?['lon'] as num?;
      final title = page['title'] as String?;
      final description = (page['description'] as String?) ?? '';
      if (lat == null || lon == null || title == null) continue;

      final kind = _classifyWikipedia(description);
      if (kind == null) continue;

      places.add(
        ExploreLocation(
          id: 'wiki-${page['pageid']}',
          name: title,
          category: kind.category,
          description: description.isEmpty
              ? kind.description
              : '${description[0].toUpperCase()}${description.substring(1)}.',
          latitude: lat.toDouble(),
          longitude: lon.toDouble(),
          xpReward: kind.xp,
          imageUrl: (page['thumbnail'] as Map?)?['source'] as String?,
          neighborhood: region.neighborhood,
          city: region.city,
          district: region.district,
          region: region.region,
          country: region.country,
        ),
      );
    }
    return places;
  }

  /// Picks a category from an article's short description, or null for things
  /// that aren't places to explore (schools, hospitals, states, companies...).
  _Kind? _classifyWikipedia(String description) {
    final d = description.toLowerCase();
    bool has(List<String> words) => words.any(d.contains);

    // Not destinations, even if they mention a lake or a fort in passing.
    if (has([
      'school',
      'college',
      'university',
      'hospital',
      'institute',
      'stadium',
      'airport',
      'railway station',
      'bus ',
      'state in',
      'union territory',
      'district',
      'city in',
      'town in',
      'village in',
      'locality',
      'region',
      'highway',
      'road ',
      'neighbourhood',
      'company',
      'club',
    ])) {
      return null;
    }

    // Kinds version 1 doesn't show (see LocationRepository.hiddenCategories).
    if (has(['waterfall', 'falls', 'mountain', 'peak', 'summit', 'trek'])) {
      return null;
    }
    if (has(['lake', 'reservoir', 'dam ', 'river', 'beach'])) {
      return const _Kind(LocationCategory.lake, 60, 'A lake.');
    }
    if (has(['cave', 'spring', 'stepwell', 'baoli'])) {
      return const _Kind(
        LocationCategory.hiddenGem,
        110,
        'A place to discover.',
      );
    }
    if (has(['viewpoint', 'viewing', 'observation'])) {
      return const _Kind(LocationCategory.viewpoint, 70, 'A scenic viewpoint.');
    }
    if (has([
      'fort',
      'palace',
      'temple',
      'mosque',
      'church',
      'gurdwara',
      'gurudwara',
      'cathedral',
      'shrine',
      'tomb',
      'mausoleum',
      'monument',
      'memorial',
      'museum',
      'ruins',
      'heritage',
      'haveli',
      'castle',
      'archaeological',
      'historic',
      'monastery',
    ])) {
      return const _Kind(LocationCategory.heritage, 80, 'A historic site.');
    }
    if (has([
      'park',
      'garden',
      'sanctuary',
      'reserve',
      'forest',
      'wildlife',
      'zoo',
    ])) {
      return const _Kind(LocationCategory.nature, 70, 'A place in nature.');
    }
    if (has(['tourist', 'attraction', 'landmark', 'sculpture', 'bridge'])) {
      return const _Kind(
        LocationCategory.photography,
        60,
        'A photogenic landmark.',
      );
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _queryOverpass(String query) async {
    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          endpoint,
          data: {'data': query},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {'User-Agent': _userAgent},
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 35),
          ),
        );
        final elements = response.data?['elements'] as List<dynamic>? ?? [];
        return [for (final e in elements) Map<String, dynamic>.from(e as Map)];
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('Could not reach the places service: $lastError');
  }

  // -------------------------------------------------------------------------
  // Mapping OpenStreetMap -> ExploreLocation
  // -------------------------------------------------------------------------

  ExploreLocation? _toLocation(Map<String, dynamic> element, _Region region) {
    final tags = <String, String>{
      for (final entry in ((element['tags'] as Map?) ?? const {}).entries)
        entry.key.toString(): entry.value.toString(),
    };
    final name = tags['name:en'] ?? tags['name'];
    if (name == null || name.trim().isEmpty) return null;

    final center = element['center'] as Map?;
    final lat = (element['lat'] ?? center?['lat']) as num?;
    final lon = (element['lon'] ?? center?['lon']) as num?;
    if (lat == null || lon == null) return null;

    final kind = _classify(tags);
    if (kind == null) return null;

    return ExploreLocation(
      id: 'osm-${element['type']}-${element['id']}',
      name: name.trim(),
      category: kind.category,
      description: tags['description'] ?? kind.description,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      xpReward: kind.xp,
      neighborhood: region.neighborhood,
      city: region.city,
      district: region.district,
      region: region.region,
      country: region.country,
    );
  }

  /// Maps OSM tags to the app's categories. Famous places (those with a
  /// Wikipedia/Wikidata entry) keep their natural category; lesser-known
  /// viewpoints, springs, caves and historic sites become
  /// "hidden gems" — a transparent stand-in for "off the beaten path".
  _Kind? _classify(Map<String, String> tags) {
    final famous =
        tags.containsKey('wikipedia') || tags.containsKey('wikidata');

    if (tags['tourism'] == 'viewpoint') {
      return famous
          ? const _Kind(LocationCategory.viewpoint, 70, 'A scenic viewpoint.')
          : const _Kind(
              LocationCategory.hiddenGem,
              100,
              'A lesser-known viewpoint.',
            );
    }
    if (tags['natural'] == 'spring' || tags['natural'] == 'cave_entrance') {
      return _Kind(
        LocationCategory.hiddenGem,
        110,
        tags['natural'] == 'spring'
            ? 'A natural spring.'
            : 'A cave to explore.',
      );
    }
    if (tags['natural'] == 'water') {
      return const _Kind(LocationCategory.lake, 60, 'A lake.');
    }
    if (tags['leisure'] == 'nature_reserve') {
      return const _Kind(LocationCategory.nature, 70, 'A nature reserve.');
    }
    if (tags.containsKey('historic')) {
      return famous
          ? const _Kind(LocationCategory.heritage, 80, 'A historic site.')
          : const _Kind(
              LocationCategory.hiddenGem,
              100,
              'A lesser-known historic site.',
            );
    }
    if (tags['tourism'] == 'attraction') {
      return const _Kind(
        LocationCategory.photography,
        60,
        'A photogenic landmark.',
      );
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Reverse geocoding (city / region / country for the Passport hierarchy)
  // -------------------------------------------------------------------------

  Future<_Region> _reverseGeocode(LatLng at) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'format': 'jsonv2',
          'lat': at.latitude,
          'lon': at.longitude,
          'zoom': 14,
          'accept-language': 'en',
        },
        options: Options(
          headers: {'User-Agent': _userAgent},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final address =
          (response.data?['address'] as Map?)?.cast<String, dynamic>() ?? {};
      String? pick(List<String> keys) {
        for (final key in keys) {
          final value = address[key];
          if (value is String && value.isNotEmpty) return value;
        }
        return null;
      }

      final city = pick(['city', 'town', 'municipality', 'county', 'village']);
      return _Region(
        neighborhood:
            pick(['suburb', 'neighbourhood', 'quarter', 'village', 'hamlet']) ??
            city ??
            'Nearby',
        city: city ?? 'Nearby',
        district:
            pick(['state_district', 'county', 'city_district']) ??
            city ??
            'Nearby',
        region: pick(['state', 'region', 'province']) ?? 'Nearby',
        country: pick(['country']) ?? 'Unknown',
      );
    } catch (_) {
      // Offline or rate-limited: places are still usable without a region.
      return const _Region.unknown();
    }
  }
}

class _Kind {
  const _Kind(this.category, this.xp, this.description);

  final LocationCategory category;
  final int xp;
  final String description;
}

class _Region {
  const _Region({
    required this.neighborhood,
    required this.city,
    required this.district,
    required this.region,
    required this.country,
  });

  const _Region.unknown()
    : neighborhood = 'Nearby',
      city = 'Nearby',
      district = 'Nearby',
      region = 'Nearby',
      country = 'Unknown';

  final String neighborhood;
  final String city;
  final String district;
  final String region;
  final String country;
}
