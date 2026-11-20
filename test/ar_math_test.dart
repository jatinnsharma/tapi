import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/ar/domain/ar_math.dart';

void main() {
  const here = LatLng(25.30, 83.00);

  test('bearing: north, east, south, west', () {
    expect(bearingDegrees(here, const LatLng(25.31, 83.00)), closeTo(0, 0.1));
    expect(bearingDegrees(here, const LatLng(25.30, 83.01)), closeTo(90, 0.1));
    expect(bearingDegrees(here, const LatLng(25.29, 83.00)), closeTo(180, 0.1));
    expect(bearingDegrees(here, const LatLng(25.30, 82.99)), closeTo(270, 0.1));
  });

  test('turn needed: shortest way round, right is positive', () {
    expect(angleDelta(10, 350), closeTo(20, 1e-9));
    expect(angleDelta(350, 10), closeTo(-20, 1e-9));
    expect(angleDelta(180, 0), closeTo(180, 1e-9));
    expect(angleDelta(90, 90), 0);
  });

  // India's field points north and down (about 45° here, ~40 µT).
  const n = 28.0, d = 28.0, g = 9.81;

  test('upright phone facing north reads 0°', () {
    // Device axes: north is -z, up is +y.
    final h = cameraHeading(ax: 0, ay: g, az: 0, mx: 0, my: -d, mz: -n);
    expect(h, closeTo(0, 0.01));
  });

  test('upright phone facing east reads 90°', () {
    // Facing east: east is -z, north is -x, up is +y.
    final h = cameraHeading(ax: 0, ay: g, az: 0, mx: -n, my: -d, mz: 0);
    expect(h, closeTo(90, 0.01));
  });

  test('upright phone facing south-west reads 225°', () {
    // Facing SW: SW is -z, so north-east is +z; right (x) is north-west.
    // North = (x + z) / sqrt 2 in device axes.
    const c = 0.7071067811865476;
    final h = cameraHeading(ax: 0, ay: g, az: 0, mx: n * c, my: -d, mz: n * c);
    expect(h, closeTo(225, 0.01));
  });

  test('a phone lying flat gives no direction', () {
    expect(cameraHeading(ax: 0, ay: 0, az: g, mx: 0, my: n, mz: -d), isNull);
    expect(cameraHeading(ax: 0, ay: 0, az: 0, mx: 0, my: 0, mz: 0), isNull);
  });

  test('field strength check spots interference', () {
    expect(fieldLooksClean(0, -28, -28), isTrue); // ~40 µT.
    expect(fieldLooksClean(0, -90, -60), isFalse); // A car door.
    expect(fieldLooksClean(0, 5, 5), isFalse);
  });

  test('smoothing goes the short way round 0°', () {
    final s = AngleSmoother(alpha: 0.5);
    s.add(350);
    final v = s.add(10);
    // Halfway between 350° and 10° is 0°, not 180°.
    expect(angleDelta(v, 0).abs(), lessThan(1));
  });

  test(
    'on-screen position: centre ahead, edges at the view limit, off-view null',
    () {
      expect(screenOffsetX(0, 400), 200);
      expect(screenOffsetX(30, 400), 400);
      expect(screenOffsetX(-15, 400), 100);
      expect(screenOffsetX(31, 400), isNull);
    },
  );
}
