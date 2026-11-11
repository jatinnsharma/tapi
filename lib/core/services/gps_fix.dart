import 'package:latlong2/latlong.dart';

/// One GPS reading with what's needed to judge whether it can be trusted.
class GpsFix {
  const GpsFix({
    required this.position,
    required this.time,
    this.accuracyMeters,
    this.isMocked = false,
  });

  final LatLng position;
  final DateTime time;

  /// Horizontal accuracy radius reported by the phone, when known.
  final double? accuracyMeters;

  /// True when Android says the position came from a mock-location app
  /// (a "fake GPS") rather than the GPS hardware. Always false on iOS, which
  /// doesn't expose this.
  final bool isMocked;
}
