import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/config/service_area.dart';
import 'package:real_world_exploration/features/locations/data/location_repository.dart';
import 'package:real_world_exploration/features/locations/data/location_seed.dart';

void main() {
  group('ServiceArea (All of India)', () {
    test('contains New Delhi (default center)', () {
      expect(ServiceArea.contains(ServiceArea.center), isTrue);
      expect(ServiceArea.kmFromCenter(ServiceArea.center), 0);
    });

    test('contains Chandigarh and other Indian cities', () {
      expect(ServiceArea.contains(ServiceArea.chandigarhCenter), isTrue);
      const varanasi = LatLng(25.3176, 82.9739);
      const jaipur = LatLng(26.9124, 75.7873);
      const kochi = LatLng(9.9312, 76.2673);
      const leh = LatLng(34.1526, 77.5771);

      expect(ServiceArea.contains(varanasi), isTrue);
      expect(ServiceArea.contains(jaipur), isTrue);
      expect(ServiceArea.contains(kochi), isTrue);
      expect(ServiceArea.contains(leh), isTrue);
    });

    test('excludes locations outside India', () {
      const london = LatLng(51.5074, -0.1278);
      const newYork = LatLng(40.7128, -74.0060);
      const tokyo = LatLng(35.6762, 139.6503);

      expect(ServiceArea.contains(london), isFalse);
      expect(ServiceArea.contains(newYork), isFalse);
      expect(ServiceArea.contains(tokyo), isFalse);
    });

    test('isNear checks radius correctly', () {
      const center = LatLng(28.6139, 77.2090); // Delhi
      const nearby = LatLng(28.6500, 77.2200); // ~4 km
      const farAway = LatLng(30.7333, 76.7794); // Chandigarh ~240 km

      expect(ServiceArea.isNear(nearby, center, radiusKm: 10), isTrue);
      expect(ServiceArea.isNear(farAway, center, radiusKm: 50), isFalse);
    });
  });

  group('Built-in places', () {
    test('there are some', () {
      expect(locationSeed, isNotEmpty);
    });

    test('all lie inside the service area', () {
      for (final place in locationSeed) {
        expect(
          ServiceArea.containsCoordinates(place.latitude, place.longitude),
          isTrue,
          reason: '${place.name} is outside ${ServiceArea.name}',
        );
      }
    });

    test('have unique ids in the same form as the online fetch', () {
      final ids = [for (final p in locationSeed) p.id];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, everyElement(startsWith('wiki-')));
    });

    test('include none of the kinds version 1 hides', () {
      for (final place in locationSeed) {
        expect(
          LocationRepository.hiddenCategories.contains(place.category),
          isFalse,
          reason: '${place.name} is a hidden kind (${place.category.name})',
        );
      }
    });

    test('have names, descriptions and a positive XP reward', () {
      for (final place in locationSeed) {
        expect(place.name.trim(), isNotEmpty);
        expect(place.description.trim(), isNotEmpty);
        expect(place.xpReward, greaterThan(0));
      }
    });
  });
}
