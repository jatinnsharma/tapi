import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/locations/data/location_repository.dart';
import 'package:real_world_exploration/features/locations/data/nearby_places_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLocationRepository extends Fake implements LocationRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NearbyPlacesService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = NearbyPlacesService(Dio(), _FakeLocationRepository());
  });

  group('NearbyPlacesService Multi-Area Cache', () {
    const varanasi = LatLng(25.3176, 82.9739);
    const varanasiClose = LatLng(25.3200, 82.9800); // ~0.7 km away
    const jaipur = LatLng(26.9124, 75.7873); // ~600 km away
    const delhi = LatLng(28.6139, 77.2090);

    test('uncached location is stale and attempts network fetch', () async {
      await expectLater(
        service.ensureFresh(varanasi, force: false),
        throwsA(isA<StateError>()),
      );
    });

    test('recording an area caches it independently of other areas', () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Simulate Varanasi in area cache
      await prefs.setString(
        'nearby_fetch_areas_v1',
        '[{"lat":25.3176,"lng":82.9739,"at":$now,"city":"Varanasi"}]',
      );

      // Varanasi is fresh (< 10 km, < 7 days): ensureFresh returns 0 without network call
      final resultVaranasi = await service.ensureFresh(varanasi);
      expect(resultVaranasi, 0);

      final resultClose = await service.ensureFresh(varanasiClose);
      expect(resultClose, 0);

      // Jaipur is NOT cached, so it attempts network call and throws StateError in offline test
      await expectLater(
        service.ensureFresh(jaipur),
        throwsA(isA<StateError>()),
      );

      // Cache Jaipur as well
      await prefs.setString(
        'nearby_fetch_areas_v1',
        '[{"lat":25.3176,"lng":82.9739,"at":$now,"city":"Varanasi"},{"lat":26.9124,"lng":75.7873,"at":$now,"city":"Jaipur"}]',
      );

      // Both Varanasi and Jaipur are now recognized as fresh cached areas
      expect(await service.ensureFresh(varanasi), 0);
      expect(await service.ensureFresh(jaipur), 0);

      // Delhi with expired timestamp (> 7 days) is treated as stale and attempts fetch
      final eightDaysAgo = now - const Duration(days: 8).inMilliseconds;
      await prefs.setString(
        'nearby_fetch_areas_v1',
        '[{"lat":28.6139,"lng":77.2090,"at":$eightDaysAgo,"city":"Delhi"}]',
      );

      await expectLater(service.ensureFresh(delhi), throwsA(isA<StateError>()));
    });
  });
}
