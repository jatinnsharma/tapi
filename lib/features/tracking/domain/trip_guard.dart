import 'package:latlong2/latlong.dart';

import '../../../core/services/gps_fix.dart';

/// Why a trip, a place or a bonus didn't earn XP. The wording is shown to
/// the user, so it says what to do rather than accusing.
enum XpDenial {
  mockLocation(
    'A mock-location app was detected, so this trip can\'t earn XP. '
    'Turn it off to earn XP on your next trip.',
  ),
  gpsJump(
    'Your location jumped further than anyone can travel, so this trip '
    'can\'t earn XP.',
  ),
  startedTooClose(
    'You started less than ${TripGuard.minStartDistanceMeters} m from this '
    'place. Start a trip from further away to earn its XP.',
  ),
  notTravelled(
    'Your recorded walk is much shorter than the distance to this place.',
  ),
  tooSoon('That was very quick. Keep going for a moment, then try again.'),
  tooShort(
    'This trip had too little trekking to count: walk at least '
    '${TripGuard.minCompletionMeters} m on foot for '
    '${TripGuard.minCompletionSeconds ~/ 60} minutes once you reach the '
    "trek's start. The journey there doesn't count.",
  );

  const XpDenial(this.message);
  final String message;

  /// Denials that can't be undone during the trip: the trip is flagged.
  bool get isPermanent => this == mockLocation || this == gpsJump;
}

/// What the guard decided about one GPS reading.
class FixResult {
  const FixResult({required this.accepted, this.addedMeters = 0, this.flag});

  /// Whether the reading is trustworthy and counts toward the trip.
  final bool accepted;

  /// Verified distance this reading adds to the trip.
  final double addedMeters;

  /// Set when the reading shows cheating: the trip is flagged.
  final XpDenial? flag;
}

/// Judges a trip's GPS readings, and whether the trip earned the right to
/// pay XP. It is plain logic with no phone or UI dependencies, so every rule
/// is covered by tests.
///
/// What it can and can't do: it stops fake-GPS apps that Android reports as
/// mock providers, teleporting, standing-still "walking", and tiny trips. A
/// determined cheat on a rooted phone can hide the mock flag, which is why
/// trips also need a camera photo at the place and why XP will ultimately
/// need to be checked on a server (see ACHIEVEMENT_RULES.md).
class TripGuard {
  /// Readings less precise than this are ignored. Phones report accuracy as
  /// a radius, and 50 m is already loose.
  static const maxAccuracyMeters = 50.0;

  /// Faster than this between two readings is not believable on the ground:
  /// 45 m/s is 162 km/h, above any car, bus or train speed in the region.
  /// The journey to a trek may be by vehicle, so only a jump beyond this is a
  /// teleport. Kept as low as honest travel allows: the higher it is, the
  /// sooner a fake jump followed by waiting looks like a real drive.
  /// (Whether a stretch was on foot or in a vehicle is [TripSplit]'s job.)
  static const maxSpeedMetersPerSecond = 45.0;

  /// Movement below this is GPS wobble, not walking.
  static const minStepMeters = 3.0;

  /// A jump this small can't be flagged as a teleport (timestamps and
  /// readings are noisy over short gaps).
  static const minJumpMeters = 60.0;

  /// To earn a place's XP you must start at least this far from it.
  static const minStartDistanceMeters = 100.0;

  /// ...and have walked at least this share of the straight-line distance.
  static const minTravelShare = 0.6;

  /// ...and have been on the trip at least this long.
  static const minArrivalSeconds = 60;

  /// A trip must have this much trek (on foot, from the trek's start), over
  /// this long, to count as completed (and pay the completion bonus).
  static const minCompletionMeters = 200;
  static const minCompletionSeconds = 120;

  /// A photo proves arrival only if the last good reading is this recent and
  /// this close to the place.
  static const proofFreshnessSeconds = 90;
  static const proofSlackMeters = 60.0;

  static const _distance = Distance();

  GpsFix? _first;
  GpsFix? _last;
  double _verifiedMeters = 0;
  int _jumps = 0;
  bool _mockSeen = false;

  /// Distance walked that passed every check.
  double get verifiedMeters => _verifiedMeters;

  bool get mockDetected => _mockSeen;
  int get jumps => _jumps;

  /// No sign of cheating so far.
  bool get isClean => !_mockSeen && _jumps == 0;

  GpsFix? get lastFix => _last;
  GpsFix? get firstFix => _first;

  /// Why this trip is flagged, or null if it isn't.
  XpDenial? get flag => _mockSeen
      ? XpDenial.mockLocation
      : (_jumps > 0 ? XpDenial.gpsJump : null);

  FixResult process(GpsFix fix) {
    if (fix.isMocked) {
      _mockSeen = true;
      return const FixResult(accepted: false, flag: XpDenial.mockLocation);
    }
    final accuracy = fix.accuracyMeters;
    if (accuracy != null && accuracy > maxAccuracyMeters) {
      return const FixResult(accepted: false);
    }

    final previous = _last;
    if (previous == null) {
      _first = fix;
      _last = fix;
      return const FixResult(accepted: true);
    }

    final seconds = fix.time.difference(previous.time).inMilliseconds / 1000;
    if (seconds <= 0) return const FixResult(accepted: false);

    final meters = _distance(previous.position, fix.position);
    if (meters >= minJumpMeters && meters / seconds > maxSpeedMetersPerSecond) {
      // Keep the old anchor: a spoofer who jumps and stays keeps failing.
      _jumps++;
      return const FixResult(accepted: false, flag: XpDenial.gpsJump);
    }

    _last = fix;
    final added = meters >= minStepMeters ? meters : 0.0;
    _verifiedMeters += added;
    return FixResult(accepted: true, addedMeters: added);
  }

  /// Why [target] can't pay its XP yet, or null if it can. [elapsed] is the
  /// trip's running time. Checked when the user reaches the place.
  XpDenial? arrivalDenial({required LatLng target, required Duration elapsed}) {
    final flagged = flag;
    if (flagged != null) return flagged;
    final first = _first;
    if (first == null) return XpDenial.tooSoon;

    final startDistance = _distance(first.position, target);
    if (startDistance < minStartDistanceMeters) {
      return XpDenial.startedTooClose;
    }
    if (_verifiedMeters < startDistance * minTravelShare) {
      return XpDenial.notTravelled;
    }
    if (elapsed.inSeconds < minArrivalSeconds) return XpDenial.tooSoon;
    return null;
  }

  /// Whether a camera photo taken at [now] counts as proof of being at
  /// [target]: the guard's last good reading must be fresh and inside the
  /// place's radius (plus a little slack for GPS error).
  bool photoProvesPresence({
    required LatLng target,
    required double radiusMeters,
    required DateTime now,
  }) {
    final last = _last;
    if (last == null || !isClean) return false;
    if (now.difference(last.time).inSeconds > proofFreshnessSeconds) {
      return false;
    }
    return _distance(last.position, target) <= radiusMeters + proofSlackMeters;
  }

  /// Whether the whole trip counts as completed (pays the completion bonus
  /// and counts toward achievements). Judged on the trek only: driving a
  /// long way doesn't make a trip.
  XpDenial? completionDenial({
    required double trekMeters,
    required Duration trekTime,
  }) {
    final flagged = flag;
    if (flagged != null) return flagged;
    if (trekMeters < minCompletionMeters ||
        trekTime.inSeconds < minCompletionSeconds) {
      return XpDenial.tooShort;
    }
    return null;
  }
}
