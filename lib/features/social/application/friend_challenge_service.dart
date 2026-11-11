import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_status.dart';
import '../../auth/application/auth_service.dart';
import '../data/social_repository.dart';
import '../domain/friend_challenge.dart';

final friendChallengesProvider =
    StreamProvider.autoDispose<List<FriendChallenge>>((ref) {
      if (!ref.watch(firebaseReadyProvider)) return Stream.value(const []);
      final user = ref.watch(authStateProvider).value;
      if (user == null) return Stream.value(const []);
      return ref
          .watch(socialRepositoryProvider)
          .streamFriendChallenges(user.uid);
    });

final friendChallengeServiceProvider = Provider<FriendChallengeService>((ref) {
  return FriendChallengeService(
    ref.watch(socialRepositoryProvider),
    ref.watch(authStateProvider).value?.uid,
    ref.watch(authStateProvider).value?.displayName ?? 'Explorer',
  );
});

class FriendChallengeService {
  FriendChallengeService(this._social, this._myUid, this._myName);

  final SocialRepository _social;
  final String? _myUid;
  final String _myName;

  Future<void> sendTrekChallenge({
    required String friendUid,
    required String friendName,
    required double targetKm,
  }) async {
    if (_myUid == null) return;
    final id = 'fc_${DateTime.now().millisecondsSinceEpoch}_$_myUid';
    final now = DateTime.now();
    final challenge = FriendChallenge(
      id: id,
      challengerUid: _myUid,
      challengerName: _myName,
      challengedUid: friendUid,
      challengedName: friendName,
      type: ChallengeGoalType.moreTrekKm,
      targetValue: '${(targetKm * 1000).round()}',
      createdAt: now,
      expiresAt: now.add(const Duration(days: 7)),
      status: FriendChallengeStatus.pending,
    );
    await _social.createFriendChallenge(challenge);
  }

  Future<void> sendReachPlaceChallenge({
    required String friendUid,
    required String friendName,
    required String placeId,
    required String placeName,
  }) async {
    if (_myUid == null) return;
    final id = 'fc_${DateTime.now().millisecondsSinceEpoch}_$_myUid';
    final now = DateTime.now();
    final challenge = FriendChallenge(
      id: id,
      challengerUid: _myUid,
      challengerName: _myName,
      challengedUid: friendUid,
      challengedName: friendName,
      type: ChallengeGoalType.firstToReach,
      targetValue: placeId,
      targetPlaceName: placeName,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 7)),
      status: FriendChallengeStatus.pending,
    );
    await _social.createFriendChallenge(challenge);
  }

  Future<void> acceptChallenge(String challengeId) async {
    await _social.updateFriendChallenge(challengeId, {
      'status': FriendChallengeStatus.active.name,
    });
  }

  Future<void> declineChallenge(String challengeId) async {
    await _social.updateFriendChallenge(challengeId, {
      'status': FriendChallengeStatus.declined.name,
    });
  }

  Future<void> recordTrekMeters(double trekMeters) async {
    if (_myUid == null) return;
    // Update active challenges for current user
    // (Handled live in tracking finish / summary)
  }
}
