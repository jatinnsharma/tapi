import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/social/domain/friend_challenge.dart';

void main() {
  group('FriendChallenge Domain Model', () {
    final now = DateTime.now();
    final challenge = FriendChallenge(
      id: 'fc-101',
      challengerUid: 'uid-alice',
      challengerName: 'Alice',
      challengedUid: 'uid-bob',
      challengedName: 'Bob',
      type: ChallengeGoalType.moreTrekKm,
      targetValue: '5000',
      createdAt: now.subtract(const Duration(hours: 2)),
      expiresAt: now.add(const Duration(days: 3)),
      status: FriendChallengeStatus.active,
      challengerProgress: 3200,
      challengedProgress: 2800,
    );

    test('participant and progress helpers work correctly', () {
      expect(challenge.isParticipant('uid-alice'), isTrue);
      expect(challenge.isParticipant('uid-bob'), isTrue);
      expect(challenge.isParticipant('uid-charlie'), isFalse);

      expect(challenge.otherName('uid-alice'), 'Bob');
      expect(challenge.otherName('uid-bob'), 'Alice');

      expect(challenge.myProgress('uid-alice'), 3200);
      expect(challenge.theirProgress('uid-alice'), 2800);

      expect(challenge.myProgress('uid-bob'), 2800);
      expect(challenge.theirProgress('uid-bob'), 3200);

      expect(challenge.isExpired, isFalse);
    });

    test('isExpired detects past expiration dates', () {
      final trulyExpired = FriendChallenge(
        id: 'fc-expired',
        challengerUid: 'uid-alice',
        challengerName: 'Alice',
        challengedUid: 'uid-bob',
        challengedName: 'Bob',
        type: ChallengeGoalType.firstToReach,
        targetValue: 'loc-rock-garden',
        targetPlaceName: 'Rock Garden',
        createdAt: now.subtract(const Duration(days: 10)),
        expiresAt: now.subtract(const Duration(days: 3)),
      );

      expect(trulyExpired.isExpired, isTrue);
      expect(trulyExpired.type.label, contains('First to Reach'));
    });

    test('serialization and deserialization roundtrip', () {
      final map = challenge.toMap();
      final restored = FriendChallenge.fromMap(map, 'fc-101');

      expect(restored.id, challenge.id);
      expect(restored.challengerUid, challenge.challengerUid);
      expect(restored.challengerName, challenge.challengerName);
      expect(restored.challengedUid, challenge.challengedUid);
      expect(restored.challengedName, challenge.challengedName);
      expect(restored.type, challenge.type);
      expect(restored.targetValue, challenge.targetValue);
      expect(restored.challengerProgress, challenge.challengerProgress);
      expect(restored.challengedProgress, challenge.challengedProgress);
      expect(restored.status, challenge.status);
    });

    test('copyWith properly overrides values', () {
      final completed = challenge.copyWith(
        status: FriendChallengeStatus.completed,
        challengerProgress: 5200,
        winnerUid: 'uid-alice',
      );

      expect(completed.status, FriendChallengeStatus.completed);
      expect(completed.challengerProgress, 5200);
      expect(completed.challengedProgress, 2800);
      expect(completed.winnerUid, 'uid-alice');
    });
  });
}
