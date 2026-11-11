/// Counts a trip's steps from the phone's step sensor, which reports a running
/// total (on Android, steps since the phone last restarted). Only the change
/// between readings counts, so:
///  - the first reading only sets the starting point;
///  - a phone restart (the total drops) restarts from the new value instead
///    of adding a huge or negative number;
///  - steps taken while the trip is paused are skipped ([skipNextGap]).
///
/// Steps are split like distance: those taken while trekking are trek steps.
class TripSteps {
  /// More than this many steps per second between readings isn't walking or
  /// running (sprinters manage about 5); such a jump is ignored.
  static const maxStepsPerSecond = 6;

  int? _lastTotal;
  DateTime? _lastAt;
  int _steps = 0;
  int _trekSteps = 0;

  /// Every step on the trip.
  int get steps => _steps;

  /// Steps taken while trekking.
  int get trekSteps => _trekSteps;

  /// Whether the sensor has reported anything yet.
  bool get hasReadings => _lastTotal != null;

  /// The next reading sets a new starting point: steps since the last one
  /// (taken while paused) don't count.
  void skipNextGap() {
    _lastTotal = null;
    _lastAt = null;
  }

  /// Feeds one sensor reading: [total] is the sensor's running count at
  /// [at]; [onTrek] says whether the user is trekking right now.
  void add(int total, DateTime at, {required bool onTrek}) {
    final last = _lastTotal;
    final lastAt = _lastAt;
    _lastTotal = total;
    _lastAt = at;
    if (last == null || lastAt == null) return;

    final delta = total - last;
    if (delta <= 0) return; // no new steps, or the phone restarted

    final seconds = at.difference(lastAt).inMilliseconds / 1000;
    // Allow a little slack for readings that arrive in quick bursts.
    if (delta > 10 && delta > (seconds + 1) * maxStepsPerSecond) return;

    _steps += delta;
    if (onTrek) _trekSteps += delta;
  }
}
