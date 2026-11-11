import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/tracking/domain/trip_steps.dart';

final _t0 = DateTime.utc(2026, 10, 15, 8);
DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

void main() {
  test('the first reading only sets the starting point', () {
    final s = TripSteps()..add(52310, _at(0), onTrek: true);
    expect(s.steps, 0);
    expect(s.hasReadings, isTrue);
  });

  test('counts steps between readings', () {
    final s = TripSteps()
      ..add(1000, _at(0), onTrek: true)
      ..add(1020, _at(10), onTrek: true)
      ..add(1050, _at(25), onTrek: true);
    expect(s.steps, 50);
    expect(s.trekSteps, 50);
  });

  test('only steps while trekking are trek steps', () {
    final s = TripSteps()
      ..add(0, _at(0), onTrek: false)
      ..add(40, _at(30), onTrek: false) // walking to the car
      ..add(60, _at(600), onTrek: false) // a few steps during the drive
      ..add(560, _at(900), onTrek: true); // the trek
    expect(s.steps, 560);
    expect(s.trekSteps, 500);
  });

  test('a phone restart does not add or remove steps', () {
    final s = TripSteps()
      ..add(80000, _at(0), onTrek: true)
      ..add(80100, _at(60), onTrek: true)
      ..add(12, _at(200), onTrek: true) // restarted: the sensor starts over
      ..add(112, _at(260), onTrek: true);
    expect(s.steps, 200);
  });

  test('steps taken while paused do not count', () {
    final s = TripSteps()
      ..add(0, _at(0), onTrek: true)
      ..add(100, _at(60), onTrek: true);
    s.skipNextGap(); // paused...
    s
      ..add(3100, _at(3600), onTrek: true) // ...walked 3000 steps meanwhile
      ..add(3150, _at(3630), onTrek: true);
    expect(s.steps, 150);
  });

  test('an impossible jump is ignored', () {
    final s = TripSteps()
      ..add(0, _at(0), onTrek: true)
      ..add(5000, _at(10), onTrek: true) // 500 steps a second
      ..add(5030, _at(20), onTrek: true);
    expect(s.steps, 30);
  });

  test('a burst of readings close together still counts', () {
    final s = TripSteps()
      ..add(0, _at(0), onTrek: true)
      ..add(8, _at(0), onTrek: true); // batched by the phone
    expect(s.steps, 8);
  });
}
