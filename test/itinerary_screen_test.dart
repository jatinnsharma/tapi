import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/locations/data/place_photos_service.dart';
import 'package:real_world_exploration/features/planner/data/opening_hours_service.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/planner/presentation/itinerary_detail_screen.dart';
import 'package:real_world_exploration/features/tracking/data/directions_service.dart';

TripStop _stop(String id, String name, {bool done = false}) => TripStop(
  id: id,
  placeName: name,
  description: 'About $name.',
  timeSlot: 'Morning',
  durationMinutes: 60,
  latitude: 25.3,
  longitude: 83.0,
  category: 'heritage',
  isCompleted: done,
  xpReward: 70,
);

final _plan = TripPlan(
  id: 't1',
  title: 'Varanasi',
  destination: 'Varanasi',
  daysCount: 2,
  createdAt: DateTime(2026, 11, 1),
  days: [
    TripDayPlan(
      dayNumber: 1,
      title: 'The ghats',
      stops: [
        _stop('a', 'Assi Ghat', done: true),
        _stop('b', 'Kashi Vishwanath'),
        _stop('c', 'Dashashwamedh Ghat'),
      ],
      foodSuggestions: const ['Kachori at Ram Bhandar'],
    ),
    const TripDayPlan(dayNumber: 2, title: 'Sarnath', stops: []),
  ],
);

/// No network: routing fails, so the map falls back to straight lines.
class _NoRoutes extends Fake implements DirectionsService {}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dayOpeningHoursProvider.overrideWith((ref, _) async => const {}),
        placePhotosProvider.overrideWith((ref, _) async => const []),
        directionsServiceProvider.overrideWithValue(_NoRoutes()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: ItineraryDetailScreen(plan: _plan),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('one main action: go to the next stop not done', (tester) async {
    await _pump(tester);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Essentials'), findsOneWidget);
    expect(find.text('Saved on this phone'), findsOneWidget);
    expect(find.text('Go to stop 2: Kashi Vishwanath'), findsOneWidget);
    expect(find.text('+70 XP when you get there'), findsOneWidget);
    // No per-row Go buttons or tiny reorder icons any more.
    expect(find.textContaining('XP · Go'), findsNothing);
    expect(find.byTooltip('Move up'), findsNothing);
    // Rows are comfortably tappable.
    final row = find.byKey(const ValueKey('stop-b'));
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
  });

  testWidgets('a stop opens a sheet with its details and edits', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('stop-b')));
    await tester.pumpAndSettle();
    expect(find.text('About Kashi Vishwanath.'), findsOneWidget);
    expect(find.text('Mark done'), findsOneWidget);
    expect(find.text('Move earlier'), findsOneWidget);
    expect(find.text('Move later'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Go here · +70 XP'), findsOneWidget);
  });

  testWidgets('an empty day offers to plan it, with no dead Go button', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Day 2'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nothing planned for this day'), findsOneWidget);
    expect(find.text('Plan this day'), findsOneWidget);
    expect(find.textContaining('Go to stop'), findsNothing);
  });

  testWidgets('meets tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('fits a 320 dp phone at 1.3x text without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
