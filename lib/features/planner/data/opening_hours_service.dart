import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../explore/domain/search_ranking.dart';

/// A stop to look up hours for. [key] is how the caller finds the answer.
typedef HoursQuery = ({
  String key,
  String? placeId,
  String name,
  double lat,
  double lng,
});

final openingHoursServiceProvider = Provider<OpeningHoursService>((ref) {
  return OpeningHoursService(
    Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
  );
});

/// Raw `opening_hours` text for each stop of an itinerary day that has it,
/// keyed by [HoursQuery.key]. The day's stops are encoded as JSON (see
/// [encodeHoursQueries]) so equal days share one lookup.
final dayOpeningHoursProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, encoded) async {
      final queries = decodeHoursQueries(encoded);
      final hours = await ref
          .read(openingHoursServiceProvider)
          .hoursFor(queries);
      ref.keepAlive(); // Hours don't change while the app is open.
      return hours;
    });

String encodeHoursQueries(List<HoursQuery> queries) => jsonEncode([
  for (final q in queries) [q.key, q.placeId, q.name, q.lat, q.lng],
]);

List<HoursQuery> decodeHoursQueries(String encoded) => [
  for (final item in jsonDecode(encoded) as List<dynamic>)
    (
      key: item[0] as String,
      placeId: item[1] as String?,
      name: item[2] as String,
      lat: (item[3] as num).toDouble(),
      lng: (item[4] as num).toDouble(),
    ),
];

/// Opening hours from OpenStreetMap's `opening_hours` tag, via the public
/// Overpass API. One request covers all the stops of a day (the free servers
/// are busy, so we ask little), and answers are kept on the phone: hours for
/// [_foundFor], "not listed" for [_missingFor].
///
/// A stop is matched by its OpenStreetMap id when it has one (`osm-N123`
/// from search, `osm-node-123` from nearby places), otherwise by name among
/// places with hours within [_matchRadius] of it.
class OpeningHoursService {
  OpeningHoursService(this._dio);

  final Dio _dio;

  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];
  static const _userAgent = 'com.example.real_world_exploration';
  static const _cacheKey = 'opening_hours_cache_v1';
  static const _foundFor = Duration(days: 14);
  static const _missingFor = Duration(days: 2);
  static const _matchRadius = 200;

  Future<Map<String, String>> hoursFor(List<HoursQuery> queries) async {
    if (queries.isEmpty) return const {};
    final cache = await _readCache();
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <String, String>{};
    final toAsk = <HoursQuery>[];

    for (final q in queries) {
      final entry = cache[_cacheKeyFor(q)];
      if (entry is Map) {
        final at = entry['at'] as int? ?? 0;
        final hours = entry['h'] as String?;
        final maxAge = hours == null ? _missingFor : _foundFor;
        if (now - at < maxAge.inMilliseconds) {
          if (hours != null) result[q.key] = hours;
          continue;
        }
      }
      toAsk.add(q);
    }
    if (toAsk.isEmpty) return result;

    final List<Map<String, dynamic>> elements;
    try {
      elements = await _query(buildQuery(toAsk));
    } catch (_) {
      return result; // Unreachable: not cached, so it's asked again later.
    }

    for (final q in toAsk) {
      final hours = matchHours(q, elements);
      cache[_cacheKeyFor(q)] = {'at': now, 'h': hours};
      if (hours != null) result[q.key] = hours;
    }
    await _writeCache(cache);
    return result;
  }

  /// `node`, `way` or `relation` and its number, from an app place id.
  static (String, int)? osmIdOf(String? placeId) {
    if (placeId == null) return null;
    final m = RegExp(r'^osm-(?:(node|way|relation)-|([NWR]))(\d+)$')
        .firstMatch(placeId);
    if (m == null) return null;
    final type =
        m.group(1) ??
        const {'N': 'node', 'W': 'way', 'R': 'relation'}[m.group(2)]!;
    return (type, int.parse(m.group(3)!));
  }

  /// One Overpass query for all [queries]: places by id, plus anything named
  /// with hours around the others.
  static String buildQuery(List<HoursQuery> queries) {
    final parts = <String>[];
    for (final q in queries) {
      final id = osmIdOf(q.placeId);
      if (id != null) {
        parts.add('${id.$1}(id:${id.$2});');
      }
      // Also by name nearby: the tagged element may not be the one we have
      // (a temple's building vs. its grounds).
      parts.add(
        'nwr(around:$_matchRadius,${q.lat},${q.lng})["opening_hours"]["name"];',
      );
    }
    return '[out:json][timeout:25];(${parts.join()});out tags center 300;';
  }

  /// The hours for [q] among Overpass [elements]: the element with its id if
  /// it has hours, else the best name match within reach.
  static String? matchHours(HoursQuery q, List<Map<String, dynamic>> elements) {
    String? hoursOf(Map<String, dynamic> e) =>
        ((e['tags'] as Map?)?['opening_hours'] as String?)?.trim();

    final id = osmIdOf(q.placeId);
    if (id != null) {
      for (final e in elements) {
        if (e['type'] == id.$1 && e['id'] == id.$2) {
          final h = hoursOf(e);
          if (h != null && h.isNotEmpty) return h;
        }
      }
    }

    const distance = Distance();
    final here = LatLng(q.lat, q.lng);
    String? best;
    var bestScore = 0;
    var bestMeters = double.infinity;
    for (final e in elements) {
      final h = hoursOf(e);
      if (h == null || h.isEmpty) continue;
      final tags = e['tags'] as Map;
      final lat = (e['lat'] ?? (e['center'] as Map?)?['lat']) as num?;
      final lng = (e['lon'] ?? (e['center'] as Map?)?['lon']) as num?;
      if (lat == null || lng == null) continue;
      final meters = distance(here, LatLng(lat.toDouble(), lng.toDouble()));
      if (meters > _matchRadius + 50) continue;
      // Either name may be the longer one ("Sarnath Museum" vs "Archaeological
      // Museum Sarnath"), so score both ways.
      var s = 0;
      for (final n in [tags['name:en'], tags['name']].whereType<String>()) {
        s = math.max(s, math.max(nameScore(q.name, n), nameScore(n, q.name)));
      }
      if (s < 65) continue;
      if (s > bestScore || (s == bestScore && meters < bestMeters)) {
        best = h;
        bestScore = s;
        bestMeters = meters;
      }
    }
    return best;
  }

  static String _cacheKeyFor(HoursQuery q) =>
      q.placeId ??
      '${normalizeForSearch(q.name)}@${q.lat.toStringAsFixed(4)},${q.lng.toStringAsFixed(4)}';

  Future<List<Map<String, dynamic>>> _query(String query) async {
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
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        final elements = response.data?['elements'] as List<dynamic>? ?? [];
        return [for (final e in elements) Map<String, dynamic>.from(e as Map)];
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('Could not reach Overpass: $lastError');
  }

  Future<Map<String, dynamic>> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeCache(Map<String, dynamic> cache) async {
    try {
      // Keep it small: drop the oldest beyond 300 places.
      if (cache.length > 300) {
        final keys = cache.keys.toList()
          ..sort(
            (a, b) => ((cache[a] as Map)['at'] as int).compareTo(
              (cache[b] as Map)['at'] as int,
            ),
          );
        for (final k in keys.take(cache.length - 300)) {
          cache.remove(k);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(cache));
    } catch (_) {}
  }
}
