import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/services/location_service.dart';
import 'package:real_world_exploration/features/explore/data/city_repository.dart';
import 'package:real_world_exploration/features/explore/data/place_search_service.dart';
import 'package:real_world_exploration/features/explore/data/recent_searches.dart';
import 'package:real_world_exploration/features/explore/domain/search_ranking.dart';
import 'package:real_world_exploration/features/explore/domain/search_result.dart';
import 'package:real_world_exploration/features/explore/presentation/widgets/explore_search_bar.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The real bundled catalog, read from disk.
class _CatalogBundle extends Fake implements AssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      File('assets/data/india_cities.json').readAsString();
}

class _NoGps extends LocationService {
  @override
  Future<LatLng?> getCurrentLocation({
    bool acceptRecent = false,
    Duration recentFor = const Duration(minutes: 10),
  }) async => null;
}

/// Phone search as normal; online answers controlled by the test.
class _FakeSearch extends PlaceSearchService {
  _FakeSearch(CityRepository cities)
    : super(dio: Dio(), cityRepository: cities, savedPlaces: () async => []);

  final online = <String, Completer<List<SearchResult>>>{};

  @override
  Future<List<SearchResult>> searchOnline(
    String query, {
    LatLng? near,
    int limit = 10,
  }) => (online[query.trim()] ??= Completer()).future;

  @override
  Future<List<SearchResult>> searchNominatim(
    String query, {
    LatLng? near,
  }) async => const [];
}

SearchResult _place(String title, double lat, double lng) => SearchResult(
  title: title,
  subtitle: 'Attraction',
  location: LatLng(lat, lng),
  type: SearchResultType.place,
  placeId: 'osm-N$title',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CityRepository cities;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cities = CityRepository(bundle: _CatalogBundle());
  });

  Future<List<String>> top(String q, [int n = 3]) async =>
      (await cities.searchCities(q)).take(n).map((c) => c.name).toList();

  group('city search', () {
    test('old names find today\'s city', () async {
      expect((await top('Banaras')).first, 'Varanasi');
      expect((await top('bombay')).first, 'Mumbai');
      expect((await top('Bangalore')).first, 'Bengaluru');
      expect((await top('gurgaon')).first, 'Gurugram');
      expect((await top('trivandrum')).first, 'Kovalam & Trivandrum');
    });

    test('small typos still find the city', () async {
      expect((await top('varansi')).first, 'Varanasi');
      expect((await top('Rishikes')).first, 'Rishikesh');
      expect((await top('jaipure')).first, 'Jaipur');
      expect((await top('Darjiling')).first, 'Darjeeling & Kalimpong');
    });

    test('either half of a compound name works', () async {
      expect((await top('Aurangabad')).first, contains('Aurangabad'));
      expect((await top('Coonoor')).first, 'Ooty & Coonoor');
      expect(await top('goa'), everyElement(contains('Goa')));
    });

    test('the city you named beats cities in a state of that name', () async {
      // "Goa" is a state too, but cities named Goa come first.
      final ranked = await cities.searchCities('Pune');
      expect(ranked.first.name, 'Pune');
    });

    test('a state lists its cities', () async {
      final rajasthan = await cities.searchCities('Rajasthan');
      expect(rajasthan.length, greaterThan(5));
      expect(rajasthan.every((c) => c.state == 'Rajasthan'), isTrue);
    });

    test('unrelated text finds nothing', () async {
      expect(await cities.searchCities('xqzw'), isEmpty);
    });
  });

  group('ranking helpers', () {
    test('scores order exact, prefix, word prefix, contains, typo', () {
      expect(nameScore('agra', 'Agra'), 100);
      expect(nameScore('agr', 'Agra'), 90);
      expect(nameScore('vrind', 'Mathura & Vrindavan'), 80);
      expect(nameScore('sarnath museum', 'Archaeological Museum Sarnath'), 70);
      expect(nameScore('ndava', 'Mathura & Vrindavan'), 65);
      expect(nameScore('vrindavn', 'Mathura & Vrindavan'), 55);
      expect(nameScore('ab', 'Kabul'), 0); // Too short to match inside.
    });

    test('edit distance counts swaps as one', () {
      expect(editDistance('varnasi', 'varansi'), 1);
      expect(editDistance('kitten', 'sitting'), 3);
    });

    test('highlights the typed part', () {
      expect(matchRange('ghat', 'Assi Ghat'), (start: 5, end: 9));
      expect(matchRange('xyz', 'Assi Ghat'), isNull);
    });
  });

  group('online results (Photon)', () {
    test('keeps India only, readable kinds and stable ids', () {
      final results = PlaceSearchService.parsePhoton({
        'features': [
          {
            'geometry': {
              'coordinates': [75.8267, 26.9239],
            },
            'properties': {
              'name': 'Hawa Mahal',
              'osm_type': 'W',
              'osm_id': 123,
              'osm_key': 'historic',
              'osm_value': 'palace',
              'city': 'Jaipur',
              'state': 'Rajasthan',
              'countrycode': 'IN',
            },
          },
          {
            'geometry': {
              'coordinates': [73.0, 31.5],
            },
            'properties': {'name': 'Lahore Fort', 'countrycode': 'PK'},
          },
          {
            'geometry': {
              'coordinates': [75.8, 26.9],
            },
            'properties': {'countrycode': 'IN'}, // No name.
          },
        ],
      }, near: const LatLng(26.9124, 75.7873));

      expect(results, hasLength(1));
      final hawaMahal = results.single;
      expect(hawaMahal.title, 'Hawa Mahal');
      expect(hawaMahal.kind, 'Palace');
      expect(hawaMahal.category, LocationCategory.heritage);
      expect(hawaMahal.subtitle, 'Palace · Jaipur, Rajasthan');
      expect(hawaMahal.placeId, 'osm-W123');
      expect(hawaMahal.distanceKm, closeTo(4, 1));
    });

    test('describes common places', () {
      expect(
        describeOsmPlace('amenity', 'place_of_worship').$1,
        'Place of worship',
      );
      expect(
        describeOsmPlace('waterway', 'waterfall').$2,
        LocationCategory.waterfall,
      );
      expect(describeOsmPlace('natural', 'water').$1, 'Lake');
      expect(describeOsmPlace('railway', 'station').$1, 'Railway station');
      expect(describeOsmPlace(null, null).$1, 'Place');
    });

    test('merging drops online copies of catalog cities and saved places', () {
      final varanasi = SearchResult(
        title: 'Varanasi',
        subtitle: 'Uttar Pradesh',
        location: const LatLng(25.3176, 82.9739),
        type: SearchResultType.city,
      );
      final merged = PlaceSearchService.mergeResults(
        [varanasi, _place('Assi Ghat', 25.2895, 83.0066)],
        [
          _place('Varanasi', 25.32, 82.99), // The town again.
          _place('Varanasi Junction', 25.33, 82.99), // A station: kept.
          _place('Assi Ghat', 25.2896, 83.0067), // Same ghat.
          _place('Assi Ghat', 28.6, 77.2), // Another Assi Ghat, far away.
          _place('Kashi Vishwanath Temple', 25.3109, 83.0107),
        ],
      );
      expect(merged.map((r) => r.title), [
        'Varanasi',
        'Assi Ghat',
        'Varanasi Junction',
        'Assi Ghat',
        'Kashi Vishwanath Temple',
      ]);
      expect(merged[3].location.latitude, 28.6);
    });
  });

  group('phone search', () {
    test('finds saved places by name, nearest first on ties', () async {
      ExploreLocation saved(String id, String name, double lat) =>
          ExploreLocation(
            id: id,
            name: name,
            category: LocationCategory.lake,
            description: '',
            latitude: lat,
            longitude: 76.8,
          );
      final service = PlaceSearchService(
        dio: Dio(),
        cityRepository: cities,
        savedPlaces: () async => [
          saved('far', 'Sukhna Lake View', 31.5),
          saved('near', 'Sukhna Lake', 30.74),
          saved('other', 'Rock Garden', 30.75),
        ],
      );
      final results = await service.searchLocal(
        'sukhna',
        near: const LatLng(30.73, 76.78),
      );
      expect(results.map((r) => r.placeId), ['near', 'far']);
      expect(results.first.savedPlace, isNotNull);
      expect(results.first.distanceKm, lessThan(3));
    });
  });

  group('recent searches', () {
    test('newest first, no duplicates, at most 8, survive reloads', () async {
      final recent = RecentSearches(cities);
      for (var i = 0; i < 10; i++) {
        await recent.add(_place('Place $i', 25 + i / 10, 80));
      }
      await recent.add(_place('Place 5', 25.5, 80)); // Again: moves to top.
      final loaded = await RecentSearches(cities).load();
      expect(loaded, hasLength(RecentSearches.maxItems));
      expect(loaded.first.title, 'Place 5');
      expect(loaded.where((r) => r.title == 'Place 5'), hasLength(1));

      await recent.remove(loaded.first);
      expect((await recent.load()).first.title, 'Place 9');
      await recent.clear();
      expect(await recent.load(), isEmpty);
    });

    test('a recent city comes back with its catalog entry', () async {
      final recent = RecentSearches(cities);
      final jaipur = (await cities.searchCities('Jaipur')).first;
      await recent.add(
        SearchResult(
          title: jaipur.name,
          subtitle: jaipur.state,
          location: jaipur.location,
          type: SearchResultType.city,
          city: jaipur,
        ),
      );
      expect((await recent.load()).single.city?.id, jaipur.id);
    });
  });

  group('search sheet', () {
    late _FakeSearch search;

    Future<void> pump(WidgetTester tester) async {
      search = _FakeSearch(cities);
      // Reading the catalog from disk is real I/O, which the widget test's
      // fake clock can't wait for: load it first (it's cached after).
      await tester.runAsync(cities.getCities);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cityRepositoryProvider.overrideWithValue(cities),
            placeSearchServiceProvider.overrideWithValue(search),
            locationServiceProvider.overrideWithValue(_NoGps()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SearchSheet(onSelectResult: (_) {}, onPlanTrip: (_) {}),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    testWidgets('shows recent and popular before typing', (tester) async {
      await pump(tester);
      expect(find.text('Popular destinations'), findsOneWidget);
      expect(find.text('Varanasi'), findsOneWidget);
    });

    testWidgets('phone results show at once, online ones join later', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'banaras');
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('Varanasi'), findsOneWidget); // Before online answers.
      expect(find.text('Searching more places…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      search.online['banaras']!.complete([
        _place('Banaras Hindu University', 25.27, 82.99),
      ]);
      await tester.pump();
      expect(find.textContaining('Hindu University'), findsOneWidget);
      expect(find.text('Searching more places…'), findsNothing);
    });

    testWidgets('a slow answer for an old query is ignored', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'agra');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'jaipur');
      await tester.pump(const Duration(milliseconds: 400));

      search.online['agra']!.complete([_place('Agra Fort', 27.18, 78.02)]);
      search.online['jaipur']!.complete([_place('Hawa Mahal', 26.92, 75.83)]);
      await tester.pump();
      expect(find.textContaining('Agra Fort'), findsNothing);
      expect(find.textContaining('Hawa Mahal'), findsOneWidget);
    });

    testWidgets('offline, it says so and keeps phone results', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'jaipur');
      await tester.pump(const Duration(milliseconds: 400));
      search.online['jaipur']!.completeError(
        const SearchUnavailableException(),
      );
      await tester.pump();
      expect(find.textContaining('Offline'), findsOneWidget);
      expect(find.textContaining('Jaipur'), findsWidgets);
    });

    testWidgets('no matches offers to search everywhere', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'qqqzzz');
      await tester.pump(const Duration(milliseconds: 400));
      search.online['qqqzzz']!.complete(const []);
      await tester.pump();
      expect(find.text('No matches for "qqqzzz"'), findsOneWidget);
      expect(find.text('Search everywhere'), findsOneWidget);
    });
  });
}
