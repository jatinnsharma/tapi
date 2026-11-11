import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../data/social_repository.dart';
import '../domain/activity_entry.dart';
import 'social_screen.dart' show mutedUidsProvider;

final _feedProvider = FutureProvider.autoDispose<List<ActivityEntry>>((
  ref,
) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return [];
  final repository = ref.watch(socialRepositoryProvider);
  final friendships = await repository.getFriendshipsFor(uid);
  final friendUids = friendships
      .where((f) => f.isAccepted)
      .map((f) => f.otherUid(uid))
      .toList();
  final entries = await repository.getFeedFor(uid, friendUids);

  // Muting is a purely private preference (unlike blocking), so it's
  // filtered client-side here rather than enforced by a Firestore rule.
  final mutedUids = await ref.watch(mutedUidsProvider.future);
  return entries.where((entry) => !mutedUids.contains(entry.uid)).toList();
});

class ActivityFeedScreen extends ConsumerWidget {
  const ActivityFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(_feedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity Feed')),
      body: feedAsync.when(
        loading: () => const Padding(
          padding: AppSpacing.page,
          child: Shimmer(
            child: Column(
              children: [
                SkeletonBox(height: 76, radius: 24),
                SizedBox(height: 12),
                SkeletonBox(height: 76, radius: 24),
                SizedBox(height: 12),
                SkeletonBox(height: 76, radius: 24),
              ],
            ),
          ),
        ),
        error: (error, stack) => Padding(
          padding: AppSpacing.page,
          child: EmptyStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load the feed',
            message: '$error',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(_feedProvider),
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const Padding(
              padding: AppSpacing.page,
              child: EmptyStateCard(
                icon: Icons.dynamic_feed_rounded,
                title: 'No activity yet',
                message: 'No activity yet. Complete an adventure, or add some friends, to see it here.',
              ),
            );
          }
          return RefreshIndicator(
            color: AppTheme.forest,
            onRefresh: () async => ref.invalidate(_feedProvider),
            child: ListView.builder(
              padding: AppSpacing.page,
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return SoftCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      AppAvatar(initial: entry.displayName, size: 46),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.displayName} completed "${entry.title}"',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                                color: AppTheme.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${entry.distanceKm.toStringAsFixed(1)} km • +${entry.xpEarned} XP • '
                              '${_relativeTime(entry.timestamp)}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _relativeTime(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}
