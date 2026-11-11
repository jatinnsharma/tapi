import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/locations/presentation/place_sheet.dart';
import 'package:real_world_exploration/features/tracking/data/directions_service.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:real_world_exploration/features/tracking/presentation/journey_trek_breakdown.dart';

String _textOf(WidgetTester tester, Finder f) => tester
    .widgetList<Text>(find.descendant(of: f, matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    .join(' | ');

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

void main() {
  group('Formatting', () {
    test('distances', () {
      expect(formatTripDistance(0), '0 m');
      expect(formatTripDistance(850.4), '850 m');
      expect(formatTripDistance(3420), '3.42 km');
    });
    test('durations', () {
      expect(formatTripDuration(Duration.zero), '0 min');
      expect(formatTripDuration(const Duration(seconds: 40)), '<1 min');
      expect(formatTripDuration(const Duration(minutes: 12)), '12 min');
      expect(formatTripDuration(const Duration(minutes: 65)), '1h 05m');
    });
  });

  testWidgets('journey and trek are shown apart, with the total', (
    tester,
  ) async {
    final session = AdventureSession(
      id: 'a',
      title: 'Triund',
      startedAt: DateTime(2026, 10, 15, 6),
      durationSeconds: 9 * 3600 + 20 * 60,
      distanceMeters: 520000,
      journeyMeters: 501000,
      journeySeconds: 5 * 3600 + 10 * 60,
      trekMeters: 19000,
      trekSeconds: 3 * 3600 + 40 * 60,
    );
    await _pump(tester, JourneyTrekBreakdown.ofSession(session));

    final journey = _textOf(tester, find.byKey(const ValueKey('journey')));
    final trek = _textOf(tester, find.byKey(const ValueKey('trek')));
    expect(journey, contains('JOURNEY'));
    expect(journey, contains('501.00 km'));
    expect(journey, contains('5h 10m'));
    expect(trek, contains('TREK'));
    expect(trek, contains('19.00 km'));
    expect(trek, contains('3h 40m'));
    expect(find.text('Total trip: 9h 20m'), findsOneWidget);
    // Difficulty comes from the 19 km trek, not the 520 km trip.
    expect(find.text('Trek difficulty: Hard'), findsOneWidget);
  });

  testWidgets('a trip with no trek says so', (tester) async {
    await _pump(
      tester,
      const JourneyTrekBreakdown(
        journeyMeters: 4000,
        journeyTime: Duration(minutes: 10),
        trekMeters: 0,
        trekTime: Duration.zero,
        totalTime: Duration(minutes: 11),
      ),
    );
    expect(find.text('Difficulty: no trek yet'), findsOneWidget);
  });

  testWidgets('fits a narrow phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      const JourneyTrekBreakdown(
        journeyMeters: 123456,
        journeyTime: Duration(hours: 12, minutes: 34),
        trekMeters: 23456,
        trekTime: Duration(hours: 7, minutes: 8),
        totalTime: Duration(hours: 20),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  group('Planning on the place sheet', () {
    final place = ExploreLocation(
      id: 'wiki-1',
      name: 'Sukhna Lake',
      description: 'A lake.',
      latitude: 30.742,
      longitude: 76.818,
      category: LocationCategory.values.first,
      xpReward: 60,
    );

    Future<void> pumpPlan(
      WidgetTester tester,
      Future<JourneyEstimate> Function() estimate,
    ) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          journeyEstimateProvider.overrideWith((ref, _) => estimate()),
        ],
        child: MaterialApp(
          home: Scaffold(body: TripPlanCard(place: place, straightLineKm: 4.2)),
        ),
      ),
    );

    testWidgets(
      'shows the journey by car and on foot, and where the trek starts',
      (tester) async {
        await pumpPlan(
          tester,
          () async => const JourneyEstimate(
            byCar: TravelEstimate(
              meters: 5300,
              duration: Duration(minutes: 14),
            ),
            onFoot: TravelEstimate(
              meters: 4600,
              duration: Duration(minutes: 58),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = _textOf(tester, find.byKey(const ValueKey('trip-plan')));
        expect(card, contains('By car | 5.30 km | ~14 min'));
        expect(card, contains('On foot | 4.60 km | ~58 min'));
        expect(card, contains('Trek starts within 200 m of Sukhna Lake'));
      },
    );

    testWidgets('offline, it falls back to the straight-line distance', (
      tester,
    ) async {
      await pumpPlan(tester, () async => const JourneyEstimate());
      await tester.pumpAndSettle();
      expect(
        find.textContaining('About 4.2 km away in a straight line'),
        findsOneWidget,
      );
    });
  });
}
