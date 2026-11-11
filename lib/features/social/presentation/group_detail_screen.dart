import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../auth/application/auth_service.dart';
import '../data/social_repository.dart';
import '../domain/explorer_profile.dart';
import '../domain/group_safety_status.dart';

class _GroupDetail {
  const _GroupDetail({required this.members, required this.totalXp});

  final List<ExplorerProfile> members;
  final int totalXp;
}

final _groupDetailProvider = FutureProvider.autoDispose
    .family<_GroupDetail?, String>((ref, groupId) async {
      final repository = ref.watch(socialRepositoryProvider);
      final group = await repository.getGroup(groupId);
      if (group == null) return null;

      final memberUids = [group.createdBy, ...group.memberUids];
      final members = <ExplorerProfile>[];
      for (final uid in memberUids) {
        final profile = await repository.getProfile(uid);
        if (profile != null) members.add(profile);
      }
      final totalXp = await repository.getGroupTotalXp(group);
      return _GroupDetail(members: members, totalXp: totalXp);
    });

final _groupSafetyStatusesProvider = StreamProvider.autoDispose
    .family<List<GroupSafetyStatus>, String>((ref, groupId) {
      return ref
          .watch(socialRepositoryProvider)
          .streamGroupSafetyStatuses(ChatParent.group, groupId);
    });

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(_groupDetailProvider(groupId));
    final safetyStatusesAsync = ref.watch(
      _groupSafetyStatusesProvider(groupId),
    );
    final user = ref.watch(authStateProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(groupName),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            tooltip: 'Group Chat',
            onPressed: () => context.push(
              '/groups/$groupId/chat?name=${Uri.encodeComponent(groupName)}',
            ),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Padding(
          padding: AppSpacing.page,
          child: Shimmer(
            child: Column(
              children: [
                SkeletonBox(height: 130, radius: 32),
                SizedBox(height: 16),
                SkeletonBox(height: 72, radius: 24),
                SizedBox(height: 12),
                SkeletonBox(height: 72, radius: 24),
              ],
            ),
          ),
        ),
        error: (error, stack) => Padding(
          padding: AppSpacing.page,
          child: EmptyStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load group',
            message: '$error',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(_groupDetailProvider(groupId)),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const Padding(
              padding: AppSpacing.page,
              child: EmptyStateCard(
                icon: Icons.search_off_rounded,
                title: 'Group not found',
                message: 'This group could not be found.',
              ),
            );
          }

          final safetyStatuses = safetyStatusesAsync.value ?? [];
          final statusByUid = {for (final s in safetyStatuses) s.uid: s};

          return ListView(
            padding: AppSpacing.page,
            children: [
              FadeSlideIn(
                child: HeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Group XP',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${detail.totalXp}',
                        style: const TextStyle(
                          color: AppTheme.amber,
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      MetaPill(
                        icon: Icons.groups_rounded,
                        label:
                            'Combined total from ${detail.members.length} members',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (user != null && detail.members.any((m) => m.uid == user.uid))
                FilledButton.icon(
                  onPressed: () =>
                      _updateMySafetyStatus(context, ref, user.uid),
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: const Text('Update My Safety Status'),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              const SectionHeader(
                title: 'Safety Board',
                padding: EdgeInsets.only(top: 20, bottom: 12),
              ),
              for (final member in detail.members)
                SoftCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  radius: 22,
                  child: Row(
                    children: [
                      AppAvatar(initial: member.displayName, size: 44),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.ink,
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                final status = statusByUid[member.uid];
                                if (status == null) {
                                  return const Text(
                                    'No recent status',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppTheme.inkMuted,
                                    ),
                                  );
                                }
                                final timeStr =
                                    '${status.timestamp.hour.toString().padLeft(2, '0')}:${status.timestamp.minute.toString().padLeft(2, '0')}';
                                return Text(
                                  '${_statusLabel(status.status)} at $timeStr',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: _statusColor(status.status),
                                    fontWeight: FontWeight.w800,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${member.totalXp} XP',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.amberText,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateMySafetyStatus(
    BuildContext context,
    WidgetRef ref,
    String uid,
  ) async {
    final status = await showDialog<SafetyStatusValue>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Safety Status'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, SafetyStatusValue.ok),
            child: const Text(
              '✅ I am Safe',
              style: TextStyle(color: Colors.green, fontSize: 16),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, SafetyStatusValue.offRoute),
            child: const Text(
              '⚠️ Off Route / Delayed',
              style: TextStyle(color: Colors.orange, fontSize: 16),
            ),
          ),
        ],
      ),
    );

    if (status != null && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      await ref
          .read(socialRepositoryProvider)
          .updateGroupSafetyStatus(
            ChatParent.group,
            groupId,
            GroupSafetyStatus(
              uid: uid,
              status: status,
              timestamp: DateTime.now(),
            ),
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Safety status updated for group.')),
      );
    }
  }

  String _statusLabel(SafetyStatusValue status) {
    switch (status) {
      case SafetyStatusValue.ok:
        return '✅ Safe';
      case SafetyStatusValue.offRoute:
        return '⚠️ Off Route';
    }
  }

  Color _statusColor(SafetyStatusValue status) {
    switch (status) {
      case SafetyStatusValue.ok:
        return Colors.green;
      case SafetyStatusValue.offRoute:
        return Colors.orange;
    }
  }
}
