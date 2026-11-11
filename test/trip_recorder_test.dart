import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/services/gps_fix.dart';
import 'package:real_world_exploration/features/tracking/domain/trip_recorder.dart';

GpsFix _fix(int seconds, {bool mocked = false, double? acc = 8}) => GpsFix(
  position: const LatLng(30.7333, 76.7794),
  time: DateTime.utc(2026, 10, 14, 8).add(Duration(seconds: seconds)),
  accuracyMeters: acc,
  isMocked: mocked,
);

void main() {
  final start = DateTime.utc(2026, 10, 14, 8);
  TripRecorder make() => TripRecorder(tripId: 'trip-1', startedAt: start);

  test('payload has the shape the server expects', () {
    final r = make()
      ..addFix(_fix(0))
      ..addFix(_fix(10, acc: null))
      ..setPlace(
        id: 'p1',
        name: 'Rock Garden',
        latitude: 30.75,
        longitude: 76.8,
      )
      ..markProofPhoto(start.add(const Duration(minutes: 9)));
    final p = r.payload(start.add(const Duration(minutes: 12)));

    expect(p['tripId'], 'trip-1');
    expect(p['startedAt'], start.millisecondsSinceEpoch);
    expect(
      p['endedAt'],
      start.add(const Duration(minutes: 12)).millisecondsSinceEpoch,
    );
    expect(p['mockSeen'], false);
    expect(
      p['photoAt'],
      start.add(const Duration(minutes: 9)).millisecondsSinceEpoch,
    );
    final fixes = p['fixes']! as List;
    expect(fixes, hasLength(2));
    expect((fixes[0] as Map)['acc'], 8.0);
    expect((fixes[1] as Map).containsKey('acc'), false);
    expect((p['place']! as Map)['name'], 'Rock Garden');
  });

  test('a mocked reading is sent and flags the trip', () {
    final r = make()..addFix(_fix(0, mocked: true));
    final p = r.payload(start.add(const Duration(minutes: 5)));
    expect(p['mockSeen'], true);
    expect(((p['fixes']! as List).single as Map)['mocked'], true);
  });

  test('no place or photo means neither is sent', () {
    final p = make().payload(start.add(const Duration(minutes: 5)));
    expect(p.containsKey('place'), false);
    expect(p.containsKey('photoAt'), false);
  });

  test('stops recording at the server limit but still flags mocks', () {
    final r = make();
    for (var i = 0; i < TripRecorder.maxFixes + 50; i++) {
      r.addFix(_fix(i));
    }
    r.addFix(_fix(99999, mocked: true));
    expect(r.fixCount, TripRecorder.maxFixes);
    expect(r.payload(start.add(const Duration(hours: 3)))['mockSeen'], true);
  });
}
