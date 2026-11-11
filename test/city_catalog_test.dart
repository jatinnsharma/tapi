import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/explore/data/city_repository.dart';
import 'package:real_world_exploration/features/explore/domain/city.dart';

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
    {
      'id': 'new-delhi',
      'name': 'New Delhi',
      'state': 'Delhi',
      'latitude': 28.6139,
      'longitude': 77.2090,
      'blurb': 'Capital city with historic Mughal monuments.',
      'imageUrl': 'https://example.com/delhi.jpg',
      'category': 'metropolis',
    },
  ];

  group('City Model', () {
    test('fromJson and toJson are consistent', () {
      final city = City.fromJson(sampleCities.first);
      expect(city.id, 'varanasi');
      expect(city.name, 'Varanasi');
      expect(city.state, 'Uttar Pradesh');
      expect(city.latitude, 25.3176);
      expect(city.longitude, 82.9739);
      expect(city.location.latitude, 25.3176);
      expect(city.location.longitude, 82.9739);

      final jsonMap = city.toJson();
      expect(jsonMap['id'], 'varanasi');
      expect(jsonMap['category'], 'spiritual');
    });
  });

  group('CityRepository', () {
    late CityRepository repository;

    setUp(() {
      final fakeBundle = _FakeAssetBundle(jsonEncode(sampleCities));
      repository = CityRepository(bundle: fakeBundle);
    });

    test('getCities loads and caches all cities', () async {
      final cities = await repository.getCities();
      expect(cities.length, 3);
      expect(
        cities.map((c) => c.name),
        containsAll(['Varanasi', 'Jaipur', 'New Delhi']),
      );
    });

    test('getCityById returns correct city', () async {
      final city = await repository.getCityById('jaipur');
      expect(city, isNotNull);
      expect(city!.name, 'Jaipur');
      expect(city.state, 'Rajasthan');

      final notFound = await repository.getCityById('unknown');
      expect(notFound, isNull);
    });

    test('searchCities matches name, state or category', () async {
      final byName = await repository.searchCities('Varanasi');
      expect(byName.length, 1);
      expect(byName.first.id, 'varanasi');

      final byState = await repository.searchCities('Rajasthan');
      expect(byState.length, 1);
      expect(byState.first.id, 'jaipur');

      final byCategory = await repository.searchCities('metropolis');
      expect(byCategory.length, 1);
      expect(byCategory.first.id, 'new-delhi');
    });

    test('getNearbyCities sorts by distance from a given point', () async {
      // From Gurgaon / near Delhi: Delhi should be closest, then Jaipur, then Varanasi
      const nearDelhi = LatLng(28.4595, 77.0266);
      final nearby = await repository.getNearbyCities(nearDelhi, limit: 3);

      expect(nearby.length, 3);
      expect(nearby[0].id, 'new-delhi');
      expect(nearby[1].id, 'jaipur');
      expect(nearby[2].id, 'varanasi');
    });

    test('findNearestCity returns single closest city', () async {
      const nearJaipur = LatLng(26.85, 75.80);
      final nearest = await repository.findNearestCity(nearJaipur);

      expect(nearest, isNotNull);
      expect(nearest!.id, 'jaipur');
    });
  });
}
