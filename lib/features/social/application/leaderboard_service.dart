import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_status.dart';
import '../../auth/application/auth_service.dart';
import '../../tracking/data/adventure_repository.dart';
import '../data/social_repository.dart';
import '../domain/explorer_profile.dart';
import '../domain/leaderboard.dart';

/// How many explorers the global ranking lists. Anyone below still sees
/// their exact rank (counted on the server).
const globalLeaderboardSize = 50;

/// A ranking by XP (weekly or all-time), for everyone or for you and your friends.
///
/// Before ranking, the user's own XP (which lives on the device) is copied
/// to their profile, so their position is current even if they earned XP
/// before signing up. People who blocked them, or whom they blocked, are
/// left out, as in the Explorers list.
final leaderboardProvider = FutureProvider.autoDispose
    .family<Leaderboard, LeaderboardFilter>((ref, filter) async {
      if (!ref.watch(firebaseReadyProvider)) {
        return const Leaderboard(entries: [], me: null);
      }
      final user = ref.watch(authStateProvider).value;
      if (user == null) return const Leaderboard(entries: [], me: null);
      final uid = user.uid;
      final social = ref.watch(socialRepositoryProvider);
      final adventureRepo = ref.watch(adventureRepositoryProvider);

      final currentKey = AdventureRepository.currentWeekKey();
      final localTotalXp = await adventureRepo.getTotalXp();
      final localWeeklyXp = await adventureRepo.getWeeklyXp();
      final myProfile = await social.getProfile(uid);

      if (myProfile != null &&
          (myProfile.totalXp != localTotalXp ||
              myProfile.weeklyXp != localWeeklyXp ||
              myProfile.weeklyKey != currentKey)) {
        try {
          await social.setTotalXp(
            uid,
            localTotalXp,
            weeklyXp: localWeeklyXp,
            weeklyKey: currentKey,
          );
        } catch (_) {
          // Ranking still works with the last synced value.
        }
      }

      final isWeekly = filter.timeframe == RankingTimeframe.thisWeek;
      final myXp = myProfile == null
          ? null
          : (isWeekly ? localWeeklyXp : localTotalXp);

      final hidden = {
        ...await social.getBlockedUids(uid),
        ...await social.getUidsWhoBlockedMe(uid),
      };

      int resolveXp(ExplorerProfile p) {
        if (isWeekly) {
          if (p.uid == uid && myXp != null) return myXp;
          return p.weeklyKey == currentKey ? p.weeklyXp : 0;
        } else {
          if (p.uid == uid && myXp != null) return myXp;
          return p.totalXp;
        }
      }

      ({String uid, String name, int xp, String? photoUrl}) row(
        ExplorerProfile p,
      ) => (
        uid: p.uid,
        name: p.displayName,
        xp: resolveXp(p),
        photoUrl: p.photoUrl,
      );

      switch (filter.scope) {
        case RankingScope.global:
          final top = isWeekly
              ? await social.getTopExplorersByWeeklyXp(
                  limit: globalLeaderboardSize,
                )
              : await social.getTopExplorersByXp(limit: globalLeaderboardSize);
          final entries = rankByXp([
            for (final p in top)
              if (!hidden.contains(p.uid)) row(p),
          ], myUid: uid);
          final listed = entries.where((e) => e.isMe).firstOrNull;
          if (listed != null || myProfile == null || myXp == null) {
            return Leaderboard(entries: entries, me: listed);
          }
          final above = isWeekly
              ? await social.countExplorersWithMoreWeeklyXp(myXp)
              : await social.countExplorersWithMoreXp(myXp);
          return Leaderboard(
            entries: entries,
            me: LeaderboardEntry(
              uid: uid,
              displayName: myProfile.displayName,
              totalXp: myXp,
              rank: above + 1,
              isMe: true,
              photoUrl: myProfile.photoUrl,
            ),
          );

        case RankingScope.friends:
          final friendUids = [
            for (final f in await social.getFriendshipsFor(uid))
              if (f.isAccepted && !hidden.contains(f.otherUid(uid)))
                f.otherUid(uid),
          ];
          final friends = await Future.wait(friendUids.map(social.getProfile));
          final entries = rankByXp([
            ?(myProfile == null ? null : row(myProfile)),
            for (final p in friends)
              if (p != null) row(p),
          ], myUid: uid);
          return Leaderboard(
            entries: entries,
            me: entries.where((e) => e.isMe).firstOrNull,
          );
      }
    });
