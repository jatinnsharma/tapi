import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, CachingAssetBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/explore/data/city_repository.dart';
import 'package:real_world_exploration/features/explore/presentation/city_detail_screen.dart';
import 'package:real_world_exploration/features/locations/data/location_repository.dart';
import 'package:real_world_exploration/features/locations/data/nearby_places_service.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/map/map_focus.dart';
import 'package:real_world_exploration/features/weather/application/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The bundled city list, in memory (one city), so tests don't depend on
/// Flutter's asset loading.
class _Cities extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(
      jsonEncode([
        {
          'id': 'new-delhi',
          'name': 'New Delhi',
          'state': 'Delhi',
          'latitude': 28.6139,
          'longitude': 77.209,
          'blurb': "India's vibrant capital.",
          'imageUrl': 'https://example.com/delhi.jpg',
          'category': 'metropolis',
        },
      ]),
    );
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

class _Lookup implements NearbyPlacesService {
  _Lookup({this.repository, this.add, this.fail = false});
  final LocationRepository? repository;
  final List<ExploreLocation>? add;
  bool fail;
  var done = Completer<void>();
  var calls = 0;
  final forced = <bool>[];

  @override
  Future<int> ensureFresh(LatLng around, {bool force = false}) async {
    calls++;
    forced.add(force);
    await done.future;
    if (fail) throw StateError('offline');
    if (add != null) await repository!.insertMany(add!);
    return add?.length ?? 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ExploreLocation _place(String id, double lat, {LocationCategory? c}) =>
    ExploreLocation(
      id: id,
      name: 'Place $id',
      description: 'About $id',
      latitude: lat,
      longitude: 77.209,
      category: c ?? LocationCategory.heritage,
    );

/// Scrolls the city page until [target] is on screen (the list is lazy).
Future<void> _see(WidgetTester tester, Finder target) => tester
    .scrollUntilVisible(target, 300, scrollable: find.byType(Scrollable).first);

Future<void> _wait(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: ms ~/ 4)),
    );
    await tester.pump();
  }
}

void main() {
  late LocationRepository repository;
  late ProviderContainer container;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('rwe_city');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    SharedPreferences.setMockInitialValues({});
    repository = LocationRepository(DatabaseService());
  });

  Future<GoRouter> pump(
    WidgetTester tester, {
    required _Lookup lookup,
    String cityId = 'new-delhi',
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        cityRepositoryProvider.overrideWithValue(
          CityRepository(bundle: _Cities()),
        ),
        locationRepositoryProvider.overrideWithValue(repository),
        nearbyPlacesServiceProvider.overrideWithValue(lookup),
        weatherAdvisoryProvider.overrideWith((ref, at) async => null),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/city/$cityId'),
              child: const Text('open city'),
            ),
          ),
        ),
        GoRoute(
          path: '/city/:id',
          builder: (_, s) => CityDetailScreen(cityId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/trip-planner',
          builder: (_, s) => Scaffold(
            body: Text(
              'PLANNER ${s.uri.queryParameters['destination']} '
              '${s.uri.queryParameters['cityId']}',
            ),
          ),
        ),
        GoRoute(path: '/map', builder: (_, _) => const Text('MAP')),
        GoRoute(path: '/explore', builder: (_, _) => const Text('EXPLORE')),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.tap(find.text('open city'));
    await tester.pump();
    // The city comes from a bundled file: wait until the page has drawn
    // (or shown its "not found" card).
    for (var i = 0; i < 40; i++) {
      await _wait(tester, 100);
      if (find.byType(Scrollable).evaluate().isNotEmpty ||
          find.text('City not found').evaluate().isNotEmpty) {
        break;
      }
    }
    await _wait(tester);
    return router;
  }

  testWidgets('the city and its saved places show before the lookup ends', (
    tester,
  ) async {
    await tester.runAsync(
      () => repository.insertMany([_place('saved', 28.62)]),
    );
    final lookup = _Lookup();
    await pump(tester, lookup: lookup);
    expect(lookup.done.isCompleted, isFalse, reason: 'still looking online');
    expect(find.text('New Delhi'), findsWidgets);
    expect(find.textContaining('vibrant capital'), findsOneWidget);
    await _see(tester, find.text('Place saved'));
    expect(find.text('Place saved'), findsOneWidget);
    expect(find.text('Places to explore (1)'), findsOneWidget);
  });

  testWidgets('new places join when the lookup finishes', (tester) async {
    final lookup = _Lookup(
      repository: repository,
      add: [_place('fresh', 28.63)],
    );
    await pump(tester, lookup: lookup);
    await _see(tester, find.byType(CircularProgressIndicator));
    // Nothing saved yet: a spinner, not "no places".
    expect(find.textContaining('No places found'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    lookup.done.complete();
    await _wait(tester, 1200);
    await _see(tester, find.text('Place fresh'));
    expect(find.text('Place fresh'), findsOneWidget);
  });

  testWidgets('offline with nothing saved: says so and can retry', (
    tester,
  ) async {
    final lookup = _Lookup(fail: true);
    await pump(tester, lookup: lookup);
    lookup.done.complete();
    await _wait(tester);
    await _see(tester, find.text('Try again'));
    expect(find.textContaining("Couldn't look up places"), findsOneWidget);
    // Trying again looks again, forced.
    lookup.done = Completer<void>()..complete();
    await tester.tap(find.text('Try again'));
    await _wait(tester);
    expect(lookup.calls, 2);
    expect(lookup.forced.last, isTrue);
  });

  testWidgets('offline with saved places: they stay, no scary message', (
    tester,
  ) async {
    await tester.runAsync(
      () => repository.insertMany([_place('saved', 28.62)]),
    );
    final lookup = _Lookup(fail: true);
    await pump(tester, lookup: lookup);
    lookup.done.complete();
    await _wait(tester);
    await _see(tester, find.text('Place saved'));
    expect(find.text('Place saved'), findsOneWidget);
    expect(find.textContaining("Couldn't look up"), findsNothing);
  });

  testWidgets('an unknown city says so and goes back to Explore', (
    tester,
  ) async {
    await pump(tester, lookup: _Lookup(), cityId: 'atlantis');
    expect(find.text('City not found'), findsOneWidget);
    await tester.tap(find.text('Back to Explore'));
    await tester.pumpAndSettle();
    // Went back to where it came from.
    expect(find.text('open city'), findsOneWidget);
  });

  testWidgets('a category with nothing offers to show all places', (
    tester,
  ) async {
    await tester.runAsync(
      () => repository.insertMany([_place('temple', 28.62)]),
    );
    final lookup = _Lookup()..done.complete();
    await pump(tester, lookup: lookup);
    await _see(tester, find.text('Lake'));
    await tester.tap(find.text('Lake'));
    await tester.pump();
    await _see(tester, find.textContaining('No lake places'));
    expect(find.textContaining('No lake places'), findsOneWidget);
    await tester.tap(find.text('Show all places'));
    await tester.pump();
    await _see(tester, find.text('Place temple'));
    expect(find.text('Place temple'), findsOneWidget);
  });

  testWidgets('Plan a trip opens the planner with the city, and leaves '
      'Explore alone', (tester) async {
    final lookup = _Lookup()..done.complete();
    await pump(tester, lookup: lookup);
    await tester.ensureVisible(find.text('Plan a trip to New Delhi'));
    await tester.tap(find.text('Plan a trip to New Delhi'));
    await tester.pumpAndSettle();
    expect(find.text('PLANNER New Delhi new-delhi'), findsOneWidget);
    expect(container.read(selectedCityProvider), isNull);
  });

  testWidgets('Explore on Map focuses the map on the city, and leaves '
      'Explore alone', (tester) async {
    final lookup = _Lookup()..done.complete();
    await pump(tester, lookup: lookup);
    await tester.tap(find.byTooltip('Explore on Map'));
    await tester.pumpAndSettle();
    expect(find.text('MAP'), findsOneWidget);
    final focus = container.read(mapFocusProvider);
    expect(focus?.center.latitude, closeTo(28.6139, 0.001));
    expect(container.read(selectedCityProvider), isNull);
  });

  testWidgets('the photo buttons are labelled and 48 dp', (tester) async {
    final semantics = tester.ensureSemantics();
    final lookup = _Lookup()..done.complete();
    await pump(tester, lookup: lookup);
    expect(
      tester.getSize(find.byTooltip('Back')).shortestSide,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byTooltip('Explore on Map')).shortestSide,
      greaterThanOrEqualTo(48),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('fits a small phone with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(
      () => repository.insertMany([_place('saved', 28.62)]),
    );
    final lookup = _Lookup()..done.complete();
    await pump(tester, lookup: lookup, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });
}
