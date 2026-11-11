import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../../tracking/application/tracking_service.dart';
import '../data/social_repository.dart';
import '../domain/group_adventure.dart';

final _publicAdventuresProvider =
    FutureProvider.autoDispose<List<GroupAdventure>>((ref) {
      return ref.watch(socialRepositoryProvider).getPublicGroupAdventures();
    });

final _myAdventuresProvider = FutureProvider.autoDispose<List<GroupAdventure>>((
  ref,
) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return [];
  return ref.watch(socialRepositoryProvider).getMyGroupAdventures(uid);
});

class GroupAdventuresScreen extends ConsumerWidget {
  const GroupAdventuresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    if (!firebaseReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Adventures')),
        body: const Padding(
          padding: AppSpacing.page,
          child: EmptyStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Group Adventures are unavailable',
            message:
                'Firebase isn\'t configured yet, so Group Adventures are unavailable. '
                'See PENDING_TASKS.md for setup steps.',
          ),
        ),
      );
    }

    final user = ref.watch(authStateProvider).value;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Adventures')),
        body: const Padding(
          padding: AppSpacing.page,
          child: EmptyStateCard(
            icon: Icons.groups_outlined,
            title: 'Adventure together',
            message: 'Sign in to create or join group adventures.',
          ),
        ),
      );
    }

    final publicAsync = ref.watch(_publicAdventuresProvider);
    final myAsync = ref.watch(_myAdventuresProvider);

    void refresh() {
      ref.invalidate(_publicAdventuresProvider);
      ref.invalidate(_myAdventuresProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Adventures'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Create Group Adventure',
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
                    const SectionHeader(title: 'My Adventures'),
                    for (final adventure in mine)
                      _GroupAdventureCard(
                        adventure: adventure,
                        myUid: user.uid,
                        onChanged: refresh,
                      ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
            const SectionHeader(title: 'Public Adventures'),
            publicAsync.when(
              loading: () => const Shimmer(
                child: Column(
                  children: [
                    SkeletonBox(height: 150, radius: 24),
                    SizedBox(height: 12),
                    SkeletonBox(height: 150, radius: 24),
                  ],
                ),
              ),
              error: (error, stack) => EmptyStateCard(
                icon: Icons.cloud_off_rounded,
                title: 'Could not load adventures',
                message: '$error',
                actionLabel: 'Try again',
                onAction: refresh,
              ),
              data: (adventures) {
                if (adventures.isEmpty) {
                  return const EmptyStateCard(
                    icon: Icons.groups_outlined,
                    title: 'No public adventures yet',
                    message: 'No public group adventures yet. Create one!',
                  );
                }
                return Column(
                  children: [
                    for (final adventure in adventures)
                      _GroupAdventureCard(
                        adventure: adventure,
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
    final locationController = TextEditingController();
    final dateController = TextEditingController();
    final timeController = TextEditingController();
    final meetingPointController = TextEditingController();
    final groupSizeController = TextEditingController(text: '6');
    String difficulty = 'Moderate';
    var visibility = GroupAdventureVisibility.public;

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create Group Adventure'),
          content: SingleChildScrollView(
            child: Column(
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
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location / Trail',
                  ),
                ),
                TextField(
                  controller: dateController,
                  decoration: const InputDecoration(labelText: 'Date'),
                ),
                TextField(
                  controller: timeController,
                  decoration: const InputDecoration(labelText: 'Time'),
                ),
                TextField(
                  controller: meetingPointController,
                  decoration: const InputDecoration(labelText: 'Meeting Point'),
                ),
                TextField(
                  controller: groupSizeController,
                  decoration: const InputDecoration(
                    labelText: 'Group Size Limit',
                  ),
                  keyboardType: TextInputType.number,
                ),
                DropdownButtonFormField<String>(
                  initialValue: difficulty,
                  decoration: const InputDecoration(labelText: 'Difficulty'),
                  items: const [
                    DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                    DropdownMenuItem(
                      value: 'Moderate',
                      child: Text('Moderate'),
                    ),
                    DropdownMenuItem(value: 'Hard', child: Text('Hard')),
                  ],
                  onChanged: (value) =>
                      setState(() => difficulty = value ?? difficulty),
                ),
                DropdownButtonFormField<GroupAdventureVisibility>(
                  initialValue: visibility,
                  decoration: const InputDecoration(labelText: 'Visibility'),
                  items: const [
                    DropdownMenuItem(
                      value: GroupAdventureVisibility.public,
                      child: Text('Public'),
                    ),
                    DropdownMenuItem(
                      value: GroupAdventureVisibility.private,
                      child: Text('Private (invite only)'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => visibility = value ?? visibility),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final groupSize =
                    int.tryParse(groupSizeController.text.trim()) ?? 6;
                final user = ref.read(authStateProvider).value;
                final profile = await ref
                    .read(socialRepositoryProvider)
                    .getProfile(myUid);
                final adventure = GroupAdventure(
                  id: const Uuid().v4(),
                  name: nameController.text.trim(),
                  description: descriptionController.text.trim(),
                  createdBy: myUid,
                  createdByName:
                      profile?.displayName ??
                      user?.email?.split('@').first ??
                      'Explorer',
                  locationHint: locationController.text.trim(),
                  date: dateController.text.trim(),
                  time: timeController.text.trim(),
                  meetingPoint: meetingPointController.text.trim(),
                  difficulty: difficulty,
                  groupSizeLimit: groupSize,
                  visibility: visibility,
                  memberUids: const [],
                  createdAt: DateTime.now(),
                );
                await ref
                    .read(socialRepositoryProvider)
                    .createGroupAdventure(adventure);
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

class _GroupAdventureCard extends ConsumerWidget {
  const _GroupAdventureCard({
    required this.adventure,
    required this.myUid,
    required this.onChanged,
  });

  final GroupAdventure adventure;
  final String myUid;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCreator = adventure.createdBy == myUid;
    final isMember = adventure.isMember(myUid);
    final repository = ref.read(socialRepositoryProvider);

    const pill = StadiumBorder();
    const pillPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 0);
    const pillSize = Size(0, 38);

    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  adventure.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.2,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              if (adventure.visibility == GroupAdventureVisibility.private)
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppTheme.inkMuted,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            adventure.description,
            style: const TextStyle(color: AppTheme.inkMuted, height: 1.35),
          ),
          const SizedBox(height: 10),
          Text(
            '${adventure.date} • ${adventure.time} • Meet at ${adventure.meetingPoint}',
            style: const TextStyle(
              color: AppTheme.primaryGreen,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${adventure.difficulty} • ${adventure.memberUids.length}/${adventure.groupSizeLimit} joined • '
            'Organized by ${adventure.createdByName}',
            style: const TextStyle(color: AppTheme.inkMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (isCreator)
                OutlinedButton.icon(
                  onPressed: () async {
                    await repository.deleteGroupAdventure(adventure.id);
                    onChanged();
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Cancel Adventure'),
                  style: OutlinedButton.styleFrom(
                    shape: pill,
                    padding: pillPadding,
                    minimumSize: pillSize,
                  ),
                )
              else if (isMember)
                OutlinedButton(
                  onPressed: () async {
                    await repository.leaveGroupAdventure(adventure.id, myUid);
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
                  onPressed: adventure.isFull
                      ? null
                      : () async {
                          await repository.joinGroupAdventure(
                            adventure.id,
                            myUid,
                          );
                          onChanged();
                        },
                  style: FilledButton.styleFrom(
                    shape: pill,
                    padding: pillPadding,
                    minimumSize: pillSize,
                  ),
                  child: Text(adventure.isFull ? 'Full' : 'Join'),
                ),
              if (isCreator || isMember) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  color: AppTheme.forest,
                  tooltip: 'Group Chat',
                  onPressed: () => context.push(
                    '/group-adventures/${adventure.id}/chat?name=${Uri.encodeComponent(adventure.name)}',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.map_outlined),
                  color: AppTheme.forest,
                  tooltip: 'Live Map',
                  onPressed: () => context.push(
                    '/group-adventures/${adventure.id}/live-map?name=${Uri.encodeComponent(adventure.name)}',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  color: AppTheme.amberText,
                  tooltip: 'Start Tracking',
                  onPressed: () async {
                    await ref
                        .read(trackingServiceProvider.notifier)
                        .startAdventure(
                          title: adventure.name,
                          groupAdventureId: adventure.id,
                        );
                    if (context.mounted) context.push('/tracking');
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
