import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/core/services/location_service.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/challenges/application/daily_challenge_service.dart';
import 'package:real_world_exploration/features/challenges/application/streak_service.dart';
import 'package:real_world_exploration/features/challenges/domain/streak_data.dart';
import 'package:real_world_exploration/features/home/home_screen.dart';
import 'package:real_world_exploration/features/locations/data/location_repository.dart';
import 'package:real_world_exploration/features/locations/data/nearby_places_service.dart';
import 'package:real_world_exploration/features/locations/data/place_photos_service.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/planner/data/opening_hours_service.dart';
import 'package:real_world_exploration/features/planner/data/saved_trips_repository.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/preferences/application/preferences_service.dart';
import 'package:real_world_exploration/features/preferences/domain/user_preferences.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/weather/application/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _here = LatLng(26.9124, 75.7873); // Jaipur

class _Gps extends LocationService {
  _Gps({this.at = _here});
  final LatLng? at;
  final asked = <bool>[];

  @override
  Future<LatLng?> getCurrentLocation({
    bool acceptRecent = false,
    Duration recentFor = const Duration(minutes: 10),
  }) async {
    asked.add(acceptRecent);
    return at;
  }

  @override
  Future<bool> requestPermission() async => true;
}

/// The online lookup, held open until the test lets it finish.
class _Lookup implements NearbyPlacesService {
  _Lookup({this.repository, this.addOnFinish, this.fail = false});
  final LocationRepository? repository;
  final List<ExploreLocation>? addOnFinish;
  final bool fail;
  final done = Completer<void>();
  var calls = 0;

  @override
  Future<int> ensureFresh(LatLng around, {bool force = false}) async {
    calls++;
    await done.future;
    if (fail) throw StateError('offline');
    if (addOnFinish != null) await repository!.insertMany(addOnFinish!);
    return addOnFinish?.length ?? 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Trips extends SavedTripsNotifier {
  @override
  Future<List<TripPlan>> build() async => const [];
}

class _Prefs extends UserPreferencesNotifier {
  @override
  Future<UserPreferences> build() async => const UserPreferences();
}

ExploreLocation _place(String id, double lat) => ExploreLocation(
  id: id,
  name: 'Place $id',
  description: 'About $id',
  latitude: lat,
  longitude: 75.79,
  category: LocationCategory.heritage,
);

void main() {
  late LocationRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('rwe_home');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    SharedPreferences.setMockInitialValues({});
    repository = LocationRepository(DatabaseService());
  });

  Future<void> pump(
    WidgetTester tester, {
    required _Lookup lookup,
    _Gps? gps,
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(gps ?? _Gps()),
          locationRepositoryProvider.overrideWithValue(repository),
          nearbyPlacesServiceProvider.overrideWithValue(lookup),
          currentWeatherProvider.overrideWith((ref) async => null),
          weatherAdvisoryProvider.overrideWith((ref, at) async => null),
          streakDataProvider.overrideWith(
            (ref) async => const StreakData(
              currentStreak: 0,
              bestStreak: 0,
              completedToday: false,
              freezesAvailable: 0,
            ),
          ),
          todayChallengeProgressProvider.overrideWith(
            (ref) => Future.error(StateError('none')),
          ),
          savedTripsListProvider.overrideWith(_Trips.new),
          userPreferencesProvider.overrideWith(_Prefs.new),
          placePhotosProvider.overrideWith((ref, _) async => const []),
          dayOpeningHoursProvider.overrideWith((ref, _) async => const {}),
          visitedPlaceIdsProvider.overrideWith((ref) async => <String>{}),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  testWidgets('saved places show at once, before the online lookup ends', (
    tester,
  ) async {
    await tester.runAsync(
      () => repository.insertMany([_place('saved', 26.92)]),
    );
    final lookup = _Lookup();
    await pump(tester, lookup: lookup);
    expect(lookup.calls, 1, reason: 'the lookup is running');
    expect(lookup.done.isCompleted, isFalse);
    // Not waiting on the internet:
    expect(find.text('Place saved'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testWidgets('new places join the list when the lookup finishes', (
    tester,
  ) async {
    await tester.runAsync(
      () => repository.insertMany([_place('saved', 26.92)]),
    );
    final lookup = _Lookup(
      repository: repository,
      addOnFinish: [_place('fresh', 26.93)],
    );
    await pump(tester, lookup: lookup);
    expect(find.text('Place fresh'), findsNothing);
    lookup.done.complete();
    // Real database work: give it time, then let the screen catch up.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }
    expect(find.text('Place saved'), findsOneWidget);
    expect(find.text('Place fresh'), findsOneWidget);
  });

  testWidgets('a new user waits on a skeleton, not a false "nothing here"', (
    tester,
  ) async {
    final lookup = _Lookup();
    await pump(tester, lookup: lookup);
    expect(find.text('Nothing here yet'), findsNothing);
    lookup.done.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('offline: saved places stay, nothing breaks', (tester) async {
    await tester.runAsync(
      () => repository.insertMany([_place('saved', 26.92)]),
    );
    final lookup = _Lookup(fail: true);
    await pump(tester, lookup: lookup);
    lookup.done.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.text('Place saved'), findsOneWidget);
    expect(find.textContaining('Could not load'), findsNothing);
  });

  testWidgets('asks for a recent position, not a fresh fix (fast start)', (
    tester,
  ) async {
    final gps = _Gps();
    await pump(tester, lookup: _Lookup(), gps: gps);
    expect(gps.asked, isNotEmpty);
    expect(gps.asked, everyElement(isTrue));
  });

  testWidgets('with no location, Around you offers to turn it on', (
    tester,
  ) async {
    await pump(tester, lookup: _Lookup(), gps: _Gps(at: null));
    expect(find.text('Location is off'), findsWidgets);
    expect(find.text('Turn on'), findsWidgets);
  });

  testWidgets('shows the search bar and the Start exploring card', (
    tester,
  ) async {
    await pump(tester, lookup: _Lookup());
    expect(find.text('Start exploring'), findsOneWidget);
    expect(find.text('Plan a trip'), findsOneWidget);
    expect(find.textContaining('Good '), findsOneWidget);
    expect(find.text('Where to next?'), findsNothing, reason: 'old headline');
  });

  testWidgets('fits a small phone with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, lookup: _Lookup(), size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('meets tap-target and label guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, lookup: _Lookup());
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
}
