import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/services/location_service.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/locations/data/location_repository.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/map/map_pin.dart';
import 'package:real_world_exploration/features/map/map_screen.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/wishlist/application/wishlist_service.dart';

class _NoGps extends LocationService {
  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<LatLng?> getCurrentLocation({
    bool acceptRecent = false,
    Duration recentFor = const Duration(minutes: 10),
  }) async => null;

  @override
  Stream<LatLng> getLocationStream() => const Stream.empty();
}

class _Places extends Fake implements LocationRepository {
  _Places(this.places);

  final List<ExploreLocation> places;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<List<ExploreLocation>> getAll() async => places;

  @override
  Future<void> markDiscovered(String id) async {}
}

Future<void> _pumpMap(WidgetTester tester, List<ExploreLocation> places) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(_NoGps()),
        locationRepositoryProvider.overrideWithValue(_Places(places)),
        visitedPlaceIdsProvider.overrideWith((ref) async => <String>{}),
        wishlistKeysProvider.overrideWith((ref) async => <String>{}),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const MapScreen()),
    ),
  );
  // Let _init finish; map tiles never load in tests, so don't settle.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('one Layers button replaces the row of mystery icons', (
    tester,
  ) async {
    await _pumpMap(tester, const []);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Layers'), findsOneWidget);
    expect(find.byTooltip('Discover Nearby Places with AI'), findsNothing);
    expect(find.byTooltip('Map view'), findsNothing);

    await tester.tap(find.text('Layers'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Map layers'), findsOneWidget);
    for (final mode in ['Nearby', 'Everything', 'Mine', 'Friends']) {
      expect(find.text(mode), findsOneWidget);
    }
    expect(find.text('Places to eat'), findsOneWidget);
    expect(
      find.text('WHAT THE PINS MEAN', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('without a location fix, the map says so', (tester) async {
    await _pumpMap(tester, const []);
    expect(find.text('Location is off'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);
    // Voice notes need sign-in and a server: hidden, not broken.
    expect(find.byTooltip('Leave a voice note here'), findsNothing);
  });

  testWidgets('pins are 44 px and say what they are', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: MapPin.visited(
              icon: Icons.water_rounded,
              label: 'Sukhna Lake',
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(MapPin)), const Size(44, 44));
    expect(find.bySemanticsLabel('Sukhna Lake, visited'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Unknown place'),
      findsNothing,
      reason: 'labels come from the pin, not a generic icon',
    );
  });
}
