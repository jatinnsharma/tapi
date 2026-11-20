import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_world_exploration/core/services/firebase_status.dart';
import 'package:real_world_exploration/features/auth/application/auth_service.dart';
import 'package:real_world_exploration/features/planner/data/saved_trips_repository.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/planner/presentation/trip_route_screen.dart';
import 'package:real_world_exploration/features/settings/presentation/settings_screen.dart';
import 'package:real_world_exploration/features/tracking/application/tracking_service.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:real_world_exploration/features/tracking/presentation/active_adventure_bar.dart';

class _FixedTracking extends TrackingService {
  _FixedTracking(this.fixed);
  final TrackingState fixed;
  @override
  TrackingState build() => fixed;
}

class _FixedTrips extends SavedTripsNotifier {
  _FixedTrips(this.trips);
  final List<TripPlan> trips;
  @override
  Future<List<TripPlan>> build() async => trips;
}

Widget _routed(Widget screen, List<Override> overrides) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(path: '/tracking', builder: (_, _) => const Text('TRACKING')),
      GoRoute(path: '/safety', builder: (_, _) => const Text('SAFETY')),
      GoRoute(path: '/trips', builder: (_, _) => const Text('TRIPS')),
      GoRoute(path: '/login', builder: (_, _) => const Text('LOGIN')),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  test('trip bar formats time and distance', () {
    expect(
      ActiveAdventureBar.formatElapsed(const Duration(seconds: 75)),
      '01:15',
    );
    expect(
      ActiveAdventureBar.formatElapsed(
        const Duration(hours: 1, minutes: 2, seconds: 3),
      ),
      '1:02:03',
    );
    expect(ActiveAdventureBar.formatKm(640), '640 m');
    expect(ActiveAdventureBar.formatKm(2345), '2.3 km');
  });

  testWidgets('no trip, no bar', (tester) async {
    await tester.pumpWidget(
      _routed(const Scaffold(bottomNavigationBar: ActiveAdventureBar()), [
        trackingServiceProvider.overrideWith(
          () => _FixedTracking(const TrackingState()),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('SOS'), findsNothing);
  });

  testWidgets('a running trip shows status, Open and SOS', (tester) async {
    final session = AdventureSession(
      id: 't',
      title: 'Ghat walk',
      startedAt: DateTime(2026, 11, 18, 9),
      status: AdventureStatus.active,
      distanceMeters: 1250,
    );
    await tester.pumpWidget(
      _routed(const Scaffold(bottomNavigationBar: ActiveAdventureBar()), [
        trackingServiceProvider.overrideWith(
          () => _FixedTracking(
            TrackingState(
              session: session,
              elapsed: const Duration(minutes: 12, seconds: 5),
            ),
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('On a trip · 12:05 · 1.3 km'), findsOneWidget);
    await tester.tap(find.text('SOS'));
    await tester.pumpAndSettle();
    expect(find.text('SAFETY'), findsOneWidget);
  });

  testWidgets('a trip that is gone says so, with a way to Trips', (
    tester,
  ) async {
    await tester.pumpWidget(
      _routed(const TripRouteScreen(tripId: 'missing'), [
        savedTripsListProvider.overrideWith(() => _FixedTrips(const [])),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trip not found'), findsOneWidget);
    await tester.tap(find.text('Go to Trips'));
    await tester.pumpAndSettle();
    expect(find.text('TRIPS'), findsOneWidget);
  });

  testWidgets('settings: signed out offers Sign in; About is always there', (
    tester,
  ) async {
    await tester.pumpWidget(
      _routed(const SettingsScreen(), [
        firebaseReadyProvider.overrideWithValue(true),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Preferences & reminders'), findsOneWidget);
    expect(find.text('Safety & SOS'), findsOneWidget);
    expect(find.text('Open-source licences'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('LOGIN'), findsOneWidget);
  });

  testWidgets('settings without accounts hides the account group', (
    tester,
  ) async {
    await tester.pumpWidget(
      _routed(const SettingsScreen(), [
        firebaseReadyProvider.overrideWithValue(false),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('ACCOUNT'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
  });
}
