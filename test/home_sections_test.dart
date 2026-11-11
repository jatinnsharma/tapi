import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/home/around_you_section.dart';
import 'package:real_world_exploration/features/locations/data/place_photos_service.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/planner/data/opening_hours_service.dart';
import 'package:real_world_exploration/features/planner/data/saved_trips_repository.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/planner/presentation/trip_home_card.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/weather/data/weather_repository.dart';
import 'package:real_world_exploration/features/weather/domain/weather_model.dart';

TripStop _stop(String id, String name, {bool done = false}) => TripStop(
  id: id,
  placeName: name,
  description: '',
  timeSlot: 'Morning',
  durationMinutes: 60,
  latitude: 25.31,
  longitude: 83.01,
  category: 'heritage',
  isCompleted: done,
);

TripPlan _trip(
  String id, {
  DateTime? start,
  int days = 3,
  DateTime? created,
  List<TripStop> day1 = const [],
}) => TripPlan(
  id: id,
  title: 'Trip $id',
  destination: 'Varanasi',
  daysCount: days,
  startDate: start,
  createdAt: created ?? DateTime(2026, 10, 1),
  days: [
    for (var d = 1; d <= days; d++)
      TripDayPlan(
        dayNumber: d,
        title: 'Day $d plan',
        stops: d == 1 ? day1 : [_stop('s$id$d', 'Stop $d')],
      ),
  ],
);

final _now = DateTime(2026, 10, 18, 10);

class _Trips extends SavedTripsNotifier {
  _Trips(this.trips);
  final List<TripPlan> trips;
  @override
  Future<List<TripPlan>> build() async => trips;
}

class _NoWeather extends WeatherRepository {
  _NoWeather() : super(Dio());
  @override
  Future<List<DailyForecast>?> getDailyForecast(
    double latitude,
    double longitude, {
    required DateTime start,
    required int days,
  }) async => null;
}

ExploreLocation _place(String id, LocationCategory c, double lat) =>
    ExploreLocation(
      id: id,
      name: 'Place $id',
      category: c,
      description: '',
      latitude: lat,
      longitude: 83.0,
    );

void main() {
  group('which trip Home shows', () {
    test('a trip on today wins, with today\'s day', () {
      final picked = pickHomeTrip([
        _trip('soon', start: DateTime(2026, 10, 25)),
        _trip('now', start: DateTime(2026, 10, 17)),
      ], _now)!;
      expect(picked.plan.id, 'now');
      expect(picked.kind, HomeTripKind.today);
      expect(picked.dayIndex, 1); // Started yesterday: Day 2.
    });

    test('otherwise the soonest coming up', () {
      final picked = pickHomeTrip([
        _trip('later', start: DateTime(2026, 12, 1)),
        _trip('soon', start: DateTime(2026, 10, 21)),
        _trip('past', start: DateTime(2026, 9, 1)),
      ], _now)!;
      expect(picked.plan.id, 'soon');
      expect(picked.kind, HomeTripKind.upcoming);
      expect(picked.daysAway, 3);
    });

    test('otherwise the latest one being planned, if recent', () {
      final picked = pickHomeTrip([
        _trip('old', created: DateTime(2026, 5, 1)),
        _trip('a', created: DateTime(2026, 10, 10)),
        _trip('b', created: DateTime(2026, 10, 15)),
      ], _now)!;
      expect(picked.plan.id, 'b');
      expect(picked.kind, HomeTripKind.planning);
      expect(
        pickHomeTrip([_trip('old', created: DateTime(2026, 5, 1))], _now),
        isNull,
      );
    });

    test('past trips and no trips: nothing', () {
      expect(pickHomeTrip([], _now), isNull);
      expect(
        pickHomeTrip([_trip('past', start: DateTime(2026, 9, 1))], _now),
        isNull,
      );
    });
  });

  group('your trip card', () {
    Future<void> pump(WidgetTester tester, List<TripPlan> trips) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedTripsListProvider.overrideWith(() => _Trips(trips)),
            placePhotosProvider.overrideWith((ref, key) async => const []),
            dayOpeningHoursProvider.overrideWith(
              (ref, key) async => const {'next': 'Mo-Su 06:00-21:00'},
            ),
            weatherRepositoryProvider.overrideWithValue(_NoWeather()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: TripHomeCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('no trips: an invitation to plan one', (tester) async {
      await pump(tester, const []);
      expect(find.text('Plan a trip anywhere in India'), findsOneWidget);
      expect(find.text('Plan a trip'), findsOneWidget);
      expect(find.text('All trips'), findsNothing);
    });

    testWidgets('on a trip day: the next stop, its hours and Go', (
      tester,
    ) async {
      final today = DateTime.now();
      await pump(tester, [
        _trip(
          't',
          start: DateTime(today.year, today.month, today.day),
          day1: [
            _stop('done', 'Assi Ghat', done: true),
            _stop('next', 'Kashi Vishwanath Temple'),
          ],
        ),
      ]);
      expect(find.text('Your trip today'), findsOneWidget);
      expect(find.text('Kashi Vishwanath Temple'), findsOneWidget);
      expect(find.text('1 of 2 stops done'), findsOneWidget);
      expect(find.text('Go'), findsOneWidget);
      expect(find.textContaining('6 AM – 9 PM'), findsOneWidget);
    });

    testWidgets('coming up: countdown and packing', (tester) async {
      final today = DateTime.now();
      await pump(tester, [
        _trip('t', start: DateTime(today.year, today.month, today.day + 3)),
      ]);
      expect(find.text('Varanasi in 3 days'), findsOneWidget);
      expect(find.textContaining('packed'), findsOneWidget);
      expect(find.text('Packing & budget'), findsOneWidget);
    });

    testWidgets('no dates yet: keep planning', (tester) async {
      await pump(tester, [_trip('t', created: DateTime.now())]);
      expect(find.text('KEEP PLANNING'), findsOneWidget);
      expect(find.text('Varanasi · 3 days'), findsOneWidget);
    });
  });

  group('around you', () {
    const here = LatLng(25.30, 83.0);
    final places = [
      _place('temple', LocationCategory.heritage, 25.301), // ~0.1 km
      _place('lake', LocationCategory.lake, 25.32), // ~2 km
      _place('cafe', LocationCategory.food, 25.40), // ~11 km
      _place('far', LocationCategory.heritage, 25.60), // ~33 km
    ];

    Future<void> pump(
      WidgetTester tester, {
      bool hasLocation = true,
      Map<String, String> hours = const {},
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            placePhotosProvider.overrideWith((ref, key) async => const []),
            dayOpeningHoursProvider.overrideWith((ref, key) async => hours),
            visitedPlaceIdsProvider.overrideWith((ref) async => const {}),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AroundYouSection(
                current: here,
                hasLocation: hasLocation,
                places: places,
                loading: false,
                fetchFailed: false,
                onFindNearby: () {},
                onTurnOnLocation: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('nearest first within the distance, chips filter', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Place temple'), findsOneWidget);
      expect(find.text('Place lake'), findsOneWidget);
      expect(find.text('Place cafe'), findsOneWidget);
      expect(find.text('Place far'), findsNothing); // Beyond 15 km.

      await tester.tap(find.text('Nature'));
      await tester.pump();
      expect(find.text('Place lake'), findsOneWidget);
      expect(find.text('Place temple'), findsNothing);

      // No photo spots around: no chip for them.
      expect(find.text('Photo spots'), findsNothing);
    });

    testWidgets('a wider distance brings in farther places', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Within 15 km'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Within 50 km').last);
      await tester.pumpAndSettle();
      expect(find.text('Place far'), findsOneWidget);
    });

    testWidgets('shows whether a place is open now', (tester) async {
      await pump(tester, hours: const {'temple': '24/7'});
      expect(find.textContaining('Open now'), findsOneWidget);
    });

    testWidgets('location off: turn it on or pick a city', (tester) async {
      await pump(tester, hasLocation: false);
      expect(find.text('Location is off'), findsOneWidget);
      expect(find.text('Pick a city'), findsOneWidget);
      expect(find.text('Place temple'), findsNothing);
    });

    test('filters group the app\'s categories', () {
      expect(AroundFilter.nature.matches(LocationCategory.waterfall), isTrue);
      expect(AroundFilter.photo.matches(LocationCategory.viewpoint), isTrue);
      expect(AroundFilter.gems.matches(LocationCategory.mystery), isTrue);
      expect(AroundFilter.heritage.matches(LocationCategory.food), isFalse);
      expect(AroundFilter.all.matches(LocationCategory.city), isTrue);
    });
  });
}
