import '../../../core/services/gps_fix.dart';

/// Keeps what the server needs to re-judge a trip: every GPS reading (fake
/// ones included, so the server sees them too), the proof photo's time and
/// the place. Built into the payload for the `verifyTrip` Cloud Function.
class TripRecorder {
  TripRecorder({required this.tripId, required this.startedAt});

  /// The server stops reading after this many readings.
  static const maxFixes = 6000;

  final String tripId;
  final DateTime startedAt;

  final List<Map<String, Object>> _fixes = [];
  bool _mockSeen = false;
  DateTime? _photoAt;
  Map<String, Object>? _place;

  int get fixCount => _fixes.length;

  void addFix(GpsFix fix) {
    if (fix.isMocked) _mockSeen = true;
    if (_fixes.length >= maxFixes) return;
    _fixes.add({
      'lat': fix.position.latitude,
      'lng': fix.position.longitude,
      't': fix.time.millisecondsSinceEpoch,
      'acc': ?fix.accuracyMeters,
      if (fix.isMocked) 'mocked': true,
    });
  }

  /// The place the trip is heading to.
  void setPlace({
    required String id,
    required String name,
    required double latitude,
    required double longitude,
    String? category,
  }) {
    _place = {
      'id': id,
      'name': name,
      'lat': latitude,
      'lng': longitude,
      'category': ?category,
    };
  }

  /// The in-app camera photo taken at the place.
  void markProofPhoto(DateTime takenAt) => _photoAt = takenAt;

  Map<String, Object> payload(DateTime endedAt) => {
    'tripId': tripId,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'endedAt': endedAt.millisecondsSinceEpoch,
    'fixes': List.of(_fixes),
    'mockSeen': _mockSeen,
    'place': ?_place,
    'photoAt': ?_photoAt?.millisecondsSinceEpoch,
  };
}
