import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/profile/domain/achievement.dart';

// Targets 5 / 25 / 100 with rewards 50 / 150 / 400.
const _def = AchievementDef(
  id: 'test',
  title: 'Test',
  icon: Icons.hiking,
  metric: AchievementMetric.distanceKm,
  targets: [5, 25, 100],
  unit: 'km',
);

AchievementProgress _p(double value, {int claimed = 0}) =>
    AchievementProgress(def: _def, value: value, claimedStars: claimed);

void main() {
  group('Achievement definitions', () {
    test(
      'every achievement has three increasing targets and three rewards',
      () {
        for (final def in achievementDefs) {
          expect(def.targets, hasLength(3), reason: def.id);
          expect(def.rewards, hasLength(3), reason: def.id);
          expect(def.targets[0] < def.targets[1], isTrue, reason: def.id);
          expect(def.targets[1] < def.targets[2], isTrue, reason: def.id);
          expect(def.rewards[0] < def.rewards[1], isTrue, reason: def.id);
          expect(def.rewards[1] < def.rewards[2], isTrue, reason: def.id);
        }
      },
    );

    test('ids are unique (they key the saved claims)', () {
      final ids = [for (final d in achievementDefs) d.id];
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every metric is used by exactly one achievement', () {
      final used = [for (final d in achievementDefs) d.metric];
      expect(used.toSet(), hasLength(AchievementMetric.values.length));
      expect(used, hasLength(AchievementMetric.values.length));
    });
  });

  group('Stars', () {
    test('none before the first target', () {
      expect(_p(4.9).earnedStars, 0);
      expect(_p(0).hasClaimable, isFalse);
    });

    test('a star is earned exactly at its target', () {
      expect(_p(5).earnedStars, 1);
      expect(_p(24.9).earnedStars, 1);
      expect(_p(25).earnedStars, 2);
      expect(_p(100).earnedStars, 3);
      expect(_p(500).earnedStars, 3);
    });

    test('is maxed only with all three', () {
      expect(_p(99).isMaxed, isFalse);
      expect(_p(100).isMaxed, isTrue);
      expect(_p(100).nextTarget, isNull);
    });
  });

  group('Claiming', () {
    test('earned stars are claimable until claimed', () {
      expect(_p(5).claimableStars, 1);
      expect(_p(5, claimed: 1).claimableStars, 0);
      expect(_p(5, claimed: 1).hasClaimable, isFalse);
    });

    test('pays the reward of each earned, unclaimed star', () {
      expect(_p(5).claimableXp, 50);
      expect(_p(25).claimableXp, 50 + 150);
      expect(_p(100).claimableXp, 50 + 150 + 400);
    });

    test('pays only the stars not yet claimed', () {
      expect(_p(25, claimed: 1).claimableXp, 150);
      expect(_p(100, claimed: 2).claimableXp, 400);
      expect(_p(100, claimed: 3).claimableXp, 0);
    });

    test('a bad saved value cannot produce a negative claim', () {
      // e.g. data restored after progress was lost.
      expect(_p(5, claimed: 3).claimableStars, 0);
      expect(_p(5, claimed: 3).claimableXp, 0);
    });
  });

  group('Memories per trip (stops farming one photo)', () {
    final counted = {'t1', 't2'};

    test('only items from counted trips count', () {
      expect(
        countCappedPerTrip(
          ['t1', 't1', 't3', null],
          countedTrips: counted,
          cap: 5,
        ),
        2,
      );
    });

    test('one trip contributes at most the cap', () {
      final fifty = List<String?>.filled(50, 't1');
      expect(countCappedPerTrip(fifty, countedTrips: counted, cap: 5), 5);
    });

    test('more memories need more trips', () {
      final items = <String?>[
        ...List.filled(30, 't1'),
        ...List.filled(30, 't2'),
      ];
      expect(countCappedPerTrip(items, countedTrips: counted, cap: 5), 10);
    });

    test('no memories, or no counted trips, is zero', () {
      expect(countCappedPerTrip(const [], countedTrips: counted, cap: 5), 0);
      expect(
        countCappedPerTrip(['t1', 't1'], countedTrips: const {}, cap: 5),
        0,
      );
    });
  });

  group('Progress bar', () {
    test('runs from the previous target to the next', () {
      expect(_p(0).progressToNext, 0);
      expect(_p(2.5).progressToNext, 0.5); // halfway to 5
      expect(_p(15).progressToNext, 0.5); // halfway from 5 to 25
      expect(_p(62.5).progressToNext, 0.5); // halfway from 25 to 100
    });

    test('is full once maxed', () {
      expect(_p(100).progressToNext, 1);
    });

    test('labels the next target, and never shows more than it', () {
      expect(_p(3.7).progressLabel, '3 / 5 km');
      expect(_p(25).progressLabel, '25 / 100 km');
      expect(_p(100).progressLabel, 'All stars earned');
    });
  });
}
