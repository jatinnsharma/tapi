// The live trip screen when heading to a place: Google Maps-style navigation.
// The map fills the screen, the next turn is a banner on top, and time,
// distance, Pause and Finish sit in a bottom sheet that pulls up for details.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/features/memories/data/memory_repository.dart';
import 'package:real_world_exploration/features/memories/domain/memory_model.dart';
import 'package:real_world_exploration/features/profile/application/rank_style_service.dart';
import 'package:real_world_exploration/features/profile/domain/rank_style.dart';
import 'package:real_world_exploration/features/tracking/application/tracking_service.dart';
import 'package:real_world_exploration/features/tracking/data/directions_service.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:real_world_exploration/features/tracking/domain/checkpoint.dart';
import 'package:real_world_exploration/features/tracking/domain/directions.dart';
import 'package:real_world_exploration/features/tracking/domain/route_point.dart';
import 'package:real_world_exploration/features/tracking/domain/trip_split.dart';
import 'package:real_world_exploration/features/tracking/presentation/live_trip_card.dart';
import 'package:real_world_exploration/features/tracking/presentation/tracking_screen.dart';
import 'package:real_world_exploration/features/weather/application/weather_service.dart';

const _place = Destination(
  id: 'p',
  name: 'Sukhna Lake',
  latitude: 30.7420,
  longitude: 76.8180,
  xpReward: 60,
);

/// Start → left turn → right turn (soon after) → the lake.
final _route = RouteDirections(
  distanceMeters: 800,
  durationSeconds: 600,
  path: const [
    LatLng(30.7400, 76.8100),
    LatLng(30.7400, 76.8150),
    LatLng(30.7407, 76.8150),
    LatLng(30.7420, 76.8180),
  ],
  steps: const [
    DirectionStep(
      instruction: 'Head east on Madhya Marg',
      icon: Icons.arrow_upward_rounded,
      location: LatLng(30.7400, 76.8100),
      distanceMeters: 480,
    ),
    DirectionStep(
      instruction: 'Turn left onto Lake Road',
      icon: Icons.turn_left_rounded,
      location: LatLng(30.7400, 76.8150),
      distanceMeters: 80, // The next turn comes right after: "Then".
    ),
    DirectionStep(
      instruction: 'Turn right onto Sukhna Path',
      icon: Icons.turn_right_rounded,
      location: LatLng(30.7407, 76.8150),
      distanceMeters: 300,
    ),
    DirectionStep(
      instruction: 'You have arrived at Sukhna Lake',
      icon: Icons.flag_rounded,
      location: LatLng(30.7420, 76.8180),
      distanceMeters: 0,
    ),
  ],
);

class _TripInProgress extends TrackingService {
  _TripInProgress({this.phase = TripPhase.trekking, this.pending});
  final TripPhase phase;
  final Checkpoint? pending;

  @override
  TrackingState build() {
    final now = DateTime.now();
    return TrackingState(
      session: AdventureSession(
        id: 'trip',
        title: 'Sukhna Lake',
        startedAt: now.subtract(const Duration(minutes: 20)),
        journeyMeters: 2900,
        journeySeconds: 700,
        trekMeters: 400,
        trekSeconds: 300,
        xpEarned: 0,
      ),
      destination: _place,
      phase: phase,
      pendingArrival: pending,
      elapsed: const Duration(minutes: 20),
      routePoints: [
        RoutePoint(
          adventureId: 'trip',
          latitude: 30.7395,
          longitude: 76.8060,
          timestamp: now,
        ),
        RoutePoint(
          adventureId: 'trip',
          latitude: 30.7400,
          longitude: 76.8100,
          timestamp: now,
        ),
      ],
    );
  }
}

class _NoMemories extends MemoryRepository {
  _NoMemories() : super(DatabaseService());
  @override
  Future<List<Memory>> getByAdventure(String adventureId) async => const [];
}

/// Pumps the screen. With [route] null, directions stay loading.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  RouteDirections? route,
  TripPhase phase = TripPhase.trekking,
  Checkpoint? pending,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      trackingServiceProvider.overrideWith(
        () => _TripInProgress(phase: phase, pending: pending),
      ),
      memoryRepositoryProvider.overrideWithValue(_NoMemories()),
      currentWeatherProvider.overrideWith((ref) async => null),
      rankStyleProvider.overrideWith(
        (ref) async => StyleState(totalXp: 0, equipped: rankStyles.first),
      ),
      routeToDestinationProvider.overrideWith((ref, d) {
        ref.watch(travelModeProvider); // Like the real one: refetch on change.
        return route == null
            ? Completer<RouteDirections>().future
            : Future.value(route);
      }),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: TrackingScreen(title: 'Sukhna Lake', destination: _place),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

void main() {
  for (final size in const [Size(390, 844), Size(360, 640), Size(412, 915)]) {
    testWidgets(
      'on a ${size.width.round()}x${size.height.round()} phone the map fills '
      'the screen with the turn on top and Pause/Finish below',
      (tester) async {
        await _pump(tester, size: size, route: _route);

        final map = tester.getRect(find.byType(FlutterMap));
        expect(map.size, size);

        final banner = tester.getRect(find.byKey(const ValueKey('nav-banner')));
        expect(banner.top, lessThan(size.height * 0.1));

        for (final label in ['Finish', 'Pause']) {
          expect(find.text(label), findsOneWidget);
          final r = tester.getRect(find.text(label));
          expect(r.bottom, lessThanOrEqualTo(size.height));
          expect(r.top, greaterThan(size.height * 0.6));
        }
      },
    );
  }

  testWidgets('shows the next turn, its distance and what comes then', (
    tester,
  ) async {
    await _pump(tester, route: _route);
    expect(find.text('Turn left onto Lake Road'), findsOneWidget);
    // About 480 m along the route to the turn.
    expect(find.textContaining(RegExp(r'^4\d0 m$')), findsOneWidget);
    expect(find.text('Then'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('nav-banner')),
        matching: find.byIcon(Icons.turn_right_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the sheet shows time left, distance and arrival time', (
    tester,
  ) async {
    await _pump(tester, route: _route);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('nav-eta'))).data,
      matches(RegExp(r'^\d+ min$')),
    );
    expect(find.textContaining('Arrive '), findsOneWidget);
  });

  testWidgets('while the route loads, the banner says so', (tester) async {
    await _pump(tester);
    expect(find.text('Finding the best route…'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
  });

  testWidgets('pulling the sheet up shows directions and the trip card', (
    tester,
  ) async {
    await _pump(tester, route: _route);
    await tester.drag(find.text('Pause'), const Offset(0, -600));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Directions ·'), findsOneWidget);
    expect(find.text('2. Turn left onto Lake Road'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(LiveTripCard),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text("You're trekking"), findsOneWidget);
  });

  testWidgets('switching to driving asks for a driving route', (tester) async {
    final container = await _pump(tester, route: _route);
    expect(container.read(travelModeProvider), isNull); // Automatic.
    await tester.tap(find.byIcon(Icons.directions_car_rounded));
    await tester.pump();
    expect(container.read(travelModeProvider), TravelMode.car);
    // The new route loads and guidance starts over.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Turn left onto Lake Road'), findsOneWidget);
  });

  testWidgets('route overview shows Re-centre, which goes back to following', (
    tester,
  ) async {
    await _pump(tester, route: _route);
    expect(find.text('Re-centre'), findsNothing);
    await tester.tap(find.byTooltip('Route overview'));
    await tester.pump();
    expect(find.text('Re-centre'), findsOneWidget);
    await tester.tap(find.text('Re-centre'));
    await tester.pump();
    expect(find.text('Re-centre'), findsNothing);
  });

  testWidgets('arriving asks for the photo right in the banner', (
    tester,
  ) async {
    await _pump(
      tester,
      route: _route,
      pending: const Checkpoint(
        id: 'dest-p@trip',
        adventureId: 'trip',
        name: 'Sukhna Lake',
        latitude: 30.7420,
        longitude: 76.8180,
      ),
    );
    expect(find.text("You've arrived at Sukhna Lake"), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
  });

  for (final phase in TripPhase.values) {
    testWidgets('navigation works during ${phase.name}', (tester) async {
      await _pump(tester, route: _route, phase: phase);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
    });
  }

  test('directions drive beyond 2.5 km and walk closer, unless picked', () {
    const here = LatLng(30.7333, 76.7794);
    expect(
      autoTravelMode(here, const LatLng(30.7420, 76.8180)),
      TravelMode.car,
    );
    expect(
      autoTravelMode(here, const LatLng(30.7400, 76.7800)),
      TravelMode.foot,
    );
  });
}
