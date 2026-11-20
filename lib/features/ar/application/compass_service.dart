import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../domain/ar_math.dart';

/// One compass reading for the AR view.
class CompassReading {
  const CompassReading({required this.heading, required this.disturbed});

  /// Where the back camera points, 0..360; null while the phone is flat.
  final double? heading;

  /// The magnetic field looks disturbed: ask the user to calibrate.
  final bool disturbed;
}

/// Combines the accelerometer and magnetometer into a smoothed heading.
final compassProvider = StreamProvider.autoDispose<CompassReading>((ref) {
  final smoother = AngleSmoother();
  AccelerometerEvent? gravity;
  final controller = StreamController<CompassReading>();
  const period = SensorInterval.uiInterval;

  final accel = accelerometerEventStream(samplingPeriod: period)
      .listen((e) => gravity = e, onError: controller.addError);
  final mag = magnetometerEventStream(samplingPeriod: period).listen((m) {
    final g = gravity;
    if (g == null) return;
    final raw = cameraHeading(
      ax: g.x,
      ay: g.y,
      az: g.z,
      mx: m.x,
      my: m.y,
      mz: m.z,
    );
    controller.add(
      CompassReading(
        heading: raw == null ? null : smoother.add(raw),
        disturbed: !fieldLooksClean(m.x, m.y, m.z),
      ),
    );
  }, onError: controller.addError);

  ref.onDispose(() {
    accel.cancel();
    mag.cancel();
    controller.close();
  });
  return controller.stream;
});
