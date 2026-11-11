import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../application/friend_challenge_service.dart';
import '../application/friends_service.dart';
import '../domain/friend_challenge.dart';

class FriendChallengesSection extends ConsumerWidget {
  const FriendChallengesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengesAsync = ref.watch(friendChallengesProvider);
    final myUid = ref.watch(authStateProvider).value?.uid ?? '';

    return challengesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (challenges) {
        final activeOrPending = challenges
            .where(
              (c) =>
                  c.status == FriendChallengeStatus.active ||
                  c.status == FriendChallengeStatus.pending,
            )
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.sports_score_rounded,
                    color: AppTheme.forest,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Friend Challenges',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: AppTheme.ink,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _openNewChallengeDialog(context, ref),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Challenge'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.forest,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (activeOrPending.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: SoftCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.forest.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.flag_circle_rounded,
                          color: AppTheme.forest,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No active challenges',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: AppTheme.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Race friends to trek km or be the first to reach a landmark!',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                itemCount: activeOrPending.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final challenge = activeOrPending[index];
                  return _ChallengeCard(challenge: challenge, myUid: myUid);
                },
              ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  void _openNewChallengeDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => const _NewChallengeSheet(),
    );
  }
}

class _ChallengeCard extends ConsumerWidget {
  const _ChallengeCard({required this.challenge, required this.myUid});

  final FriendChallenge challenge;
  final String myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(friendChallengeServiceProvider);
    final isChallenger = challenge.challengerUid == myUid;
    final otherName = challenge.otherName(myUid);
    final isPending = challenge.status == FriendChallengeStatus.pending;
    final targetMeters = double.tryParse(challenge.targetValue) ?? 5000;
    final targetKm = targetMeters / 1000;

    final myVal = challenge.myProgress(myUid);
    final theirVal = challenge.theirProgress(myUid);
    final myRatio = (myVal / targetMeters).clamp(0.0, 1.0);
    final theirRatio = (theirVal / targetMeters).clamp(0.0, 1.0);

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: AppTheme.amberText,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.type == ChallengeGoalType.moreTrekKm
                          ? '${targetKm.toStringAsFixed(1)} km Trek Race'
                          : 'First to reach ${challenge.targetPlaceName ?? "Destination"}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppTheme.ink,
                      ),
                    ),
                    Text(
                      isPending
                          ? (isChallenger
                                ? 'Waiting for $otherName to accept'
                                : '$otherName challenged you!')
                          : 'Race with $otherName',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isPending && !isChallenger) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => service.declineChallenge(challenge.id),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => service.acceptChallenge(challenge.id),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ] else if (!isPending) ...[
            const SizedBox(height: 12),
            // Progress bars
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'You',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${(myVal / 1000).toStringAsFixed(1)} / ${targetKm.toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: myRatio,
                    backgroundColor: Colors.black.withValues(alpha: 0.06),
                    valueColor: const AlwaysStoppedAnimation(
                      AppTheme.primaryGreen,
                    ),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      otherName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${(theirVal / 1000).toStringAsFixed(1)} / ${targetKm.toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: theirRatio,
                    backgroundColor: Colors.black.withValues(alpha: 0.06),
                    valueColor: const AlwaysStoppedAnimation(AppTheme.forest),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NewChallengeSheet extends ConsumerStatefulWidget {
  const _NewChallengeSheet();

  @override
  ConsumerState<_NewChallengeSheet> createState() => _NewChallengeSheetState();
}

class _NewChallengeSheetState extends ConsumerState<_NewChallengeSheet> {
  String? _selectedFriendUid;
  String? _selectedFriendName;
  double _distanceKm = 5.0;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(acceptedFriendsProvider);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Challenge a Friend',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Who will walk the distance first? Compete on trek meters over the next 7 days.',
            style: TextStyle(fontSize: 13, color: AppTheme.inkMuted),
          ),
          const SizedBox(height: 16),
          const Text(
            'Choose Friend',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 8),
          friendsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Could not load friends: $e'),
            data: (friends) {
              if (friends.isEmpty) {
                return const Text(
                  'Add accepted friends from the Social tab first to challenge them.',
                );
              }
              return DropdownButtonFormField<String>(
                initialValue: _selectedFriendUid,
                hint: const Text('Select friend'),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                items: [
                  for (final f in friends)
                    DropdownMenuItem(value: f.uid, child: Text(f.displayName)),
                ],
                onChanged: (uid) {
                  final match = friends.firstWhere((f) => f.uid == uid);
                  setState(() {
                    _selectedFriendUid = uid;
                    _selectedFriendName = match.displayName;
                  });
                },
              );
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Distance Target',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppTheme.forest,
              selectedForegroundColor: Colors.white,
            ),
            segments: const [
              ButtonSegment(value: 3.0, label: Text('3 km')),
              ButtonSegment(value: 5.0, label: Text('5 km')),
              ButtonSegment(value: 10.0, label: Text('10 km')),
            ],
            selected: {_distanceKm},
            onSelectionChanged: (s) => setState(() => _distanceKm = s.first),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selectedFriendUid == null || _submitting
                  ? null
                  : () async {
                      setState(() => _submitting = true);
                      await ref
                          .read(friendChallengeServiceProvider)
                          .sendTrekChallenge(
                            friendUid: _selectedFriendUid!,
                            friendName: _selectedFriendName ?? 'Friend',
                            targetKm: _distanceKm,
                          );
                      if (context.mounted) Navigator.of(context).pop();
                    },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const StadiumBorder(),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Send Challenge',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
