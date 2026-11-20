import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/planner/domain/plan_merge.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';

TripStop _s(String id, {String? tip, bool done = false}) => TripStop(
  id: id,
  placeName: 'Place $id',
  description: '',
  timeSlot: 'Morning',
  durationMinutes: 60,
  latitude: 25.3,
  longitude: 83.0,
  category: 'heritage',
  tip: tip,
  isCompleted: done,
);

TripPlan _plan(
  List<TripStop> stops, {
  String title = 'Varanasi',
  List<String> packed = const [],
  List<String> members = const ['owner', 'friend'],
  DateTime? updated,
}) => TripPlan(
  id: 'trip',
  title: title,
  destination: 'Varanasi',
  daysCount: 1,
  createdAt: DateTime(2026, 11, 1),
  days: [TripDayPlan(dayNumber: 1, title: 'Ghats', stops: stops)],
  packingChecked: packed,
  ownerUid: 'owner',
  memberUids: members,
  updatedAt: updated,
);

List<String> _ids(TripPlan p) => [for (final s in p.days.single.stops) s.id];

void main() {
  final base = _plan([_s('a'), _s('b'), _s('c')]);

  test('nothing changed on one side: the other side wins whole', () {
    final remote = _plan([_s('a'), _s('c')], title: 'Kashi');
    expect(mergePlans(base: base, local: base, remote: remote).title, 'Kashi');
    final local = _plan([_s('a')], title: 'Mine');
    expect(_ids(mergePlans(base: base, local: local, remote: base)), ['a']);
  });

  test('a stop added on each side: both are kept', () {
    final local = _plan([_s('a'), _s('b'), _s('mine'), _s('c')]);
    final remote = _plan([_s('a'), _s('b'), _s('c'), _s('theirs')]);
    expect(_ids(mergePlans(base: base, local: local, remote: remote)), [
      'a',
      'b',
      'mine',
      'c',
      'theirs',
    ]);
  });

  test('different stops edited on each side: both edits are kept', () {
    final local = _plan([_s('a', done: true), _s('b'), _s('c')]);
    final remote = _plan([_s('a'), _s('b'), _s('c', tip: 'Go early')]);
    final merged = mergePlans(base: base, local: local, remote: remote);
    final stops = merged.days.single.stops;
    expect(stops[0].isCompleted, isTrue);
    expect(stops[2].tip, 'Go early');
  });

  test('the very same stop edited on both sides: this phone wins', () {
    final local = _plan([_s('a', tip: 'mine'), _s('b'), _s('c')]);
    final remote = _plan([_s('a', tip: 'theirs'), _s('b'), _s('c')]);
    final merged = mergePlans(base: base, local: local, remote: remote);
    expect(merged.days.single.stops.first.tip, 'mine');
  });

  test('a deleted stop stays deleted, unless the other side edited it', () {
    // I delete b; they did nothing to b.
    var merged = mergePlans(
      base: base,
      local: _plan([_s('a'), _s('c')]),
      remote: _plan([_s('a'), _s('b'), _s('c', tip: 'x')]),
    );
    expect(_ids(merged), ['a', 'c']);
    expect(merged.days.single.stops.last.tip, 'x');

    // I delete b; they marked b done meanwhile: keep their b.
    merged = mergePlans(
      base: base,
      local: _plan([_s('a'), _s('c')]),
      remote: _plan([_s('a'), _s('b', done: true), _s('c')]),
    );
    expect(_ids(merged), ['a', 'b', 'c']);
  });

  test('the order follows whoever reordered', () {
    final local = _plan([_s('c'), _s('a'), _s('b')]);
    final remote = _plan([_s('a'), _s('b'), _s('c'), _s('d')]);
    // My order wins; their new d goes right after c, as they placed it.
    expect(_ids(mergePlans(base: base, local: local, remote: remote)), [
      'c',
      'd',
      'a',
      'b',
    ]);

    final theirOrder = _plan([_s('b'), _s('a'), _s('c')]);
    final myEdit = _plan([_s('a', tip: 't'), _s('b'), _s('c')]);
    final merged = mergePlans(base: base, local: myEdit, remote: theirOrder);
    expect(_ids(merged), ['b', 'a', 'c']);
    expect(merged.days.single.stops[1].tip, 't');
  });

  test('plan fields: each side keeps what it changed', () {
    final local = _plan(base.days.single.stops, title: 'Mine');
    final remote = base.copyWith(overview: 'Their overview');
    final merged = mergePlans(base: base, local: local, remote: remote);
    expect(merged.title, 'Mine');
    expect(merged.overview, 'Their overview');
  });

  test('packing ticks from both sides apply', () {
    final b = _plan([_s('a')], packed: ['water', 'hat']);
    final l = _plan([_s('a')], packed: ['water', 'hat', 'torch']);
    final r = _plan([_s('a')], packed: ['hat', 'shoes']); // Unticked water.
    final merged = mergePlans(base: b, local: l, remote: r);
    expect(merged.packingChecked.toSet(), {'hat', 'shoes', 'torch'});
  });

  test('membership always comes from the cloud; newest time is kept', () {
    final local = _plan(
      base.days.single.stops,
      members: ['owner', 'friend', 'sneaky'],
      updated: DateTime(2026, 11, 17, 10),
    );
    final remote = _plan(
      base.days.single.stops,
      members: ['owner'],
      updated: DateTime(2026, 11, 17, 9),
    );
    final merged = mergePlans(base: base, local: local, remote: remote);
    expect(merged.memberUids, ['owner']);
    expect(merged.updatedAt, DateTime(2026, 11, 17, 10));
  });
}
