import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/food/data/food_repository.dart';
import 'package:real_world_exploration/features/food/domain/food.dart';
import 'package:real_world_exploration/features/food/domain/snack_stop.dart';
import 'package:real_world_exploration/features/food/presentation/signature_dishes_section.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';

Map<String, dynamic> _node(int id, Map<String, String> tags) => {
  'type': 'node',
  'id': id,
  'lat': 25.31,
  'lon': 83.01,
  'tags': tags,
};

/// A Dio whose every request is answered by [reply] (or fails when it
/// throws), counting the calls.
({Dio dio, List<String> calls}) _fakeDio(Object Function(String url) reply) {
  final calls = <String>[];
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls.add(options.uri.toString());
          try {
            handler.resolve(
              Response(
                requestOptions: options,
                data: reply(options.uri.toString()),
              ),
            );
          } catch (e) {
            handler.reject(DioException(requestOptions: options, error: e));
          }
        },
      ),
    );
  return (dio: dio, calls: calls);
}

void main() {
  group('FoodSpot from OpenStreetMap', () {
    test('kind, cuisine and pure-veg marking', () {
      final spot = FoodSpot.fromOverpass(
        _node(42, {
          'name': 'Kashi Chaat Bhandar',
          'amenity': 'fast_food',
          'cuisine': 'chaat;north_indian',
          'diet:vegetarian': 'only',
          'opening_hours': 'Mo-Su 16:00-22:00',
        }),
      )!;
      expect(spot.id, 'osm-node-42');
      expect(spot.kind, 'Street food');
      expect(spot.cuisine, 'chaat, north indian');
      expect(spot.diet, Diet.veg);
      expect(spot.openingHours, 'Mo-Su 16:00-22:00');
    });

    test('sweet shops and the English name', () {
      final spot = FoodSpot.fromOverpass(
        _node(7, {
          'name': 'मिठाई',
          'name:en': 'Mithai Wala',
          'shop': 'confectionery',
        }),
      )!;
      expect(spot.name, 'Mithai Wala');
      expect(spot.kind, 'Sweets');
      expect(spot.diet, isNull);
    });

    test('unnamed places are skipped', () {
      expect(FoodSpot.fromOverpass(_node(1, {'amenity': 'cafe'})), isNull);
    });
  });

  test('Diet reads the asset values', () {
    expect(Diet.parse('veg'), Diet.veg);
    expect(Diet.parse('nonveg'), Diet.nonVeg);
    expect(Diet.parse('both'), Diet.both);
  });

  test('every bundled dish list belongs to a catalog city', () {
    final dishes = jsonDecode(
      File('assets/data/india_signature_dishes.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final cityIds = {
      for (final c in jsonDecode(
        File('assets/data/india_cities.json').readAsStringSync(),
      ) as List<dynamic>)
        (c as Map<String, dynamic>)['id'],
    };
    expect(dishes.keys.where((id) => !cityIds.contains(id)), isEmpty);
    for (final list in dishes.values) {
      for (final d in list as List<dynamic>) {
        final dish = SignatureDish.fromJson(d as Map<String, dynamic>);
        expect(dish.name, isNotEmpty);
        expect(['veg', 'nonveg', 'both'], contains(d['diet']));
      }
    }
  });

  group('FoodRepository', () {
    test('parses spots, caches the area, falls back between servers', () async {
      var now = DateTime(2026, 11, 17, 12);
      final fake = _fakeDio((url) {
        if (url.contains('first')) throw StateError('down');
        return {
          'elements': [
            _node(1, {'name': 'Blue Lassi', 'amenity': 'cafe'}),
            _node(2, {'amenity': 'cafe'}),
          ],
        };
      });
      final repo = FoodRepository(
        dio: fake.dio,
        endpoints: const ['https://first.test/api', 'https://second.test/api'],
        clock: () => now,
      );

      final spots = await repo.spotsNear(25.3100, 83.0100);
      expect(spots.map((s) => s.name), ['Blue Lassi']);
      expect(fake.calls, hasLength(2)); // First server failed, second answered.

      await repo.spotsNear(25.3101, 83.0101); // Same ~100 m area: cached.
      expect(fake.calls, hasLength(2));

      now = now.add(foodCacheTtl);
      await repo.spotsNear(25.3100, 83.0100); // Expired: fetched again.
      expect(fake.calls, hasLength(4));
    });

    test('throws when no server answers', () async {
      final fake = _fakeDio((_) => throw StateError('down'));
      final repo = FoodRepository(
        dio: fake.dio,
        endpoints: const ['https://a.test', 'https://b.test'],
      );
      expect(repo.spotsNear(1, 1), throwsStateError);
    });
  });

  group('snack stop', () {
    TripStop stop(String id, {bool done = false}) => TripStop(
      id: id,
      placeName: id,
      description: '',
      timeSlot: 'Morning',
      durationMinutes: 60,
      latitude: 25.3,
      longitude: 83.0,
      category: 'heritage',
      isCompleted: done,
    );
    final plan = TripPlan(
      id: 'trip',
      title: 'Varanasi',
      destination: 'Varanasi',
      daysCount: 1,
      createdAt: DateTime(2026, 11, 1),
      days: [
        TripDayPlan(
          dayNumber: 1,
          title: 'Ghats',
          stops: [stop('done', done: true), stop('next')],
        ),
      ],
    );
    const spot = FoodSpot(
      id: 'osm-node-1',
      name: 'Blue Lassi',
      latitude: 25.31,
      longitude: 83.01,
      kind: 'Café',
      cuisine: 'lassi',
    );

    test('goes in as the next stop, once', () {
      final now = DateTime(2026, 11, 17, 15);
      final updated = withSnackStop(plan, 0, spot, now: now);
      final stops = updated.days.single.stops;
      expect(stops.map((s) => s.id), ['done', 'snack-osm-node-1', 'next']);
      final snack = stops[1];
      expect(snack.category, 'food');
      expect(snack.durationMinutes, snackStopMinutes);
      expect(snack.timeSlot, 'Afternoon');
      expect(snack.description, 'Café · lassi');
      expect(snack.placeId, 'osm-node-1');
      expect(withSnackStop(updated, 0, spot, now: now), same(updated));
    });

    test('time slots', () {
      expect(timeSlotAt(DateTime(2026, 1, 1, 9)), 'Morning');
      expect(timeSlotAt(DateTime(2026, 1, 1, 13)), 'Afternoon');
      expect(timeSlotAt(DateTime(2026, 1, 1, 19)), 'Evening');
    });
  });

  testWidgets('city dishes section lists dishes; empty shows nothing', (
    tester,
  ) async {
    Future<void> pump(String cityId) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            signatureDishesProvider.overrideWith(
              (ref, id) async => id == 'varanasi'
                  ? const [
                      SignatureDish(
                        name: 'Kachori Sabzi',
                        diet: Diet.veg,
                        when: 'Breakfast',
                        note: 'Fried kachoris.',
                      ),
                    ]
                  : const [],
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SignatureDishesSection(
                cityId: cityId,
                cityName: 'Varanasi',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pump('varanasi');
    expect(find.text('What to eat in Varanasi'), findsOneWidget);
    expect(find.text('Kachori Sabzi'), findsOneWidget);
    expect(tester.widget<DietMark>(find.byType(DietMark)).diet, Diet.veg);

    await pump('nowhere');
    expect(find.text('What to eat in Varanasi'), findsNothing);
  });
}
