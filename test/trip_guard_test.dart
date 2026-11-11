import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/services/gps_fix.dart';
import 'package:real_world_exploration/features/tracking/domain/trip_guard.dart';

final _t0 = DateTime.utc(2026, 10, 14, 8);

/// Roughly 1 degree of latitude is 111.2 km.
const _mPerDegLat = 111200.0;
const _home = LatLng(30.7333, 76.7794);

LatLng _north(LatLng from, double meters) =>
    LatLng(from.latitude + meters / _mPerDegLat, from.longitude);

GpsFix _fix(
  LatLng p,
  int seconds, {
  double accuracy = 8,
  bool mocked = false,
}) => GpsFix(
  position: p,
  time: _t0.add(Duration(seconds: seconds)),
  accuracyMeters: accuracy,
  isMocked: mocked,
);

/// Walks [meters] north in 1 m/s steps of 10 s, returning the final point.
LatLng _walk(TripGuard g, LatLng from, double meters, {int startAt = 0}) {
  var p = from;
  var t = startAt;
  for (var walked = 0.0; walked < meters; walked += 10) {
    t += 10;
    p = _north(p, 10);
    g.process(_fix(p, t));
  }
  return p;
}

void main() {
  group('GPS readings', () {
    test('a normal walk adds up its distance', () {
      final g = TripGuard()..process(_fix(_home, 0));
      _walk(g, _home, 500);
      expect(g.verifiedMeters, closeTo(500, 10));
      expect(g.isClean, isTrue);
    });

    test('a mock-location reading is rejected and flags the trip', () {
      final g = TripGuard()..process(_fix(_home, 0));
      final r = g.process(_fix(_north(_home, 20), 10, mocked: true));
      expect(r.accepted, isFalse);
      expect(r.flag, XpDenial.mockLocation);
      expect(g.mockDetected, isTrue);
      expect(g.flag, XpDenial.mockLocation);
      expect(g.verifiedMeters, 0);
    });

    test('a teleport is rejected, flagged, and adds no distance', () {
      final g = TripGuard()..process(_fix(_home, 0));
      // 3 km in 10 seconds.
      final r = g.process(_fix(_north(_home, 3000), 10));
      expect(r.accepted, isFalse);
      expect(r.flag, XpDenial.gpsJump);
      expect(g.jumps, 1);
      expect(g.verifiedMeters, 0);
    });

    test('a spoofer who jumps and stays keeps failing', () {
      final g = TripGuard()..process(_fix(_home, 0));
      final far = _north(_home, 3000);
      for (var t = 10; t <= 50; t += 10) {
        expect(g.process(_fix(far, t)).accepted, isFalse);
      }
      expect(g.jumps, 5);
    });

    test('a long gap with a short move (GPS lost, then found) is fine', () {
      final g = TripGuard()..process(_fix(_home, 0));
      final r = g.process(_fix(_north(_home, 900), 600)); // 1.5 m/s
      expect(r.accepted, isTrue);
      expect(g.isClean, isTrue);
    });

    test('a car or train on the journey is fine; a teleport is not', () {
      final g = TripGuard()..process(_fix(_home, 0));
      expect(g.process(_fix(_north(_home, 80), 10)).accepted, isTrue); // 8 m/s
      final car = g.process(_fix(_north(_home, 80 + 400), 20)); // 40 m/s
      expect(car.accepted, isTrue);
      expect(g.isClean, isTrue);
      final teleport = g.process(
        _fix(_north(_home, 480 + 3000), 30),
      ); // 300 m/s
      expect(teleport.accepted, isFalse);
      expect(g.flag, XpDenial.gpsJump);
    });

    test('imprecise readings are ignored without flagging', () {
      final g = TripGuard()..process(_fix(_home, 0));
      final r = g.process(_fix(_north(_home, 20), 10, accuracy: 120));
      expect(r.accepted, isFalse);
      expect(r.flag, isNull);
      expect(g.isClean, isTrue);
    });

    test('standing still (GPS wobble) adds nothing', () {
      final g = TripGuard()..process(_fix(_home, 0));
      for (var t = 10; t <= 600; t += 10) {
        g.process(_fix(_north(_home, t.isEven ? 1 : 2), t));
      }
      expect(g.verifiedMeters, lessThan(5));
    });

    test('readings out of order or at the same time are ignored', () {
      final g = TripGuard()..process(_fix(_home, 100));
      expect(g.process(_fix(_north(_home, 30), 100)).accepted, isFalse);
      expect(g.process(_fix(_north(_home, 30), 50)).accepted, isFalse);
    });
  });

  group('Arriving at a place', () {
    final place = _north(_home, 600);

    test('a real walk there pays', () {
      final g = TripGuard()..process(_fix(_home, 0));
      _walk(g, _home, 600);
      expect(
        g.arrivalDenial(target: place, elapsed: const Duration(minutes: 10)),
        isNull,
      );
    });

    test('starting right next to the place does not pay', () {
      final g = TripGuard()..process(_fix(_north(place, 30), 0));
      _walk(g, _north(place, 30), 30);
      expect(
        g.arrivalDenial(target: place, elapsed: const Duration(minutes: 10)),
        XpDenial.startedTooClose,
      );
    });

    test('teleporting there does not pay', () {
      final g = TripGuard()..process(_fix(_home, 0));
      g.process(_fix(place, 5)); // 600 m in 5 s
      expect(
        g.arrivalDenial(target: place, elapsed: const Duration(minutes: 10)),
        XpDenial.gpsJump,
      );
    });

    test('a short walk cannot cover a long distance', () {
      final far = _north(_home, 3000);
      final g = TripGuard()..process(_fix(_home, 0));
      _walk(g, _home, 200);
      expect(
        g.arrivalDenial(target: far, elapsed: const Duration(minutes: 10)),
        XpDenial.notTravelled,
      );
    });

    test('arriving within a minute of starting does not pay', () {
      final g = TripGuard()..process(_fix(_home, 0));
      _walk(g, _home, 600);
      expect(
        g.arrivalDenial(target: place, elapsed: const Duration(seconds: 30)),
        XpDenial.tooSoon,
      );
    });

    test('no readings yet means no arrival', () {
      expect(
        TripGuard().arrivalDenial(
          target: place,
          elapsed: const Duration(minutes: 10),
        ),
        XpDenial.tooSoon,
      );
    });
  });

  group('Photo proof of presence', () {
    final place = _north(_home, 600);

    TripGuard arrived() {
      final g = TripGuard()..process(_fix(_home, 0));
      _walk(g, _home, 600);
      return g;
    }

    test('counts when the last good reading is fresh and at the place', () {
      final g = arrived();
      final now = g.lastFix!.time.add(const Duration(seconds: 20));
      expect(
        g.photoProvesPresence(target: place, radiusMeters: 40, now: now),
        isTrue,
      );
    });

    test('does not count if the user has since walked away', () {
      final g = arrived();
      _walk(g, g.lastFix!.position, 300, startAt: 700);
      expect(
        g.photoProvesPresence(
          target: place,
          radiusMeters: 40,
          now: g.lastFix!.time,
        ),
        isFalse,
      );
    });

    test('does not count on a stale reading', () {
      final g = arrived();
      final now = g.lastFix!.time.add(const Duration(minutes: 10));
      expect(
        g.photoProvesPresence(target: place, radiusMeters: 40, now: now),
        isFalse,
      );
    });

    test('never counts on a flagged trip', () {
      final g = arrived()..process(_fix(_north(place, 5), 9999, mocked: true));
      expect(
        g.photoProvesPresence(
          target: place,
          radiusMeters: 40,
          now: g.lastFix!.time,
        ),
        isFalse,
      );
    });
  });

  group('Completing a trip', () {
    test('a real trip counts', () {
      final g = TripGuard()..process(_fix(_home, 0));
      _walk(g, _home, 300);
      expect(
        g.completionDenial(
          trekMeters: 300,
          trekTime: const Duration(minutes: 6),
        ),
        isNull,
      );
    });

    test('start-and-finish farming does not', () {
      final g = TripGuard()..process(_fix(_home, 0));
      expect(
        g.completionDenial(trekMeters: 0, trekTime: const Duration(seconds: 3)),
        XpDenial.tooShort,
      );
    });

    test('a long sit with no movement does not', () {
      final g = TripGuard()..process(_fix(_home, 0));
      expect(
        g.completionDenial(trekMeters: 0, trekTime: const Duration(hours: 2)),
        XpDenial.tooShort,
      );
    });

    test('a long drive with almost no trek does not count', () {
      final g = TripGuard()..process(_fix(_home, 0));
      expect(
        g.completionDenial(
          trekMeters: 50,
          trekTime: const Duration(minutes: 30),
        ),
        XpDenial.tooShort,
      );
    });

    test('a flagged trip never counts, however long', () {
      final g = TripGuard()..process(_fix(_home, 0));
      _walk(g, _home, 500);
      g.process(_fix(_north(_home, 520), 9999, mocked: true));
      expect(
        g.completionDenial(trekMeters: 500, trekTime: const Duration(hours: 1)),
        XpDenial.mockLocation,
      );
    });
  });

  group('Denials', () {
    test('only mock locations and GPS jumps are permanent', () {
      expect(XpDenial.mockLocation.isPermanent, isTrue);
      expect(XpDenial.gpsJump.isPermanent, isTrue);
      expect(XpDenial.tooSoon.isPermanent, isFalse);
      expect(XpDenial.notTravelled.isPermanent, isFalse);
    });

    test('every denial has a message for the user', () {
      for (final d in XpDenial.values) {
        expect(d.message.trim(), isNotEmpty);
      }
    });
  });
}
