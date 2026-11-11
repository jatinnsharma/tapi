import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

/// One reading of the phone's step sensor: its running total at a moment.
class StepReading {
  const StepReading(this.total, this.at);
  final int total;
  final DateTime at;
}

final stepServiceProvider = Provider<StepService>((ref) => StepService());

/// The phone's own step counter (the low-power sensor, not the GPS). Optional:
/// some phones have no step sensor and people may say no to the permission,
/// and trips work the same without it.
class StepService {
  /// Only phones have a step sensor.
  bool get supported => Platform.isAndroid || Platform.isIOS;

  /// Asks for the "Physical activity" permission on Android 10+. iOS asks by
  /// itself the first time the step count is read.
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.activityRecognition.request();
    return status.isGranted || status.isLimited;
  }

  /// Running totals from the sensor. Errors if the phone has no step sensor.
  Stream<StepReading> readings() =>
      Pedometer.stepCountStream.map((e) => StepReading(e.steps, e.timeStamp));
}
