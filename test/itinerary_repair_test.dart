import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/planner/data/itinerary_repair.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/tracking/data/directions_service.dart';

const _varanasi = LatLng(25.3176, 82.9739);

ExploreLocation _place(String id, String name, double lat, double lng) =>
    ExploreLocation(
      id: id,
      name: name,
      category: LocationCategory.heritage,
      description: '',
      latitude: lat,
      longitude: lng,
      xpReward: 80,
    );

final _places = [
  _place('wiki-1', 'Dashashwamedh Ghat', 25.3060, 83.0104),
  _place('wiki-2', 'Kashi Vishwanath Temple', 25.3109, 83.0107),
  _place('wiki-3', 'Assi Ghat', 25.2895, 83.0066),
  _place('wiki-4', 'Sarnath', 25.3811, 83.0214),
  _place('wiki-5', 'Ramnagar Fort', 25.2697, 83.0247),
];

TripStop _stop(
  String name, {
  double lat = 0,
  double lng = 0,
  String slot = '',
}) => TripStop(
  id: 'raw',
  placeName: name,
  description: '',
  timeSlot: slot,
  durationMinutes: 90,
  latitude: lat,
  longitude: lng,
  category: 'heritage',
);

TripDayPlan _day(int n, List<TripStop> stops) =>
    TripDayPlan(dayNumber: n, title: 'Day $n', stops: stops);

/// A filler day from the real places not used yet, like the planner's.
TripDayPlan _filler(int n, Set<String> used) {
  final p = _places.firstWhere((p) => !used.contains(p.id));
  used.add(p.id);
  return _day(n, [
    _stop(p.name, lat: p.latitude, lng: p.longitude).copyWith(placeId: p.id),
  ]);
}

void main() {
  group('ItineraryRepairer.groundStop', () {
    test('snaps a stop to the real place its name matches', () async {
      final repairer = ItineraryRepairer(places: _places, center: _varanasi);
      // Wrong coordinates (Delhi) and a slightly different name.
      final placed = await repairer.groundStop(
        _stop('The Dashashwamedh Ghat', lat: 28.61, lng: 77.20),
      );
      expect(placed!.placeId, 'wiki-1');
      expect(placed.latitude, 25.3060);
      expect(placed.xpReward, 80);
    });

    test('geocodes an unknown name, but only inside the destination', () async {
      final repairer = ItineraryRepairer(
        places: _places,
        center: _varanasi,
        geocode: (name) async => name == 'Manikarnika Ghat'
            ? (point: const LatLng(25.3109, 83.0137), placeId: 'osm-42')
            : (point: const LatLng(19.07, 72.87), placeId: 'osm-mumbai'),
      );
      final found = await repairer.groundStop(_stop('Manikarnika Ghat'));
      expect(found!.placeId, 'osm-42');

      // Geocoded to Mumbai and no usable AI coordinates: dropped.
      expect(await repairer.groundStop(_stop('Somewhere Else')), isNull);
    });

    test('keeps AI coordinates only when they are in the area', () async {
      final repairer = ItineraryRepairer(places: _places, center: _varanasi);
      final near = await repairer.groundStop(
        _stop('Tulsi Manas Temple', lat: 25.2867, lng: 82.9997),
      );
      expect(near!.placeId, startsWith('plan-tulsi-manas-temple-'));

      // Missing coordinates parse as 0, 0.
      expect(await repairer.groundStop(_stop('Made Up Palace')), isNull);
      // Real coordinates, wrong city.
      expect(
        await repairer.groundStop(_stop('Gateway', lat: 18.92, lng: 72.83)),
        isNull,
      );
    });

    test('stops geocoding once the time budget is spent', () async {
      var lookups = 0;
      final repairer = ItineraryRepairer(
        places: const [],
        center: _varanasi,
        geocodeBudget: const Duration(milliseconds: 50),
        geocode: (_) async {
          lookups++;
          await Future<void>.delayed(const Duration(milliseconds: 60));
          return null;
        },
      );
      await repairer.groundStop(_stop('A'));
      await repairer.groundStop(_stop('B'));
      expect(lookups, 1);
    });
  });

  group('ItineraryRepairer.repair', () {
    test('returns exactly the requested days, numbered 1..N', () async {
      final repairer = ItineraryRepairer(places: _places, center: _varanasi);
      final days = await repairer.repair(
        [
          _day(2, [_stop('Assi Ghat')]),
          _day(1, [_stop('Sarnath')]),
        ],
        daysCount: 3,
        fallbackDay: _filler,
      );
      expect(days.map((d) => d.dayNumber), [1, 2, 3]);
      expect(days[0].stops.single.placeId, 'wiki-4'); // Sorted by day number.
      expect(days[1].stops.single.placeId, 'wiki-3');
      expect(days[2].stops, isNotEmpty); // Filled in.
      expect(days[2].stops.single.placeId, isNot(anyOf('wiki-3', 'wiki-4')));

      final truncated =
          await ItineraryRepairer(places: _places, center: _varanasi).repair(
            [
              _day(1, [_stop('Sarnath')]),
              _day(2, [_stop('Assi Ghat')]),
            ],
            daysCount: 1,
            fallbackDay: _filler,
          );
      expect(truncated, hasLength(1));
    });

    test('drops repeated places and refills a day left empty', () async {
      final repairer = ItineraryRepairer(places: _places, center: _varanasi);
      final days = await repairer.repair(
        [
          _day(1, [_stop('Assi Ghat'), _stop('Assi Ghat')]),
          _day(2, [_stop('Assi Ghat'), _stop('Nowhere')]),
        ],
        daysCount: 2,
        fallbackDay: _filler,
      );
      expect(days[0].stops, hasLength(1));
      expect(days[1].stops, isNotEmpty);
      final ids = days.expand((d) => d.stops).map((s) => s.placeId).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('avoids places already used on other days', () async {
      final repairer = ItineraryRepairer(places: _places, center: _varanasi);
      final days = await repairer.repair(
        [
          _day(1, [_stop('Sarnath'), _stop('Ramnagar Fort')]),
        ],
        daysCount: 1,
        fallbackDay: _filler,
        alreadyUsed: {'wiki-4'},
      );
      expect(days.single.stops.map((s) => s.placeId), ['wiki-5']);
    });

    test('tidies time slots and durations', () async {
      final repairer = ItineraryRepairer(places: _places, center: _varanasi);
      final days = await repairer.repair(
        [
          _day(1, [
            _stop(
              'Sarnath',
              slot: 'early morning',
            ).copyWith(durationMinutes: 2000),
            _stop('Assi Ghat', slot: 'शाम'),
            _stop('Ramnagar Fort', slot: '???').copyWith(durationMinutes: 1),
          ]),
        ],
        daysCount: 1,
        fallbackDay: _filler,
      );
      final stops = days.single.stops;
      expect(stops.map((s) => s.timeSlot), ['Morning', 'Evening', 'Evening']);
      expect(stops[0].durationMinutes, 480);
      expect(stops[2].durationMinutes, 15);
    });
  });

  group('names', () {
    test('similarity ignores case, punctuation and filler words', () {
      double sim(String a, String b) => ItineraryRepairer.nameSimilarity(
        ItineraryRepairer.normalizeName(a),
        ItineraryRepairer.normalizeName(b),
      );
      expect(sim('Shri Kashi Vishwanath Temple', 'kashi vishwanath temple'), 1);
      expect(
        sim('Assi Ghat', 'Assi Ghat, Varanasi'),
        greaterThanOrEqualTo(0.6),
      );
      expect(sim('Assi Ghat', 'Ramnagar Fort'), lessThan(0.6));
    });

    test('stable ids stay the same for the same place and have no @', () {
      final a = ItineraryRepairer.stableIdFor(
        _stop('Tulsi Manas Temple', lat: 25.28671, lng: 82.99969),
      );
      final b = ItineraryRepairer.stableIdFor(
        _stop('Tulsi Manas Temple', lat: 25.28674, lng: 82.99972),
      );
      expect(a, b);
      expect(a, isNot(contains('@')));
      expect(
        ItineraryRepairer.stableIdFor(_stop('तुलसी मंदिर', lat: 25.3, lng: 83)),
        'plan-25.300_83.000',
      );
    });
  });

  group('TripStop', () {
    test('missing coordinates are invalid instead of New Delhi', () {
      final stop = TripStop.fromJson({'placeName': 'Somewhere'});
      expect(stop.hasValidCoordinates, isFalse);
    });

    test('place id and XP survive a JSON round trip', () {
      final stop = _stop(
        'Sarnath',
        lat: 25.38,
        lng: 83.02,
      ).copyWith(placeId: 'wiki-4', xpReward: 90);
      final back = TripStop.fromJson(stop.toJson());
      expect(back.placeId, 'wiki-4');
      expect(back.xpReward, 90);
      expect(back.hasValidCoordinates, isTrue);
    });
  });

  group('describeLeg', () {
    test('short legs are walks, longer ones by road', () {
      expect(
        describeLeg(
          const TravelEstimate(meters: 900, duration: Duration(minutes: 3)),
        ),
        '12 min walk · 900 m',
      );
      expect(
        describeLeg(
          const TravelEstimate(meters: 6200, duration: Duration(minutes: 20)),
        ),
        '20 min by road · 6.2 km',
      );
      expect(
        describeLeg(
          const TravelEstimate(meters: 45000, duration: Duration(minutes: 75)),
        ),
        '1 h 15 min by road · 45.0 km',
      );
    });
  });
}
