import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/explore/data/city_repository.dart';
import 'package:real_world_exploration/features/explore/data/place_search_service.dart';
import 'package:real_world_exploration/features/explore/domain/search_result.dart';

class _FakeAssetBundle extends Fake implements AssetBundle {
  _FakeAssetBundle(this.jsonString);
  final String jsonString;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    return jsonString;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleCities = [
    {
      'id': 'varanasi',
      'name': 'Varanasi',
      'state': 'Uttar Pradesh',
      'latitude': 25.3176,
      'longitude': 82.9739,
      'blurb': 'Ancient spiritual city on the sacred Ganges.',
      'imageUrl': 'https://example.com/varanasi.jpg',
      'category': 'spiritual',
    },
    {
      'id': 'jaipur',
      'name': 'Jaipur',
      'state': 'Rajasthan',
      'latitude': 26.9124,
      'longitude': 75.7873,
      'blurb': 'The Pink City with magnificent royal palaces.',
      'imageUrl': 'https://example.com/jaipur.jpg',
      'category': 'heritage',
    },
  ];

  late CityRepository cityRepo;
  late Dio dio;
  late PlaceSearchService service;

  setUp(() {
    final bundle = _FakeAssetBundle(jsonEncode(sampleCities));
    cityRepo = CityRepository(bundle: bundle);
    dio = Dio();
    service = PlaceSearchService(dio: dio, cityRepository: cityRepo);
  });

  group('PlaceSearchService', () {
    test(
      'empty query returns empty list immediately without network request',
      () async {
        final results = await service.search('   ');
        expect(results, isEmpty);
      },
    );

    test('finds local city instantly by name prefix', () async {
      final results = await service.search('Varanasi');
      expect(results, isNotEmpty);
      expect(results.first.title, 'Varanasi');
      expect(results.first.type, SearchResultType.city);
      expect(results.first.city?.id, 'varanasi');
      expect(results.first.location.latitude, 25.3176);
      expect(results.first.isCity, isTrue);
    });

    test('finds local city by partial query', () async {
      final results = await service.search('Jai');
      expect(results.any((r) => r.title == 'Jaipur'), isTrue);
    });
  });

  group('SearchResult domain model', () {
    test('isCity property is accurate', () {
      final cityRes = SearchResult(
        title: 'Manali',
        subtitle: 'Himachal Pradesh · HILL STATION',
        location: const LatLng(32.2432, 77.1892),
        type: SearchResultType.city,
      );
      final placeRes = SearchResult(
        title: 'Hadimba Temple',
        subtitle: 'Temple, Manali',
        location: const LatLng(32.2483, 77.1804),
        type: SearchResultType.place,
      );

      expect(cityRes.isCity, isTrue);
      expect(placeRes.isCity, isFalse);
    });
  });
}
