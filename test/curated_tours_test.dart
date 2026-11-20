import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/auth/application/auth_service.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/tours/data/tour_repository.dart';
import 'package:real_world_exploration/features/tours/domain/curated_tour.dart';
import 'package:real_world_exploration/features/tours/presentation/tour_detail_screen.dart';

TripStop _stop(String id, {double lng = 83.0}) => TripStop(
  id: id,
  placeName: 'Place $id',
  description: '',
  timeSlot: 'Morning',
  durationMinutes: 60,
  latitude: 25.3,
  longitude: lng,
  category: 'heritage',
  placeId: 'wiki-$id',
  tip: 'Tip $id',
);

final _tour = CuratedTour(
  id: 't1',
  creatorUid: 'author',
  creatorName: 'Asha',
  cityId: 'varanasi',
  cityName: 'Varanasi',
  title: 'Ghats at dawn',
  description: 'Sunrise walk along the river.',
  stops: const [
    TourStop(name: 'Assi Ghat', latitude: 25.2900, longitude: 83.0060),
    TourStop(name: 'Tulsi Ghat', latitude: 25.2950, longitude: 83.0080),
    TourStop(
      name: 'Dashashwamedh Ghat',
      latitude: 25.3060,
      longitude: 83.0100,
      tip: 'Stay for the evening aarti.',
    ),
  ],
  createdAt: DateTime(2026, 11, 1),
);

void main() {
  test('only stops reached on counted trips can be published', () {
    final day = TripDayPlan(
      dayNumber: 1,
      title: 'Ghats',
      stops: [_stop('a'), _stop('b'), _stop('c'), _stop('d')],
    );
    final verified = verifiedTourStops(day, {
      'wiki-a',
      'wiki-c',
      'wiki-d',
    }, (s) => s.placeId!);
    expect(verified.map((s) => s.id), ['a', 'c', 'd']);
  });

  test('a tour round-trips through its Firestore shape', () {
    final map = {..._tour.toMap(), 'createdAt': _tour.createdAt};
    expect(map.containsKey('id'), isFalse);
    expect(
      (map['stops'] as List).last,
      containsPair('tip', 'Stay for the evening aarti.'),
    );
    expect((map['stops'] as List).first, isNot(contains('tip')));
    final back = CuratedTour.fromMap('t1', map);
    expect(back.title, _tour.title);
    expect(back.stops.map((s) => s.name), _tour.stops.map((s) => s.name));
    expect(back.createdAt, _tour.createdAt);
  });

  test('distance stop to stop, and average stars', () {
    expect(_tour.stopToStopKm, closeTo(1.85, 0.2));
    expect(averageStars(const []), isNull);
    expect(
      averageStars(const [
        TourRating(uid: 'a', name: 'A', stars: 5),
        TourRating(uid: 'b', name: 'B', stars: 4),
      ]),
      4.5,
    );
    // Out-of-range stars from bad data are clamped.
    expect(TourRating.fromMap('x', {'stars': 9}).stars, 5);
  });

  test('"Plan this tour" makes a one-day plan with every stop', () {
    final plan = tourAsTripPlan(_tour, now: DateTime(2026, 11, 17));
    expect(plan.daysCount, 1);
    expect(plan.cityId, 'varanasi');
    expect(plan.destination, 'Varanasi');
    final stops = plan.days.single.stops;
    expect(stops.map((s) => s.placeName), [
      'Assi Ghat',
      'Tulsi Ghat',
      'Dashashwamedh Ghat',
    ]);
    expect(stops.map((s) => s.timeSlot), ['Morning', 'Morning', 'Afternoon']);
    expect(stops.last.tip, 'Stay for the evening aarti.');
    expect(plan.overview, contains('by Asha'));
  });

  testWidgets('tour page: stops, rating and plan button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          tourRatingsProvider.overrideWith(
            (ref, id) async => const [
              TourRating(uid: 'r', name: 'Ravi', stars: 4, review: 'Lovely'),
            ],
          ),
        ],
        child: MaterialApp(home: TourDetailScreen(tour: _tour)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Ghats at dawn'), findsOneWidget);
    expect(find.textContaining('★ 4.0 (1 rating)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Plan this tour'), 200);
    expect(find.text('Dashashwamedh Ghat'), findsOneWidget);
    expect(find.text('Plan this tour'), findsOneWidget);
    // Signed out: no rating button.
    expect(find.text('Rate this tour'), findsNothing);
  });
}
