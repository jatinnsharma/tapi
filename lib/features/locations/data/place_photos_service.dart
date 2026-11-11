import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/service_area.dart';
import '../domain/location.dart';

/// A freely licensed photo of a place, from Wikimedia Commons. Commons
/// licences require crediting the author and naming the licence, so both
/// travel with the photo and are shown with it.
class PlacePhoto {
  const PlacePhoto({
    required this.title,
    required this.thumbUrl,
    required this.fullUrl,
    required this.pageUrl,
    this.author,
    this.license,
  });

  /// Commons file name, e.g. "File:Mani Majra Fort, Chandigarh, India 01.JPG".
  final String title;

  /// About 1000 px wide: for the gallery and the full-screen viewer.
  final String thumbUrl;
  final String fullUrl;

  /// The file's page on Commons (author, licence, full details).
  final String pageUrl;
  final String? author;
  final String? license;

  /// `Photo: <author> · <licence>` for display.
  String get credit {
    final parts = [
      if (author != null && author!.isNotEmpty) author!,
      if (license != null && license!.isNotEmpty) license!,
    ];
    return parts.isEmpty ? 'Wikimedia Commons' : 'Photo: ${parts.join(' · ')}';
  }
}

final placePhotosServiceProvider = Provider<PlacePhotosService>((ref) {
  return PlacePhotosService(Dio());
});

/// Photos of a place, loaded when its sheet opens. Keyed by id and name (a
/// record, so equal keys share one request).
final placePhotosProvider = FutureProvider.autoDispose
    .family<List<PlacePhoto>, PlaceKey>((ref, place) {
      return ref.watch(placePhotosServiceProvider).photosFor(place);
    });

/// What identifies a place for photo lookup. Coordinates let photos be found
/// by where they were taken, which works for places that have no article.
typedef PlaceKey = ({
  String id,
  String name,
  String city,
  double lat,
  double lng,
});

/// Finds photos of a place on Wikimedia, no key needed. All of these run at
/// once and are merged in this order of trust:
///  1. the photos used in the place's Wikipedia article (for places that
///     came from Wikipedia) — reliably of that place;
///  2. the main picture of a Wikipedia article about the place found nearby
///     by name (for places that came from elsewhere, e.g. OpenStreetMap);
///  3. Commons photos geotagged within [_geoRadiusMeters] of the place, the
///     nearest first;
///  4. if that still gives fewer than 3, a Commons search by name, keeping only
///     files whose names contain the place's distinctive words AND its city
///     (or Chandigarh), so a generic name like "Garden of Springs" or
///     "Terraced Garden" can't pull in photos of a garden somewhere else.
class PlacePhotosService {
  PlacePhotosService(this._dio);

  final Dio _dio;

  static const _userAgent = 'com.example.real_world_exploration';
  static const _maxPhotos = 20;
  static const _wikiPrefix = 'wiki-';

  /// Words that describe a kind of place rather than this place, so they
  /// can't confirm that a photo shows it.
  static const _genericWords = {
    'the',
    'and',
    'of',
    'in',
    'at',
    'chandigarh',
    'india',
    'punjab',
    'haryana',
    'panchkula',
    'mohali',
    'sector',
    'garden',
    'gardens',
    'park',
    'lake',
    'fort',
    'temple',
    'mandir',
    'gurdwara',
    'sahib',
    'museum',
    'gallery',
    'monument',
    'memorial',
    'market',
    'valley',
    'centre',
    'center',
    'research',
    'national',
    'government',
    'sanctuary',
    'wildlife',
    'bird',
    'botanical',
    'art',
  };

  /// Photos taken this close to a place are taken to show it.
  static const _geoRadiusMeters = 200;

  /// Photos already found, by place, so reopening a place (or switching
  /// back to an itinerary day) shows them at once without asking again.
  /// Empty answers aren't kept: the next look tries again.
  final _found = <PlaceKey, List<PlacePhoto>>{}; // The app keeps one service.
  static const _foundMax = 80;

  Future<List<PlacePhoto>> photosFor(PlaceKey place) async {
    final known = _found[place];
    if (known != null) return known;
    final photos = await _lookUp(place);
    if (photos.isNotEmpty) {
      _found[place] = photos;
      if (_found.length > _foundMax) _found.remove(_found.keys.first);
    }
    return photos;
  }

  Future<List<PlacePhoto>> _lookUp(PlaceKey place) async {
    final fromArticle = place.id.startsWith(_wikiPrefix)
        ? _articlePhotos(place.id.substring(_wikiPrefix.length))
        : Future.value(const <PlacePhoto>[]);
    final results = await Future.wait([
      fromArticle,
      _nearbyArticleImage(place),
      _geotaggedPhotos(place.lat, place.lng),
    ]);

    final photos = <String, PlacePhoto>{};
    for (final list in results) {
      for (final p in list) {
        photos.putIfAbsent(p.title, () => p);
      }
    }
    if (photos.length < 3) {
      for (final p in await _searchPhotos(place.name, place.city)) {
        photos.putIfAbsent(p.title, () => p);
      }
    }
    return photos.values.take(_maxPhotos).toList();
  }

  /// Commons files with coordinates within [_geoRadiusMeters], nearest first.
  Future<List<PlacePhoto>> _geotaggedPhotos(double lat, double lng) async {
    try {
      final data = await _get('https://commons.wikimedia.org/w/api.php', {
        'action': 'query',
        'generator': 'geosearch',
        'ggscoord': '$lat|$lng',
        'ggsradius': _geoRadiusMeters,
        'ggsnamespace': 6,
        'ggslimit': 20,
        ..._imageInfoParams,
      });
      final pages = (data['query']?['pages'] as List?) ?? const [];
      final order = {
        for (final p in pages.whereType<Map>())
          p['title']: (p['index'] as num?)?.toInt() ?? 1 << 20,
      };
      return _parse(data)
        ..sort((a, b) => order[a.title]!.compareTo(order[b.title]!));
    } catch (_) {
      return const [];
    }
  }

  /// The main picture of a nearby Wikipedia article about this place. The
  /// article must be named like the place, so a neighbour's picture is never
  /// used.
  Future<List<PlacePhoto>> _nearbyArticleImage(PlaceKey place) async {
    try {
      final data = await _get('https://en.wikipedia.org/w/api.php', {
        'action': 'query',
        'generator': 'geosearch',
        'ggscoord': '${place.lat}|${place.lng}',
        'ggsradius': 600,
        'ggslimit': 15,
        'prop': 'pageimages',
        'piprop': 'thumbnail|original',
        'pithumbsize': 1000,
        'format': 'json',
        'formatversion': 2,
      });
      final pages = (data['query']?['pages'] as List?) ?? const [];
      final result = <PlacePhoto>[];
      for (final raw in pages.whereType<Map>()) {
        final title = raw['title'] as String? ?? '';
        final thumb = (raw['thumbnail'] as Map?)?['source'] as String?;
        if (thumb == null || !articleMatchesPlace(title, place.name)) continue;
        result.add(
          PlacePhoto(
            title: 'Wikipedia: $title',
            thumbUrl: thumb,
            fullUrl: (raw['original'] as Map?)?['source'] as String? ?? thumb,
            pageUrl: 'https://en.wikipedia.org/?curid=${raw['pageid']}',
            author: 'Wikipedia',
          ),
        );
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// Whether a Wikipedia article title is about the place called [placeName]:
  /// they share a distinctive word ("Manimajra" in both "Mani Majra Fort" and
  /// "Manimajra Fort"), ignoring spaces and generic words.
  @visibleForTesting
  static bool articleMatchesPlace(String articleTitle, String placeName) {
    String squash(String s) => _normalize(s).replaceAll(' ', '');
    final article = squash(articleTitle);
    final place = squash(placeName);
    if (article.isEmpty || place.isEmpty) return false;
    if (article.contains(place) || place.contains(article)) return true;
    final articleWords = _distinctiveWords(articleTitle);
    final placeWords = _distinctiveWords(placeName);
    if (articleWords.isEmpty || placeWords.isEmpty) return false;
    return placeWords.any(
      (w) => w.length >= 4 && articleWords.any((a) => a == w),
    );
  }

  Future<List<PlacePhoto>> _articlePhotos(String pageId) async {
    try {
      final data = await _get('https://en.wikipedia.org/w/api.php', {
        'action': 'query',
        'pageids': pageId,
        'generator': 'images',
        'gimlimit': 50,
        ..._imageInfoParams,
      });
      return _parse(data);
    } catch (_) {
      return const [];
    }
  }

  Future<List<PlacePhoto>> _searchPhotos(String name, String city) async {
    final words = _distinctiveWords(name);
    if (words.isEmpty) return const [];
    // A matching name isn't enough: the photo must also be from this town.
    final towns = {_normalize(city), _normalize(ServiceArea.name)}..remove('');
    try {
      final data = await _get('https://commons.wikimedia.org/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': '$name filetype:bitmap',
        'gsrnamespace': 6,
        'gsrlimit': 20,
        ..._imageInfoParams,
      });
      return _parse(data).where((p) {
        final title = _normalize(p.title);
        return words.every(title.contains) && towns.any(title.contains);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  static const _imageInfoParams = {
    'prop': 'imageinfo',
    'iiprop': 'url|mime|extmetadata',
    'iiextmetadatafilter': 'Artist|LicenseShortName',
    'iiurlwidth': 1000,
    'format': 'json',
    'formatversion': 2,
  };

  Future<Map<String, dynamic>> _get(
    String url,
    Map<String, Object> query,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      url,
      queryParameters: query,
      options: Options(
        headers: {'User-Agent': _userAgent},
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    return response.data ?? const {};
  }

  /// Keeps photographs only: articles also use maps, flags, icons and
  /// diagrams, which are SVGs or have tell-tale names.
  @visibleForTesting
  List<PlacePhoto> parse(Map<String, dynamic> data) => _parse(data);

  List<PlacePhoto> _parse(Map<String, dynamic> data) {
    final pages = (data['query']?['pages'] as List<dynamic>?) ?? const [];
    final result = <PlacePhoto>[];
    for (final raw in pages) {
      final page = raw as Map<String, dynamic>;
      final title = page['title'] as String? ?? '';
      final info = (page['imageinfo'] as List?)?.firstOrNull as Map?;
      if (info == null) continue;
      final mime = info['mime'] as String? ?? '';
      if (!(mime == 'image/jpeg' ||
          mime == 'image/png' ||
          mime == 'image/webp')) {
        continue;
      }
      final lower = title.toLowerCase();
      if (const [
        'logo',
        'icon',
        'map',
        'flag',
        'symbol',
        'seal',
        'emblem',
      ].any(lower.contains)) {
        continue;
      }
      final thumb = info['thumburl'] as String? ?? info['url'] as String?;
      final full = info['url'] as String?;
      if (thumb == null || full == null) continue;

      // An empty `extmetadata` comes back as a JSON list, not an object.
      final rawMeta = info['extmetadata'];
      final meta = rawMeta is Map ? rawMeta : const {};
      result.add(
        PlacePhoto(
          title: title,
          thumbUrl: thumb,
          fullUrl: full,
          pageUrl:
              info['descriptionurl'] as String? ??
              'https://commons.wikimedia.org/wiki/${Uri.encodeComponent(title)}',
          author: _plainText((meta['Artist'] as Map?)?['value'] as String?),
          license: (meta['LicenseShortName'] as Map?)?['value'] as String?,
        ),
      );
    }
    return result;
  }

  /// The words of a place name that identify it, e.g. "Manimajra" in
  /// "Manimajra Fort" or "springs" in "Garden of Springs, Chandigarh".
  static List<String> _distinctiveWords(String name) =>
      _normalize(name)
          .split(' ')
          .where((w) => w.length >= 3 && !_genericWords.contains(w))
          .toList();

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Commons' author field is HTML (usually a link); keep its text.
  static String? _plainText(String? html) {
    if (html == null) return null;
    final text = html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.isEmpty ? null : text;
  }
}

/// Convenience key for [placePhotosProvider].
extension PlacePhotosKey on ExploreLocation {
  PlaceKey get photosKey =>
      (id: id, name: name, city: city, lat: latitude, lng: longitude);
}
