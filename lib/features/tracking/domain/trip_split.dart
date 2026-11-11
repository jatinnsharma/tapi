import 'package:latlong2/latlong.dart';

import '../../../core/services/gps_fix.dart';

/// Which part of the trip the user is in.
enum TripPhase {
  /// Travelling to the trek's start (any transport). Counts as journey.
  toTrekStart('Journey'),

  /// On foot, after reaching the trek's start. Counts as trek.
  trekking('Trekking'),

  /// Travelling back by vehicle after the trek. Counts as journey.
  returning('Journey back');

  const TripPhase(this.label);
  final String label;
}

/// Splits a trip into **journey** (getting to the trek and back, by any
/// transport) and **trek** (the part on foot from the trek's start, including
/// a return hike). Only the trek counts for trek statistics, achievements,
/// the completion bonus and difficulty; the journey is shown for planning.
///
/// The rules, in order:
///  1. The trek starts when you are within [trekStartRadiusMeters] of its
///     start point (the place the trip goes to; for a trip with no place,
///     where the trip begins). Everything before that is journey.
///  2. After that, moving on foot counts as trek, and moving in a vehicle
///     counts as journey. "Vehicle" is judged on the last
///     [speedWindowSeconds] of movement, not one GPS step, so GPS wobble
///     isn't mistaken for a car.
///  3. A vehicle leg of [vehicleLegMeters] or more after the trek means you
///     are heading back: the rest is journey, unless you come back to the
///     trek's start on foot.
///
/// Time follows distance: a segment's time goes to the same side as its
/// movement; standing still keeps going to whichever side you were on
/// (resting on the trek is trek time, waiting in traffic is journey time).
///
/// Plain logic, fed with the readings [TripGuard] accepted, so every rule is
/// covered by tests (test/trip_split_test.dart). The server has a copy
/// (functions/lib/trip_split.js) that must stay in step.
class TripSplit {
  TripSplit({this.trekStart});

  /// Where the trek starts. Null: it starts where the trip starts.
  final LatLng? trekStart;

  /// The trek starts once you are this close to its start point.
  static const trekStartRadiusMeters = 200.0;

  /// Faster than this on average is a vehicle (or a bike), not trekking:
  /// 4 m/s is 14.4 km/h, a jog.
  static const maxTrekSpeedMetersPerSecond = 4.0;

  /// Speed is judged over this much recent time...
  static const speedWindowSeconds = 30;

  /// ...and, with less history than this, on the single step instead.
  static const minWindowSeconds = 10;

  /// With little history, a single step shorter than this is never taken for
  /// a vehicle: it is probably GPS wobble.
  static const wobbleMeters = 25.0;

  /// Movement below this is GPS wobble, not walking.
  static const minStepMeters = 3.0;

  /// A vehicle leg this long after the trek means you are heading back.
  static const vehicleLegMeters = 300.0;

  static const _distance = Distance();

  TripPhase _phase = TripPhase.toTrekStart;
  bool _trekStarted = false;
  bool _inVehicle = false;
  double _vehicleMetersSinceFoot = 0;
  final List<GpsFix> _window = [];
  GpsFix? _last;
  bool _skipNextTime = false;

  double _trekMeters = 0;
  double _journeyMeters = 0;
  double _trekSeconds = 0;
  double _journeySeconds = 0;

  TripPhase get phase => _phase;
  bool get trekStarted => _trekStarted;
  bool get inVehicle => _inVehicle;

  double get trekMeters => _trekMeters;
  double get journeyMeters => _journeyMeters;
  Duration get trekTime => _duration(_trekSeconds);
  Duration get journeyTime => _duration(_journeySeconds);

  /// Metres from [fix] to the trek's start, or null if there is no fixed
  /// start point.
  double? metersToTrekStart(LatLng position) {
    final start = trekStart;
    return start == null ? null : _distance(position, start);
  }

  /// Time between the next two readings isn't counted (the trip was paused
  /// in between). The distance still is, if the user moved.
  void skipNextGap() => _skipNextTime = true;

  /// Feeds one reading the trip guard accepted. Readings must come in order.
  void add(GpsFix fix) {
    final previous = _last;
    _last = fix;
    _window.add(fix);
    // Keep just enough history to cover the speed window.
    while (_window.length > 2 &&
        fix.time.difference(_window[1].time).inSeconds >= speedWindowSeconds) {
      _window.removeAt(0);
    }

    final inZone = _inTrekStartZone(fix.position);
    if (previous == null) {
      if (inZone) _startTrek();
      return;
    }

    final seconds = fix.time.difference(previous.time).inMilliseconds / 1000.0;
    final meters = _distance(previous.position, fix.position);
    final countedSeconds = _skipNextTime || seconds < 0 ? 0.0 : seconds;
    _skipNextTime = false;

    if (_isVehicle(fix, meters, seconds)) {
      _inVehicle = true;
      _vehicleMetersSinceFoot += meters;
    } else if (meters >= minStepMeters) {
      _inVehicle = false;
      _vehicleMetersSinceFoot = 0;
    }

    final movedMeters = meters >= minStepMeters ? meters : 0.0;
    if (_phase == TripPhase.trekking && !_inVehicle) {
      _trekMeters += movedMeters;
      _trekSeconds += countedSeconds;
    } else {
      _journeyMeters += movedMeters;
      _journeySeconds += countedSeconds;
    }

    switch (_phase) {
      case TripPhase.toTrekStart:
        if (inZone) _startTrek();
      case TripPhase.trekking:
        if (_vehicleMetersSinceFoot >= vehicleLegMeters) {
          _phase = TripPhase.returning;
        }
      case TripPhase.returning:
        if (inZone && !_inVehicle) _phase = TripPhase.trekking;
    }
  }

  void _startTrek() {
    _trekStarted = true;
    _phase = TripPhase.trekking;
    // Only a vehicle leg after reaching the trek means heading back; the
    // drive there doesn't.
    _vehicleMetersSinceFoot = 0;
  }

  bool _inTrekStartZone(LatLng position) {
    final start = trekStart;
    return start == null || _distance(position, start) <= trekStartRadiusMeters;
  }

  bool _isVehicle(GpsFix fix, double stepMeters, double stepSeconds) {
    // A step at walking speed is never a vehicle step, so getting out of a
    // car counts as trek straight away.
    if (stepSeconds <= 0 ||
        stepMeters / stepSeconds <= maxTrekSpeedMetersPerSecond) {
      return false;
    }
    // A fast step must be confirmed by the recent window: one GPS jump while
    // standing still is not a car.
    final first = _window.first;
    final span = fix.time.difference(first.time).inMilliseconds / 1000.0;
    if (span >= minWindowSeconds) {
      // Straight-line progress over the window: wobble doesn't add up, a
      // moving car does.
      final progress = _distance(first.position, fix.position);
      return progress / span > maxTrekSpeedMetersPerSecond;
    }
    return stepSeconds > 0 &&
        stepMeters >= wobbleMeters &&
        stepMeters / stepSeconds > maxTrekSpeedMetersPerSecond;
  }

  static Duration _duration(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round());
}

/// How hard a trek was, from its distance on foot only (the journey never
/// counts).
enum TrekDifficulty {
  easy('Easy'),
  moderate('Moderate'),
  challenging('Challenging'),
  hard('Hard');

  const TrekDifficulty(this.label);
  final String label;

  /// Null when there was no real trek (under 200 m on foot).
  static TrekDifficulty? forTrek(double trekMeters) {
    if (trekMeters < 200) return null;
    if (trekMeters < 3000) return easy;
    if (trekMeters < 8000) return moderate;
    if (trekMeters < 15000) return challenging;
    return hard;
  }
}
