import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/services/gps_fix.dart';
import 'package:real_world_exploration/features/tracking/domain/trip_split.dart';

final _t0 = DateTime.utc(2026, 10, 14, 8);
const _mPerDegLat = 111200.0;
const _home = LatLng(30.7333, 76.7794);

LatLng _north(LatLng from, double meters) =>
    LatLng(from.latitude + meters / _mPerDegLat, from.longitude);

/// Feeds readings into a [TripSplit] along a straight line north, like a
/// phone reporting every [every] seconds.
class _Trip {
  _Trip(this.split, {LatLng start = _home}) : at = start {
    split.add(_fix());
  }

  final TripSplit split;
  LatLng at;
  int t = 0;

  GpsFix _fix() => GpsFix(
    position: at,
    time: _t0.add(Duration(seconds: t)),
  );

  /// Moves [meters] north at [speed] m/s, one reading every [every] s.
  void move(double meters, double speed, {int every = 10}) {
    final step = speed * every;
    for (var done = 0.0; done < meters - 0.01; done += step) {
      final d = (meters - done) < step ? meters - done : step;
      t += (d / speed).round().clamp(1, 1 << 30);
      at = _north(at, d);
      split.add(_fix());
    }
  }

  /// Stays put for [seconds], reporting the same spot.
  void wait(int seconds, {int every = 10}) {
    for (var s = 0; s < seconds; s += every) {
      t += every;
      split.add(_fix());
    }
  }

  /// Wobbles in place: GPS readings jumping a few metres around one spot.
  void wobble(int seconds, {double meters = 8, int every = 2}) {
    final centre = at;
    var sign = 1.0;
    for (var s = 0; s < seconds; s += every) {
      t += every;
      at = _north(centre, meters * sign);
      sign = -sign;
      split.add(_fix());
    }
    at = centre;
  }
}

void main() {
  const walk = 1.4; // m/s
  const car = 15.0; // m/s, 54 km/h

  group('A trip to a place (the trek starts within 200 m of it)', () {
    test('driving there is journey, walking around it is trek', () {
      final place = _north(_home, 10000);
      final trip = _Trip(TripSplit(trekStart: place));

      trip.move(9900, car); // drive to the car park, 100 m from the place
      expect(trip.split.phase, TripPhase.trekking); // arrived within 200 m
      trip.wait(60); // park
      trip.move(500, walk); // walk to the place and around it

      expect(trip.split.journeyMeters, closeTo(9900, 15));
      expect(trip.split.trekMeters, closeTo(500, 15));
      expect(trip.split.trekTime.inSeconds, closeTo(500 / walk, 40));
      expect(trip.split.journeyTime.inMinutes, greaterThanOrEqualTo(11));
    });

    test(
      'driving on into the car park inside the zone still starts the trek',
      () {
        final place = _north(_home, 3000);
        final trip = _Trip(TripSplit(trekStart: place));
        trip.move(2900, car); // into the zone and on to the car park
        expect(trip.split.phase, TripPhase.trekking);
        trip.move(400, walk);
        expect(trip.split.phase, TripPhase.trekking);
        expect(trip.split.trekMeters, closeTo(400, 15));
      },
    );

    test('walking there counts as journey until 200 m from the place', () {
      final place = _north(_home, 2000);
      final trip = _Trip(TripSplit(trekStart: place));

      trip.move(1700, walk);
      expect(trip.split.phase, TripPhase.toTrekStart);
      expect(trip.split.trekMeters, 0);

      trip.move(400, walk); // into the zone and past the place
      expect(trip.split.phase, TripPhase.trekking);
      expect(trip.split.journeyMeters, closeTo(1800, 15));
      expect(trip.split.trekMeters, closeTo(300, 15));
    });

    test('a return hike counts as trek; the drive home is journey', () {
      final trailhead = _north(_home, 5000);
      final trip = _Trip(TripSplit(trekStart: trailhead));

      trip.move(5000, car); // drive to the trailhead
      trip.move(3000, walk); // hike up
      trip.wait(600); // rest at the top: still trek
      // Hike back down. (The helper only walks north; distance and time are
      // what matter here.)
      trip.move(3000, walk);
      expect(trip.split.phase, TripPhase.trekking);
      trip.move(5000, car); // drive home

      expect(trip.split.phase, TripPhase.returning);
      expect(trip.split.trekMeters, closeTo(6000, 30));
      expect(trip.split.journeyMeters, closeTo(10000, 40));
      // Up, rest, down: about 36 + 10 + 36 minutes on the trek.
      expect(trip.split.trekTime.inMinutes, inInclusiveRange(78, 86));
    });

    test('walking from the bus stop home after the trek stays journey', () {
      final place = _north(_home, 3000);
      final trip = _Trip(TripSplit(trekStart: place));
      trip.move(3000, car);
      trip.move(400, walk); // the trek
      trip.move(4000, car); // bus back
      trip.move(300, walk); // bus stop to home, far from the place
      expect(trip.split.phase, TripPhase.returning);
      expect(trip.split.trekMeters, closeTo(400, 15));
    });

    test('coming back to the trek start on foot resumes the trek', () {
      final place = _north(_home, 1000);
      final trip = _Trip(TripSplit(trekStart: place));
      trip.move(1000, car);
      trip.move(200, walk);
      trip.move(400, car); // a short ride away...
      expect(trip.split.phase, TripPhase.returning);
      // ...and back near the start (helper only goes north, so restart the
      // walk from the start point).
      trip.at = place;
      trip.t += 120;
      trip.split.skipNextGap();
      trip.move(100, walk);
      expect(trip.split.phase, TripPhase.trekking);
    });

    test('waiting in traffic is journey time, not trek time', () {
      final place = _north(_home, 6000);
      final trip = _Trip(TripSplit(trekStart: place));
      trip.move(3000, car);
      trip.wait(600); // stuck in traffic
      trip.move(3000, car);
      expect(trip.split.trekTime, Duration.zero);
      expect(trip.split.journeyTime.inMinutes, greaterThanOrEqualTo(16));
    });

    test('sitting in the parked car at the trek start is journey time', () {
      final place = _north(_home, 2000);
      final trip = _Trip(TripSplit(trekStart: place));
      trip.move(2000, car);
      trip.wait(300); // still in the car
      expect(trip.split.trekTime, Duration.zero);
      trip.move(100, walk); // gets out and walks
      trip.wait(300); // rests on the trek
      expect(trip.split.trekTime.inSeconds, greaterThanOrEqualTo(360));
    });
  });

  group('A trip with no place', () {
    test('the trek starts at once; walking is trek', () {
      final trip = _Trip(TripSplit());
      expect(trip.split.phase, TripPhase.trekking);
      trip.move(800, walk);
      expect(trip.split.trekMeters, closeTo(800, 15));
      expect(trip.split.journeyMeters, 0);
    });

    test('a bus ride in the middle is journey', () {
      final trip = _Trip(TripSplit());
      trip.move(500, walk);
      trip.move(4000, car);
      expect(trip.split.journeyMeters, closeTo(4000, 40));
      expect(trip.split.trekMeters, closeTo(500, 30));
    });
  });

  group('GPS noise and edge cases', () {
    test('GPS wobble while standing is neither trek nor vehicle', () {
      final trip = _Trip(TripSplit());
      trip.wobble(120);
      expect(trip.split.inVehicle, isFalse);
      expect(trip.split.journeyMeters, 0);
    });

    test('jogging is still trekking', () {
      final trip = _Trip(TripSplit());
      trip.move(2000, 3.2); // 11.5 km/h
      expect(trip.split.trekMeters, closeTo(2000, 30));
      expect(trip.split.journeyMeters, 0);
    });

    test('a car is spotted with readings every second', () {
      final trip = _Trip(TripSplit());
      trip.move(100, walk, every: 1);
      trip.move(2000, car, every: 1);
      expect(trip.split.journeyMeters, greaterThan(1700));
    });

    test('time across a pause is not counted', () {
      final trip = _Trip(TripSplit());
      trip.move(300, walk);
      final before = trip.split.trekTime;
      trip.t += 3600; // paused for an hour
      trip.split.skipNextGap();
      trip.move(10, walk);
      expect(
        trip.split.trekTime - before,
        lessThan(const Duration(seconds: 30)),
      );
    });

    test('distance to the trek start is reported', () {
      final place = _north(_home, 1500);
      final split = TripSplit(trekStart: place);
      expect(split.metersToTrekStart(_home), closeTo(1500, 5));
      expect(TripSplit().metersToTrekStart(_home), isNull);
    });
  });

  group('Trek difficulty uses the trek only', () {
    test('by distance on foot', () {
      expect(TrekDifficulty.forTrek(100), isNull);
      expect(TrekDifficulty.forTrek(1500), TrekDifficulty.easy);
      expect(TrekDifficulty.forTrek(5000), TrekDifficulty.moderate);
      expect(TrekDifficulty.forTrek(9000), TrekDifficulty.challenging);
      expect(TrekDifficulty.forTrek(18000), TrekDifficulty.hard);
    });
  });
}
