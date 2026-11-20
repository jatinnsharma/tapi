import 'package:latlong2/latlong.dart';

import 'live_location.dart';

/// Within this many metres of the reference, a member is with the group.
const radarNearMeters = 50.0;

/// Beyond this many metres, a member has strayed (the alert shows).
const radarSeparatedMeters = 150.0;

/// A position older than this is shown as out of date.
const radarStaleAfter = Duration(minutes: 10);

/// A ping older than this is no longer shown.
const radarPingFor = Duration(minutes: 30);

/// Quick pings a member can send the group.
const radarPings = [
  'Stopping here for chai',
  'Wait for me!',
  'Regroup at the leader',
  'All good, carrying on',
];

enum RadarStatus { near, drifting, separated, stale }

class RadarMember {
  const RadarMember({
    required this.location,
    required this.status,
    required this.metersAway,
    required this.isLeader,
  });

  final LiveLocation location;
  final RadarStatus status;

  /// From the reference point (the leader, or the group's centre); null for
  /// the reference itself.
  final double? metersAway;
  final bool isLeader;

  /// The member's current ping, if recent.
  String? pingAt(DateTime now) {
    final at = location.statusAt;
    final note = location.statusNote;
    if (note == null || at == null) return null;
    return now.difference(at) <= radarPingFor ? note : null;
  }
}

/// Where everyone is relative to the group: distance from the leader
/// ([leaderUid]) while they're sharing and up to date, else from the centre
/// of the up-to-date members.
List<RadarMember> groupRadar(
  List<LiveLocation> live, {
  required String? leaderUid,
  required DateTime now,
}) {
  bool fresh(LiveLocation l) => now.difference(l.updatedAt) <= radarStaleAfter;
  LatLng at(LiveLocation l) => LatLng(l.latitude, l.longitude);

  final current = live.where(fresh).toList();
  final leader = current.where((l) => l.uid == leaderUid).firstOrNull;
  final LatLng? reference = leader != null
      ? at(leader)
      : current.isEmpty
      ? null
      : LatLng(
          current.map((l) => l.latitude).reduce((a, b) => a + b) /
              current.length,
          current.map((l) => l.longitude).reduce((a, b) => a + b) /
              current.length,
        );

  const distance = Distance();
  final members = [
    for (final l in live)
      () {
        final isLeader = l.uid == leaderUid;
        if (!fresh(l)) {
          return RadarMember(
            location: l,
            status: RadarStatus.stale,
            metersAway: null,
            isLeader: isLeader,
          );
        }
        final meters = (isLeader && leader != null) || reference == null
            ? null
            : distance(reference, at(l));
        final status = meters == null || meters <= radarNearMeters
            ? RadarStatus.near
            : meters <= radarSeparatedMeters
            ? RadarStatus.drifting
            : RadarStatus.separated;
        return RadarMember(
          location: l,
          status: status,
          metersAway: meters,
          isLeader: isLeader,
        );
      }(),
  ];
  // Leader first, then the furthest away (who needs attention).
  members.sort((a, b) {
    if (a.isLeader != b.isLeader) return a.isLeader ? -1 : 1;
    return (b.metersAway ?? -1).compareTo(a.metersAway ?? -1);
  });
  return members;
}
