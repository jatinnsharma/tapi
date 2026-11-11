import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../data/social_repository.dart';
import '../domain/group.dart';

final _publicGroupsProvider = FutureProvider.autoDispose<List<Group>>((ref) {
  return ref.watch(socialRepositoryProvider).getPublicGroups();
});

final _myGroupsProvider = FutureProvider.autoDispose<List<Group>>((ref) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return [];
  return ref.watch(socialRepositoryProvider).getMyGroups(uid);
});

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    if (!firebaseReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('Groups')),
        body: const Padding(
          padding: AppSpacing.page,
          child: EmptyStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Groups are unavailable',
            message:
                'Firebase isn\'t configured yet, so Groups are unavailable. '
                'See PENDING_TASKS.md for setup steps.',
          ),
        ),
      );
    }

    final user = ref.watch(authStateProvider).value;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Groups')),
        body: const Padding(
          padding: AppSpacing.page,
          child: EmptyStateCard(
            icon: Icons.diversity_3_outlined,
            title: 'Join the crew',
            message: 'Sign in to create or join a group.',
          ),
        ),
      );
    }

    final publicAsync = ref.watch(_publicGroupsProvider);
    final myAsync = ref.watch(_myGroupsProvider);

    void refresh() {
      ref.invalidate(_publicGroupsProvider);
      ref.invalidate(_myGroupsProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Create Group',
            onPressed: () => _showCreateDialog(context, ref, user.uid, refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.forest,
        onRefresh: () async => refresh(),
        child: ListView(
          padding: AppSpacing.page,
          children: [
            myAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => const SizedBox.shrink(),
              data: (mine) {
                if (mine.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'My Groups'),
                    for (final group in mine)
                      _GroupCard(
                        group: group,
                        myUid: user.uid,
                        onChanged: refresh,
                      ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
            const SectionHeader(title: 'Public Groups'),
            publicAsync.when(
              loading: () => const Shimmer(
                child: Column(
                  children: [
                    SkeletonBox(height: 88, radius: 24),
                    SizedBox(height: 12),
                    SkeletonBox(height: 88, radius: 24),
                  ],
                ),
              ),
              error: (error, stack) => EmptyStateCard(
                icon: Icons.cloud_off_rounded,
                title: 'Could not load groups',
                message: '$error',
                actionLabel: 'Try again',
                onAction: refresh,
              ),
              data: (groups) {
                if (groups.isEmpty) {
                  return const EmptyStateCard(
                    icon: Icons.diversity_3_outlined,
                    title: 'No public groups yet',
                    message: 'No public groups yet. Create one!',
                  );
                }
                return Column(
                  children: [
                    for (final group in groups)
                      _GroupCard(
                        group: group,
                        myUid: user.uid,
                        onChanged: refresh,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(
    BuildContext context,
    WidgetRef ref,
    String myUid,
    VoidCallback onCreated,
  ) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    var visibility = GroupVisibility.public;

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create Group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              DropdownButtonFormField<GroupVisibility>(
                initialValue: visibility,
                decoration: const InputDecoration(labelText: 'Visibility'),
                items: const [
                  DropdownMenuItem(
                    value: GroupVisibility.public,
                    child: Text('Public'),
                  ),
                  DropdownMenuItem(
                    value: GroupVisibility.private,
                    child: Text('Private (invite only)'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => visibility = value ?? visibility),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final user = ref.read(authStateProvider).value;
                final profile = await ref
                    .read(socialRepositoryProvider)
                    .getProfile(myUid);
                final group = Group(
                  id: const Uuid().v4(),
                  name: nameController.text.trim(),
                  description: descriptionController.text.trim(),
                  createdBy: myUid,
                  createdByName:
                      profile?.displayName ??
                      user?.email?.split('@').first ??
                      'Explorer',
                  visibility: visibility,
                  memberUids: const [],
                  createdAt: DateTime.now(),
                );
                await ref.read(socialRepositoryProvider).createGroup(group);
                onCreated();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({
    required this.group,
    required this.myUid,
    required this.onChanged,
  });

  final Group group;
  final String myUid;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCreator = group.createdBy == myUid;
    final isMember = group.isMember(myUid);
    final repository = ref.read(socialRepositoryProvider);

    const pill = StadiumBorder();
    const pillPadding = EdgeInsets.symmetric(horizontal: 16);
    const pillSize = Size(0, 36);

    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      onTap: isMember
          ? () => context.push(
              '/groups/${group.id}?name=${Uri.encodeComponent(group.name)}',
            )
          : null,
      child: Row(
        children: [
          AppAvatar(initial: group.name, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    if (group.visibility == GroupVisibility.private) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: AppTheme.inkMuted,
                      ),
                    ],
                  ],
                ),
                if (group.description.isNotEmpty)
                  Text(
                    group.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: AppTheme.inkMuted,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${group.memberCount} members',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isCreator)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              onPressed: () async {
                await repository.deleteGroup(group.id);
                onChanged();
              },
            )
          else if (isMember)
            OutlinedButton(
              onPressed: () async {
                await repository.leaveGroup(group.id, myUid);
                onChanged();
              },
              style: OutlinedButton.styleFrom(
                shape: pill,
                padding: pillPadding,
                minimumSize: pillSize,
              ),
              child: const Text('Leave'),
            )
          else
            FilledButton(
              onPressed: () async {
                await repository.joinGroup(group.id, myUid);
                onChanged();
              },
              style: FilledButton.styleFrom(
                shape: pill,
                padding: pillPadding,
                minimumSize: pillSize,
              ),
              child: const Text('Join'),
            ),
        ],
      ),
    );
  }
}
