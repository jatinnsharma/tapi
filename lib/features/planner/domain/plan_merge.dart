import 'dart:convert';

import 'trip_plan.dart';

/// Three-way merge of a shared trip, so two people editing it at once both
/// keep their changes.
///
/// [base] is the cloud copy this phone's edit started from, [local] is this
/// phone's edited copy, and [remote] is what the cloud holds now (perhaps
/// edited by a friend since [base]). Every field (of the plan, each day and
/// each stop) takes whichever side changed it since [base]; when both
/// changed the very same field, [local] wins (it is the newest save).
///
/// - Stops are matched by id: stops added on either side are kept, a stop
///   deleted on one side is dropped unless the other side edited it, and
///   the order follows whichever side reordered.
/// - Packed items merge as a set: ticks and unticks from both sides apply.
/// - Who the trip is shared with comes from [remote], except that the owner
///   ([savedByOwner]) keeps their own change to `memberUids`.
TripPlan mergePlans({
  required TripPlan base,
  required TripPlan local,
  required TripPlan remote,
  bool savedByOwner = false,
}) {
  final b = base.toJson(), l = local.toJson(), r = remote.toJson();
  final merged = _mergeFields(
    b,
    l,
    r,
    special: const {
      'days',
      'packingChecked',
      'ownerUid',
      'memberUids',
      'updatedAt',
      'cloudSynced',
    },
  );

  merged['packingChecked'] = _mergeSet(
    _strings(b['packingChecked']),
    _strings(l['packingChecked']),
    _strings(r['packingChecked']),
  );
  merged['days'] = _mergeDays(
    _maps(b['days']),
    _maps(l['days']),
    _maps(r['days']),
  );
  merged['ownerUid'] = r['ownerUid'];
  // Only the owner may change who it's shared with (the rules agree).
  merged['memberUids'] =
      savedByOwner && !_same(l['memberUids'], b['memberUids'])
      ? l['memberUids']
      : r['memberUids'];
  final newest = [local.updatedAt, remote.updatedAt]
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, d) => a == null || d.isAfter(a) ? d : a);
  merged['updatedAt'] = newest?.toIso8601String();
  merged['cloudSynced'] = remote.cloudSynced;
  return TripPlan.fromJson(merged);
}

bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// Field by field: local's value if local changed it since base, else
/// remote's. Keys in [special] are left for the caller.
Map<String, dynamic> _mergeFields(
  Map<String, dynamic> b,
  Map<String, dynamic> l,
  Map<String, dynamic> r, {
  Set<String> special = const {},
}) => {
  for (final key in {...b.keys, ...l.keys, ...r.keys})
    if (!special.contains(key)) key: _same(l[key], b[key]) ? r[key] : l[key],
};

List<String> _strings(Object? v) => [
  for (final x in (v as List?) ?? const []) '$x',
];

List<Map<String, dynamic>> _maps(Object? v) => [
  for (final x in (v as List?) ?? const []) Map<String, dynamic>.from(x as Map),
];

List<String> _mergeSet(List<String> b, List<String> l, List<String> r) {
  final base = b.toSet(), local = l.toSet(), remote = r.toSet();
  final added = local.difference(base);
  final removed = base.difference(local);
  return [
    for (final x in {...r, ...l})
      if ((remote.contains(x) || added.contains(x)) && !removed.contains(x)) x,
  ];
}

/// Days by position. The number of days follows whichever side changed it.
List<Map<String, dynamic>> _mergeDays(
  List<Map<String, dynamic>> b,
  List<Map<String, dynamic>> l,
  List<Map<String, dynamic>> r,
) {
  final count = l.length != b.length ? l.length : r.length;
  return [
    for (var i = 0; i < count; i++)
      _mergeDay(
        i < b.length ? b[i] : const {},
        i < l.length ? l[i] : const {},
        i < r.length ? r[i] : (i < l.length ? l[i] : const {}),
      ),
  ];
}

Map<String, dynamic> _mergeDay(
  Map<String, dynamic> b,
  Map<String, dynamic> l,
  Map<String, dynamic> r,
) => {
  ..._mergeFields(b, l, r, special: const {'stops'}),
  'stops': mergeStops(_maps(b['stops']), _maps(l['stops']), _maps(r['stops'])),
};

/// Three-way merge of a day's stops (as JSON maps with an `id`).
List<Map<String, dynamic>> mergeStops(
  List<Map<String, dynamic>> base,
  List<Map<String, dynamic>> local,
  List<Map<String, dynamic>> remote,
) {
  Map<String, Map<String, dynamic>> byId(List<Map<String, dynamic>> list) => {
    for (final s in list) s['id'] as String: s,
  };
  final b = byId(base), l = byId(local), r = byId(remote);

  // Which stops survive, and in which version.
  final kept = <String, Map<String, dynamic>>{};
  for (final id in {...l.keys, ...r.keys, ...b.keys}) {
    final inB = b[id], inL = l[id], inR = r[id];
    if (inB == null) {
      kept[id] = inL ?? inR!; // Added on one (or both) sides.
    } else if (inL == null && inR == null) {
      continue; // Deleted on both.
    } else if (inL == null) {
      if (!_same(inR, inB)) kept[id] = inR!; // Friend edited what I deleted.
    } else if (inR == null) {
      if (!_same(inL, inB)) kept[id] = inL; // I edited what they deleted.
    } else {
      kept[id] = _same(inL, inB) ? inR : inL;
    }
  }

  // Order: whoever reordered the stops they share with the base wins.
  List<String> commonOrder(List<Map<String, dynamic>> list) => [
    for (final s in list)
      if (b.containsKey(s['id'])) s['id'] as String,
  ];
  final localReordered = !_same(commonOrder(local), [
    for (final id in commonOrder(base))
      if (l.containsKey(id)) id,
  ]);
  final primary = localReordered ? local : remote;
  final secondary = localReordered ? remote : local;

  final order = [
    for (final s in primary)
      if (kept.containsKey(s['id'])) s['id'] as String,
  ];
  // Stops only the other side has: placed after the stop before them there.
  for (var i = 0; i < secondary.length; i++) {
    final id = secondary[i]['id'] as String;
    if (!kept.containsKey(id) || order.contains(id)) continue;
    var at = 0;
    for (var j = i - 1; j >= 0; j--) {
      final before = order.indexOf(secondary[j]['id'] as String);
      if (before >= 0) {
        at = before + 1;
        break;
      }
    }
    order.insert(at, id);
  }
  // Survivors only the base still orders (edited on one side, deleted on
  // the other) go last.
  for (final id in kept.keys) {
    if (!order.contains(id)) order.add(id);
  }
  return [for (final id in order) kept[id]!];
}
