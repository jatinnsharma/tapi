import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/planner/domain/day_rebalance.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/planner/presentation/stop_actions.dart';

/// Stops along a line east of [_here]; 0.01° of longitude ≈ 1 km here.
TripStop _stop(
  String id, {
  double kmEast = 1,
  int minutes = 60,
  String category = 'heritage',
  String? hours,
  bool done = false,
}) => TripStop(
  id: id,
  placeName: 'Place $id',
  description: '',
  timeSlot: 'Afternoon',
  durationMinutes: minutes,
  latitude: 25.30,
  longitude: 83.00 + kmEast / 100,
  category: category,
  openingHours: hours,
  isCompleted: done,
);

const _here = LatLng(25.30, 83.00);
final _afternoon = DateTime(2026, 11, 17, 14);

void main() {
  test('travel time: straight line with detours, at least 10 min', () {
    expect(travelMinutesBetween(_here, _here), rebalanceMinTravelMinutes);
    // ~10 km × 1.3 at 15 km/h ≈ 52 min.
    final ten = travelMinutesBetween(_here, const LatLng(25.30, 83.10));
    expect(ten, inInclusiveRange(48, 56));
  });

  test('running late: nearest first, and what does not fit is dropped', () {
    final result = rebalanceDay(
      pending: [
        _stop('far', kmEast: 8),
        _stop('near', kmEast: 1),
        _stop('long', kmEast: 2, minutes: 600),
      ],
      now: _afternoon,
      reason: RebalanceReason.runningLate,
      from: _here,
    );
    expect(result.kept.map((s) => s.id), ['near', 'far']);
    expect(result.dropped.single.stop.id, 'long');
    expect(result.dropped.single.reason, DropReason.noTime);
    expect(result.finishAt.isBefore(DateTime(2026, 11, 17, 21)), isTrue);
  });

  test('late in the evening nothing fits', () {
    final result = rebalanceDay(
      pending: [_stop('a'), _stop('b')],
      now: DateTime(2026, 11, 17, 20, 30),
      reason: RebalanceReason.runningLate,
      from: _here,
    );
    expect(result.kept, isEmpty);
    expect(result.dropped, hasLength(2));
  });

  test('tired: shorter visits and at most two stops', () {
    final result = rebalanceDay(
      pending: [
        _stop('a', kmEast: 1),
        _stop('b', kmEast: 2),
        _stop('c', kmEast: 3),
      ],
      now: _afternoon,
      reason: RebalanceReason.tired,
      from: _here,
    );
    expect(result.kept.map((s) => s.id), ['a', 'b']);
    expect(result.kept.first.durationMinutes, 45);
    expect(result.dropped.single.reason, DropReason.tired);
  });

  test('a place the user says is closed is dropped', () {
    final result = rebalanceDay(
      pending: [_stop('a'), _stop('shut', kmEast: 2)],
      now: _afternoon,
      reason: RebalanceReason.placeClosed,
      from: _here,
      closedStopIds: {'shut'},
    );
    expect(result.kept.map((s) => s.id), ['a']);
    expect(result.dropped.single.reason, DropReason.userClosed);
  });

  test('rain drops waterfalls and viewpoints, keeps temples', () {
    final result = rebalanceDay(
      pending: [
        _stop('falls', category: 'waterfall'),
        _stop('temple', category: 'heritage'),
        _stop('view', category: 'viewpoint'),
      ],
      now: _afternoon,
      reason: RebalanceReason.rain,
      from: _here,
      categoryOf: (s) => categoryOfStop(s.category),
    );
    expect(result.kept.map((s) => s.id), ['temple']);
    expect(result.dropped.map((d) => d.reason).toSet(), {DropReason.weather});
  });

  test('a stop closed on arrival is dropped; unknown hours are kept', () {
    final result = rebalanceDay(
      pending: [
        _stop('museum', hours: 'shut'),
        _stop('ghat', kmEast: 2),
      ],
      now: _afternoon,
      reason: RebalanceReason.runningLate,
      from: _here,
      isOpenAt: (stop, at) => stop.openingHours == 'shut' ? false : null,
    );
    expect(result.kept.map((s) => s.id), ['ghat']);
    expect(result.dropped.single.reason, DropReason.closed);
  });

  test('applying keeps done stops first and removes dropped ones', () {
    final day = TripDayPlan(
      dayNumber: 1,
      title: 'Ghats',
      stops: [
        _stop('done', done: true),
        _stop('b', kmEast: 5),
        _stop('a', kmEast: 1),
        _stop('gone', kmEast: 2),
      ],
    );
    final result = rebalanceDay(
      pending: day.stops.where((s) => !s.isCompleted).toList(),
      now: _afternoon,
      reason: RebalanceReason.placeClosed,
      from: _here,
      closedStopIds: {'gone'},
    );
    final updated = applyRebalance(day, result);
    expect(updated.stops.map((s) => s.id), ['done', 'a', 'b']);
  });
}
