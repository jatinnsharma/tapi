import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/auth/application/auth_service.dart';
import 'package:real_world_exploration/features/social/data/social_repository.dart';
import 'package:real_world_exploration/features/social/domain/group_radar.dart';
import 'package:real_world_exploration/features/social/domain/live_location.dart';
import 'package:real_world_exploration/features/social/presentation/group_live_map_screen.dart';

final _now = DateTime(2026, 11, 17, 10);

/// [metersNorth] of a fixed spot (1° latitude ≈ 111 km).
LiveLocation _at(
  String uid,
  double metersNorth, {
  Duration age = Duration.zero,
  String? ping,
  Duration pingAge = Duration.zero,
}) => LiveLocation(
  uid: uid,
  displayName: 'User $uid',
  latitude: 25.3 + metersNorth / 111195,
  longitude: 83.0,
  adventureTitle: 'Ghat walk',
  updatedAt: _now.subtract(age),
  sharing: true,
  groupAdventureId: 'g1',
  statusNote: ping,
  statusAt: ping == null ? null : _now.subtract(pingAge),
);

class _FakeSocial implements SocialRepository {
  _FakeSocial(this.live);

  final List<LiveLocation> live;

  @override
  Stream<List<LiveLocation>> watchGroupLiveLocations(String id) =>
      Stream.value(live);
  @override
  Future<String?> getGroupAdventureLeader(String id) async => 'lead';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('groupRadar', () {
    test('distance from the leader sets each ring', () {
      final radar = groupRadar(
        [_at('lead', 0), _at('close', 30), _at('mid', 100), _at('far', 400)],
        leaderUid: 'lead',
        now: _now,
      );
      final status = {for (final m in radar) m.location.uid: m.status};
      expect(status, {
        'lead': RadarStatus.near,
        'close': RadarStatus.near,
        'mid': RadarStatus.drifting,
        'far': RadarStatus.separated,
      });
      // Leader first, then the furthest away.
      expect(radar.map((m) => m.location.uid), ['lead', 'far', 'mid', 'close']);
      expect(radar[1].metersAway, closeTo(400, 2));
    });

    test('an out-of-date position is stale, not judged', () {
      final radar = groupRadar(
        [_at('lead', 0), _at('old', 900, age: const Duration(minutes: 11))],
        leaderUid: 'lead',
        now: _now,
      );
      expect(radar.last.status, RadarStatus.stale);
      expect(radar.last.metersAway, isNull);
    });

    test('without the leader live, distance is from the group centre', () {
      final radar = groupRadar(
        [_at('a', 0), _at('b', 40), _at('c', 500)],
        leaderUid: 'lead',
        now: _now,
      );
      final byUid = {for (final m in radar) m.location.uid: m};
      // Centre is ~180 m north: c (~320 m away) has strayed.
      expect(byUid['c']!.status, RadarStatus.separated);
      expect(byUid['a']!.status, RadarStatus.separated);
      expect(byUid['b']!.status, RadarStatus.drifting);
    });

    test('pings show for 30 minutes', () {
      final fresh = groupRadar(
        [
          _at(
            'a',
            0,
            ping: 'Wait for me!',
            pingAge: const Duration(minutes: 5),
          ),
        ],
        leaderUid: null,
        now: _now,
      ).single;
      expect(fresh.pingAt(_now), 'Wait for me!');
      final old = groupRadar(
        [
          _at(
            'a',
            0,
            ping: 'Wait for me!',
            pingAge: const Duration(minutes: 31),
          ),
        ],
        leaderUid: null,
        now: _now,
      ).single;
      expect(old.pingAt(_now), isNull);
    });
  });

  test('a ping round-trips with the live location', () {
    final l = _at('a', 0, ping: 'Stopping here for chai');
    final back = LiveLocation.fromMap(l.toMap());
    expect(back.statusNote, 'Stopping here for chai');
    expect(back.statusAt, l.statusAt);
    // Older docs without a ping still read.
    final plain = LiveLocation.fromMap(_at('b', 0).toMap());
    expect(plain.statusNote, isNull);
  });

  testWidgets('the radar warns about someone who strayed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          socialRepositoryProvider.overrideWithValue(
            _FakeSocial([
              _at('lead', 0).copyWithNow(),
              _at('far', 400).copyWithNow(),
            ]),
          ),
        ],
        child: const MaterialApp(
          home: GroupLiveMapScreen(adventureId: 'g1', adventureName: 'Ghats'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('User far is more than 150 m'), findsOneWidget);
    expect(find.text('Leader'), findsOneWidget);
  });
}

extension on LiveLocation {
  /// The same position, updated just now (the screen uses the real clock).
  LiveLocation copyWithNow() => LiveLocation(
    uid: uid,
    displayName: displayName,
    latitude: latitude,
    longitude: longitude,
    adventureTitle: adventureTitle,
    updatedAt: DateTime.now(),
    sharing: sharing,
    groupAdventureId: groupAdventureId,
  );
}
