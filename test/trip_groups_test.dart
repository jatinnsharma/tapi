import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/planner/domain/trip_groups.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/planner/presentation/my_trips_screen.dart';

TripPlan _trip(String id, {DateTime? start, int days = 3, int done = 0}) =>
    TripPlan(
      id: id,
      title: id,
      destination: id,
      daysCount: days,
      startDate: start,
      createdAt: DateTime(2026, 1, int.parse(id.substring(1))),
      days: [
        for (var d = 0; d < days; d++)
          TripDayPlan(
            dayNumber: d + 1,
            title: 'Day',
            stops: [
              for (var i = 0; i < 2; i++)
                TripStop(
                  id: '$id-$d-$i',
                  placeName: 'Stop',
                  description: '',
                  timeSlot: 'Morning',
                  durationMinutes: 60,
                  latitude: 0,
                  longitude: 0,
                  category: 'heritage',
                  isCompleted: d * 2 + i < done,
                ),
            ],
          ),
      ],
    );

void main() {
  final now = DateTime(2026, 11, 18, 15);

  test('trips fall into now, upcoming, undated and past', () {
    final groups = groupTrips([
      _trip('t1', start: DateTime(2026, 11, 10)), // ended 12 Nov
      _trip('t2', start: DateTime(2026, 11, 17)), // 17–19 Nov: now
      _trip('t3'), // no dates
      _trip('t4', start: DateTime(2026, 12, 20)),
      _trip('t5', start: DateTime(2026, 12, 1)),
      _trip('t6', start: DateTime(2026, 11, 1)),
    ], now);
    expect(groups.keys, [
      TripGroup.now,
      TripGroup.upcoming,
      TripGroup.undated,
      TripGroup.past,
    ]);
    expect(groups[TripGroup.now]!.map((t) => t.id), ['t2']);
    expect(groups[TripGroup.upcoming]!.map((t) => t.id), ['t5', 't4']);
    expect(groups[TripGroup.past]!.map((t) => t.id), ['t1', 't6']);
  });

  test('the last day still counts as now; the day after is past', () {
    final trip = _trip('t1', start: DateTime(2026, 11, 16));
    expect(groupOf(trip, now), TripGroup.now);
    expect(groupOf(trip, DateTime(2026, 11, 19)), TripGroup.past);
  });

  testWidgets('a trip card shows dates, progress and a menu for delete', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TripCard(
              plan: _trip('t1', start: DateTime(2026, 11, 17), done: 2),
              onOpen: () {},
              onDelete: () => deleted = true,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('17 Nov – 19 Nov'), findsOneWidget);
    expect(find.text('2 of 6 stops done'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    await tester.tap(find.byTooltip('Trip options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete trip'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });
}
