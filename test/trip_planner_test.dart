import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/features/ai/data/gemini_client.dart';
import 'package:real_world_exploration/features/explore/data/city_repository.dart';
import 'package:real_world_exploration/features/explore/data/place_search_service.dart';
import 'package:real_world_exploration/features/locations/data/location_repository.dart';
import 'package:real_world_exploration/features/locations/data/nearby_places_service.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/planner/data/saved_trips_repository.dart';
import 'package:real_world_exploration/features/planner/data/trip_planner_service.dart';
import 'package:real_world_exploration/features/planner/domain/planner_input.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeAssetBundle extends Fake implements AssetBundle {
  _FakeAssetBundle(this.jsonString);
  final String jsonString;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    return jsonString;
  }
}

/// Answers Gemini with [reply]; every other request fails, as if offline.
class _GeminiOnlyAdapter implements HttpClientAdapter {
  _GeminiOnlyAdapter(this.reply);
  final String reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.uri.host.contains('generativelanguage')) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline in tests',
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '```json\n$reply\n```'},
              ],
            },
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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
  ];

  group('TripPlan Domain Models', () {
    test('JSON serialization & deserialization are consistent', () {
      final stop = TripStop(
        id: 'stop-1',
        placeName: 'Dashashwamedh Ghat',
        description: 'Famous evening Ganga Aarti ghat.',
        timeSlot: 'Evening',
        durationMinutes: 90,
        travelTimeFromPrevious: '10 min walk',
        latitude: 25.3076,
        longitude: 83.0107,
        category: 'heritage',
        tip: 'Arrive early to get a seat on a wooden boat.',
      );

      final day = TripDayPlan(
        dayNumber: 1,
        title: 'Ghats & Sunset Aarti',
        theme: 'Spiritual awakening',
        stops: [stop],
        foodSuggestions: ['Blue Lassi Shop', 'Kachori Gali'],
        dayTip: 'Dress modestly when attending evening prayer.',
      );

      final plan = TripPlan(
        id: 'plan-123',
        title: '3 Days in Varanasi',
        destination: 'Varanasi',
        cityId: 'varanasi',
        daysCount: 3,
        companion: TripCompanion.friends,
        pace: TripPace.moderate,
        budget: TripBudget.moderate,
        interests: ['Spiritual', 'Street Food'],
        createdAt: DateTime(2026, 10, 17),
        days: [day],
        overview: 'An unforgettable cultural immersion.',
      );

      final jsonMap = plan.toJson();
      final roundTrip = TripPlan.fromJson(jsonMap);

      expect(roundTrip.id, 'plan-123');
      expect(roundTrip.title, '3 Days in Varanasi');
      expect(roundTrip.destination, 'Varanasi');
      expect(roundTrip.companion, TripCompanion.friends);
      expect(roundTrip.pace, TripPace.moderate);
      expect(roundTrip.totalStops, 1);
      expect(roundTrip.days.length, 1);
      expect(roundTrip.days.first.stops.first.placeName, 'Dashashwamedh Ghat');
      expect(roundTrip.days.first.foodSuggestions.length, 2);
    });
  });

  group('TripPlannerService (Offline / Grounded Rules Planner)', () {
    late TripPlannerService service;

    setUp(() {
      final bundle = _FakeAssetBundle(jsonEncode(sampleCities));
      final cityRepo = CityRepository(bundle: bundle);
      final dio = Dio();
      final placeSearch = PlaceSearchService(
        dio: dio,
        cityRepository: cityRepo,
      );
      final dbService = DatabaseService();
      final locRepo = LocationRepository(dbService);
      final nearbyService = NearbyPlacesService(dio, locRepo);
      final gemini = GeminiClient(dio);

      service = TripPlannerService(
        geminiClient: gemini,
        nearbyPlacesService: nearbyService,
        locationRepository: locRepo,
        cityRepository: cityRepo,
        placeSearchService: placeSearch,
        isAiReady: false, // tests deterministic offline planner
      );
    });

    test(
      'generates full multi-day itinerary with exact requested days',
      () async {
        const input = PlannerInput(
          destination: 'Varanasi',
          cityId: 'varanasi',
          daysCount: 3,
          companion: TripCompanion.solo,
          pace: TripPace.moderate,
        );

        final plan = await service.generatePlan(input);

        expect(plan.destination, 'Varanasi');
        expect(plan.daysCount, 3);
        expect(plan.days.length, 3);
        expect(plan.days[0].dayNumber, 1);
        expect(plan.days[1].dayNumber, 2);
        expect(plan.days[2].dayNumber, 3);
        expect(plan.totalStops, greaterThanOrEqualTo(3));
        for (final day in plan.days) {
          expect(day.stops, isNotEmpty);
          expect(day.foodSuggestions, isNotEmpty);
          expect(day.dayTip, isNotNull);
        }
      },
    );

    test(
      'regenerateDay updates single day without breaking structure',
      () async {
        const input = PlannerInput(
          destination: 'Varanasi',
          cityId: 'varanasi',
          daysCount: 2,
        );

        final initialPlan = await service.generatePlan(input);
        final day2 = await service.regenerateDay(
          currentPlan: initialPlan,
          dayNumber: 2,
        );

        expect(day2.dayNumber, 2);
        expect(day2.stops, isNotEmpty);
      },
    );
  });

  group('TripPlannerService (AI reply repaired)', () {
    test('a sloppy Gemini plan comes back complete and in Varanasi', () async {
      SharedPreferences.setMockInitialValues({});
      final reply = jsonEncode({
        'title': 'Varanasi with a friend',
        'overview': 'Ghats and food',
        'days': [
          {
            'dayNumber': 1,
            'title': 'Ghats',
            'stops': [
              // Fine: real coordinates in Varanasi.
              {
                'placeName': 'Assi Ghat',
                'timeSlot': 'Morning',
                'durationMinutes': 90,
                'latitude': 25.2895,
                'longitude': 83.0066,
              },
              // The same place again: dropped.
              {
                'placeName': 'Assi Ghat',
                'latitude': 25.2895,
                'longitude': 83.0066,
              },
              // No coordinates: dropped (it used to land in New Delhi).
              {'placeName': 'Imaginary Palace', 'timeSlot': 'Afternoon'},
              // Wrong city: dropped.
              {
                'placeName': 'Gateway of India',
                'latitude': 18.922,
                'longitude': 72.8347,
              },
            ],
          },
          // Only one stop, and it's in Mumbai: the day gets refilled.
          {
            'dayNumber': 2,
            'title': 'Mumbai by mistake',
            'stops': [
              {
                'placeName': 'Marine Drive',
                'latitude': 18.943,
                'longitude': 72.823,
              },
            ],
          },
          // Day 3 is missing altogether.
        ],
      });

      final dio = Dio()..httpClientAdapter = _GeminiOnlyAdapter(reply);
      final cityRepo = CityRepository(
        bundle: _FakeAssetBundle(jsonEncode(sampleCities)),
      );
      final locRepo = LocationRepository(DatabaseService());
      final service = TripPlannerService(
        geminiClient: GeminiClient(dio),
        nearbyPlacesService: NearbyPlacesService(dio, locRepo),
        locationRepository: locRepo,
        cityRepository: cityRepo,
        placeSearchService: PlaceSearchService(
          dio: dio,
          cityRepository: cityRepo,
        ),
        isAiReady: true,
      );

      final plan = await service.generatePlan(
        const PlannerInput(
          destination: 'Varanasi',
          cityId: 'varanasi',
          daysCount: 3,
        ),
      );

      expect(plan.title, 'Varanasi with a friend');
      expect(plan.days.map((d) => d.dayNumber), [1, 2, 3]);
      const varanasi = LatLng(25.3176, 82.9739);
      final stops = plan.days.expand((d) => d.stops).toList();
      for (final day in plan.days) {
        expect(day.stops, isNotEmpty, reason: 'day ${day.dayNumber}');
      }
      for (final stop in stops) {
        expect(stop.placeId, isNotNull);
        expect(
          const Distance()(varanasi, stop.coordinates) / 1000,
          lessThan(40),
          reason: stop.placeName,
        );
      }
      expect(plan.days[0].stops.map((s) => s.placeName), ['Assi Ghat']);
      expect(stops.where((s) => s.placeName == 'Assi Ghat'), hasLength(1));
      // Offline there are only a few generic places, so once they're used a
      // day revisits one; nothing else repeats.
      final firstVisits = stops.where(
        (s) => !s.placeName.endsWith('Surrounds'),
      );
      expect(
        firstVisits.map((s) => s.placeId).toSet().length,
        firstVisits.length,
      );
    });
  });

  group('SavedTripsRepository (SQLite Offline Storage)', () {
    late DatabaseService dbService;
    late SavedTripsRepository repo;

    setUp(() async {
      dbService = DatabaseService();
      repo = SavedTripsRepository(dbService);
    });

    test('can save, read, and delete a TripPlan', () async {
      final plan = TripPlan(
        id: 'test-trip-save-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Weekend in Jaipur',
        destination: 'Jaipur',
        daysCount: 2,
        createdAt: DateTime.now(),
        days: [
          TripDayPlan(
            dayNumber: 1,
            title: 'Amber & Forts',
            stops: [
              TripStop(
                id: 'stop-j1',
                placeName: 'Amber Fort',
                description: 'Magnificent hill fort.',
                timeSlot: 'Morning',
                durationMinutes: 120,
                latitude: 26.9855,
                longitude: 75.8513,
                category: LocationCategory.heritage.name,
              ),
            ],
          ),
        ],
      );

      await repo.saveTrip(plan);

      final retrieved = await repo.getTrip(plan.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, plan.id);
      expect(retrieved.destination, 'Jaipur');
      expect(retrieved.days.first.stops.first.placeName, 'Amber Fort');

      final all = await repo.getAllTrips();
      expect(all.any((t) => t.id == plan.id), isTrue);

      await repo.deleteTrip(plan.id);
      final deleted = await repo.getTrip(plan.id);
      expect(deleted, isNull);
    });
  });
}
