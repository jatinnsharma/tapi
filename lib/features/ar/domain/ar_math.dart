import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Earth's magnetic field is 25–65 µT; outside that, something nearby
/// (metal, a vehicle, a magnet) is disturbing the compass.
const minEarthFieldMicroTesla = 25.0;
const maxEarthFieldMicroTesla = 65.0;

/// Horizontal field of view assumed for a phone's back camera, in degrees.
const cameraFieldOfViewDegrees = 60.0;

/// Compass bearing from [from] to [to], 0..360 (0 = north, 90 = east).
double bearingDegrees(LatLng from, LatLng to) {
  final lat1 = from.latitudeInRad, lat2 = to.latitudeInRad;
  final dLng = to.longitudeInRad - from.longitudeInRad;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return normalizeDegrees(math.atan2(y, x) * 180 / math.pi);
}

/// [degrees] in 0..360.
double normalizeDegrees(double degrees) => (degrees % 360 + 360) % 360;

/// The turn from [heading] to [target], in -180..180 (positive = right).
double angleDelta(double target, double heading) {
  final d = normalizeDegrees(target - heading);
  return d > 180 ? d - 360 : d;
}

/// The compass direction the back camera points, 0..360, from gravity
/// ([ax], [ay], [az], the accelerometer at rest) and the magnetic field
/// ([mx], [my], [mz]), both in the phone's axes (x right, y up the screen,
/// z out of the screen). Works with the phone held upright; null when the
/// readings can't give a direction (phone flat, or a zero reading).
///
/// This is Android's `getRotationMatrix`: H = field × gravity points east,
/// M = gravity × H points north, and the camera looks along -z.
double? cameraHeading({
  required double ax,
  required double ay,
  required double az,
  required double mx,
  required double my,
  required double mz,
}) {
  // H = magnetic × gravity (east).
  var hx = my * az - mz * ay;
  var hy = mz * ax - mx * az;
  var hz = mx * ay - my * ax;
  final hNorm = math.sqrt(hx * hx + hy * hy + hz * hz);
  final aNorm = math.sqrt(ax * ax + ay * ay + az * az);
  if (hNorm < 0.1 || aNorm < 0.1) return null;
  hx /= hNorm;
  hy /= hNorm;
  hz /= hNorm;
  final gx = ax / aNorm, gy = ay / aNorm, gz = az / aNorm;
  // M = gravity × H (north).
  final mzN = gx * hy - gy * hx;
  // Camera axis is -z: east component -hz, north component -mzN.
  final east = -hz, north = -mzN;
  if (east.abs() < 1e-6 && north.abs() < 1e-6) return null;
  // Pointing at the ground or sky: no useful direction.
  if (gz.abs() > 0.9) return null;
  return normalizeDegrees(math.atan2(east, north) * 180 / math.pi);
}

/// Whether the field strength looks like Earth's alone.
bool fieldLooksClean(double mx, double my, double mz) {
  final strength = math.sqrt(mx * mx + my * my + mz * mz);
  return strength >= minEarthFieldMicroTesla &&
      strength <= maxEarthFieldMicroTesla;
}

/// Smooths a jittery angle: each reading moves the result [alpha] of the
/// way there, around the circle (359° and 1° average to 0°, not 180°).
class AngleSmoother {
  AngleSmoother({this.alpha = 0.15});

  final double alpha;
  double? _x, _y;

  double? get value => _x == null
      ? null
      : normalizeDegrees(math.atan2(_y!, _x!) * 180 / math.pi);

  double add(double degrees) {
    final r = degrees * math.pi / 180;
    final nx = math.cos(r), ny = math.sin(r);
    if (_x == null) {
      _x = nx;
      _y = ny;
    } else {
      _x = _x! + alpha * (nx - _x!);
      _y = _y! + alpha * (ny - _y!);
    }
    return value!;
  }
}

/// Where the target appears across a [width]-wide camera view, given the
/// turn [delta] (from [angleDelta]); null when it's outside the view.
double? screenOffsetX(
  double delta,
  double width, {
  double fieldOfView = cameraFieldOfViewDegrees,
}) {
  final half = fieldOfView / 2;
  if (delta.abs() > half) return null;
  return width / 2 + delta / half * (width / 2);
}
