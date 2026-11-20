import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../auth/application/auth_service.dart';
import '../application/friend_requests.dart';
import '../data/social_repository.dart';
import '../domain/explorer_profile.dart';
import '../domain/friendship.dart';
import '../domain/live_location.dart';
import 'friend_challenges_section.dart';
import '../../../core/ui/confirm_destructive.dart';
import '../../../core/ui/friendly_error.dart';
import '../../../core/theme/app_components.dart';

final _explorersProvider = FutureProvider.autoDispose<List<ExplorerProfile>>((
  ref,
) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return [];
  return ref.watch(socialRepositoryProvider).getAllExplorers(excludingUid: uid);
});

/// Profiles of your friends and of people asking to be friends, by uid.
/// Fetched one by one when they aren't among the first explorers, so a
/// friend or request never shows as "An explorer".
final _peopleProvider =
    FutureProvider.autoDispose<Map<String, ExplorerProfile>>((ref) async {
      final uid = ref.watch(authStateProvider).value?.uid;
      if (uid == null) return {};
      final friendships = await ref.watch(friendshipsProvider.future);
      final explorers = await ref.watch(_explorersProvider.future);
      final known = {for (final e in explorers) e.uid: e};
      final repository = ref.watch(socialRepositoryProvider);
      final people = <String, ExplorerProfile>{};
      for (final f in friendships) {
        if (!f.isAccepted && !f.isIncomingFor(uid)) continue;
        final other = f.otherUid(uid);
        final profile = known[other] ?? await repository.getProfile(other);
        if (profile != null) people[other] = profile;
      }
      return people;
    });

final _myProfileProvider = FutureProvider.autoDispose<ExplorerProfile?>((
  ref,
) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return null;
  return ref.watch(socialRepositoryProvider).getProfile(uid);
});

final _friendsLiveProvider = FutureProvider.autoDispose<List<LiveLocation>>((
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
  return repository.getFriendsLiveLocations(friendUids);
});

/// Everyone to hide from the Explorers directory: people the signed-in user
/// has blocked, and people who have blocked them (mutual invisibility).
/// Feed and live-sharing need no separate filtering here — blocking severs
/// the friendship (see `SocialRepository.blockUser`), which already removes
/// a blocked person from every friend-scoped list elsewhere in the app.
final _hiddenUidsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return {};
  final repository = ref.watch(socialRepositoryProvider);
  final blocked = await repository.getBlockedUids(uid);
  final blockedMe = await repository.getUidsWhoBlockedMe(uid);
  return {...blocked, ...blockedMe};
});

/// Public (not file-private) because `ActivityFeedScreen` also needs this to
/// filter muted authors out of the feed.
final mutedUidsProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return {};
  return ref.watch(socialRepositoryProvider).getMutedUids(uid);
});

const _pagePadding = EdgeInsets.symmetric(horizontal: 20);

/// The tab's title, shared by every state.
class _SocialHeader extends StatelessWidget {
  const _SocialHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _pagePadding,
      child: Text('Friends', style: Theme.of(context).textTheme.headlineLarge),
    );
  }
}

/// Groups, meetups, leaderboard and feed as labelled shortcuts (they were
/// four look-alike icons).
class _SocialNav extends StatelessWidget {
  const _SocialNav();

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.diversity_3_outlined, 'Groups', '/groups'),
      (Icons.event_available_outlined, 'Meetups', '/group-adventures'),
      (Icons.emoji_events_outlined, 'Leaderboard', '/leaderboard'),
      (Icons.dynamic_feed_outlined, 'Feed', '/activity-feed'),
    ];
    // A wrap, not a sideways scroll: all four stay visible.
    return Padding(
      padding: _pagePadding,
      child: Wrap(
        spacing: 8,
        children: [
          for (final (icon, label, path) in items)
            ActionChip(
              avatar: Icon(icon, size: 18),
              label: Text(label),
              onPressed: () => context.push(path),
            ),
        ],
      ),
    );
  }
}

/// Title plus a single message card, for the not-configured / signed-out
/// states.
class _SocialMessage extends StatelessWidget {
  const _SocialMessage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 32),
          children: [
            const _SocialHeader(),
            const SizedBox(height: 16),
            Padding(padding: _pagePadding, child: child),
          ],
        ),
      ),
    );
  }
}

class _SocialSkeleton extends StatelessWidget {
  const _SocialSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: _pagePadding,
      child: Shimmer(
        child: Column(
          children: [
            SkeletonBox(height: 110, radius: 32),
            SizedBox(height: 24),
            SkeletonBox(height: 72, radius: 24),
            SizedBox(height: 12),
            SkeletonBox(height: 72, radius: 24),
            SizedBox(height: 12),
            SkeletonBox(height: 72, radius: 24),
          ],
        ),
      ),
    );
  }
}

class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final firebaseReady = ref.watch(firebaseReadyProvider);

    if (!firebaseReady) {
      return const _SocialMessage(
        child: EmptyStateCard(
          icon: Icons.cloud_off_rounded,
          title: 'Social is unavailable',
          message:
              "Friends and groups aren't available in this version of the app "
              'yet. Everything else works without them.',
        ),
      );
    }

    final authState = ref.watch(authStateProvider);
    final user = authState.value;

    if (user == null) {
      return _SocialMessage(
        child: SignInPrompt(
          reason: 'add friends, join groups and see the leaderboard',
          onSignIn: () => context.push('/login'),
        ),
      );
    }

    final explorersAsync = ref.watch(_explorersProvider);
    final friendshipsAsync = ref.watch(friendshipsProvider);
    final hiddenUidsAsync = ref.watch(_hiddenUidsProvider);
    final mutedUidsAsync = ref.watch(mutedUidsProvider);
    final people = ref.watch(_peopleProvider).value ?? const {};
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);

    void refresh() {
      ref.invalidate(_explorersProvider);
      ref.invalidate(friendshipsProvider);
      ref.invalidate(_peopleProvider);
      ref.invalidate(_myProfileProvider);
      ref.invalidate(_friendsLiveProvider);
      ref.invalidate(_hiddenUidsProvider);
      ref.invalidate(mutedUidsProvider);
    }

    Widget sectionTitle(String title) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(title, style: text.titleMedium),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              const _SocialHeader(),
              const SizedBox(height: 8),
              const _SocialNav(),
              const SizedBox(height: 12),
              explorersAsync.when(
                loading: () => const _SocialSkeleton(),
                error: (error, stack) => Padding(
                  padding: _pagePadding,
                  child: ErrorState(error: error, onRetry: refresh),
                ),
                data: (allExplorers) {
                  final friendships = friendshipsAsync.value ?? const [];
                  final byOtherUid = {
                    for (final f in friendships) f.otherUid(user.uid): f,
                  };
                  final incoming = friendships
                      .where((f) => f.isIncomingFor(user.uid))
                      .toList();
                  final friendUids = {
                    for (final f in friendships)
                      if (f.isAccepted) f.otherUid(user.uid),
                  };
                  final hiddenUids = hiddenUidsAsync.value ?? const {};
                  final mutedUids = mutedUidsAsync.value ?? const {};
                  final friends =
                      [
                        for (final uid in friendUids)
                          if (people[uid] case final p?)
                            if (!hiddenUids.contains(uid)) p,
                      ]..sort(
                        (a, b) => a.displayName.toLowerCase().compareTo(
                          b.displayName.toLowerCase(),
                        ),
                      );
                  final q = _query.trim().toLowerCase();
                  // Everyone else: not a friend, not asking to be one.
                  final others = allExplorers
                      .where(
                        (e) =>
                            !hiddenUids.contains(e.uid) &&
                            !friendUids.contains(e.uid) &&
                            byOtherUid[e.uid]?.isIncomingFor(user.uid) !=
                                true &&
                            (q.isEmpty ||
                                e.displayName.toLowerCase().contains(q)),
                      )
                      .toList();

                  Widget personTile(ExplorerProfile p) => _ExplorerTile(
                    profile: p,
                    friendship: byOtherUid[p.uid],
                    myUid: user.uid,
                    isMuted: mutedUids.contains(p.uid),
                    onChanged: refresh,
                  );

                  return Padding(
                    padding: _pagePadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FadeSlideIn(
                          child: _MyProfileCard(
                            myUid: user.uid,
                            fallbackEmail: user.email ?? '',
                            onChanged: refresh,
                          ),
                        ),
                        if (incoming.isNotEmpty) ...[
                          sectionTitle('Requests (${incoming.length})'),
                          AppListGroup(
                            children: [
                              for (final request in incoming)
                                _FriendRequestTile(
                                  profile: people[request.otherUid(user.uid)],
                                  onAccept: () async {
                                    await ref
                                        .read(socialRepositoryProvider)
                                        .acceptFriendRequest(
                                          user.uid,
                                          request.otherUid(user.uid),
                                        );
                                    refresh();
                                  },
                                  onDecline: () async {
                                    await ref
                                        .read(socialRepositoryProvider)
                                        .removeFriendship(
                                          user.uid,
                                          request.otherUid(user.uid),
                                        );
                                    refresh();
                                  },
                                ),
                            ],
                          ),
                        ],
                        const _FriendsLiveSection(),
                        const FriendChallengesSection(),
                        sectionTitle(
                          friends.isEmpty
                              ? 'Your friends'
                              : 'Your friends (${friends.length})',
                        ),
                        if (friends.isEmpty)
                          Text(
                            'No friends yet. Find explorers below and send a '
                            'request.',
                            style: text.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          )
                        else
                          AppListGroup(
                            children: [for (final p in friends) personTile(p)],
                          ),
                        sectionTitle('Find explorers'),
                        TextField(
                          onChanged: (v) => setState(() => _query = v),
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            hintText: 'Search by name',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (others.isEmpty)
                          Text(
                            q.isEmpty
                                ? 'No other explorers have signed up yet.'
                                : 'No one called "${_query.trim()}".',
                            style: text.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          )
                        else
                          AppListGroup(
                            children: [for (final p in others) personTile(p)],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendsLiveSection extends ConsumerWidget {
  const _FriendsLiveSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveAsync = ref.watch(_friendsLiveProvider);

    return liveAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (liveFriends) {
        if (liveFriends.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Friends Live Now',
              padding: EdgeInsets.only(top: 24, bottom: 12),
            ),
            for (final live in liveFriends)
              SoftCard(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                radius: 22,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppTheme.emerald, AppTheme.forest],
                        ),
                      ),
                      child: const Icon(
                        Icons.navigation,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${live.displayName} is on "${live.adventureTitle}"',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Updated ${_relativeTime(live.updatedAt)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.of(context).textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _relativeTime(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    return '${difference.inHours}h ago';
  }
}

class _MyProfileCard extends ConsumerWidget {
  const _MyProfileCard({
    required this.myUid,
    required this.fallbackEmail,
    required this.onChanged,
  });

  final String myUid;
  final String fallbackEmail;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_myProfileProvider);

    return profileAsync.when(
      loading: () => const Shimmer(child: SkeletonBox(height: 110, radius: 32)),
      error: (error, stack) => EmptyStateCard(
        icon: Icons.person_off_outlined,
        title: 'Could not load your profile',
        message: friendlyError(error),
      ),
      data: (profile) {
        final displayName =
            profile?.displayName ?? fallbackEmail.split('@').first;
        return HeroCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
                child: explorerAvatar(
                  profile,
                  fallbackEmail: fallbackEmail,
                  size: 56,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile?.bio?.isNotEmpty == true
                          ? profile!.bio!
                          : 'No bio yet',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary
                            .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Colors.white),
                tooltip: 'Edit profile',
                onPressed: () => _showEditProfileDialog(
                  context,
                  ref,
                  profile,
                  myUid,
                  fallbackEmail,
                  onChanged,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditProfileDialog(
    BuildContext context,
    WidgetRef ref,
    ExplorerProfile? current,
    String uid,
    String email,
    VoidCallback onSaved,
  ) {
    final nameController = TextEditingController(
      text: current?.displayName ?? email.split('@').first,
    );
    final bioController = TextEditingController(text: current?.bio ?? '');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        File? newAvatar;
        bool isLoading = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Profile'),
              content: isLoading
                  ? const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (newAvatar != null)
                            CircleAvatar(
                              radius: 40,
                              backgroundImage: FileImage(newAvatar!),
                            )
                          else if (current?.photoUrl != null)
                            CircleAvatar(
                              radius: 40,
                              backgroundImage: NetworkImage(current!.photoUrl!),
                            )
                          else
                            CircleAvatar(
                              radius: 40,
                              child: Text(
                                nameController.text.isNotEmpty
                                    ? nameController.text[0].toUpperCase()
                                    : '?',
                              ),
                            ),
                          TextButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final picked = await picker.pickImage(
                                source: ImageSource.gallery,
                              );
                              if (picked != null) {
                                setState(() {
                                  newAvatar = File(picked.path);
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Change Avatar'),
                          ),
                          TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Display name',
                            ),
                          ),
                          TextField(
                            controller: bioController,
                            decoration: const InputDecoration(labelText: 'Bio'),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
              actions: [
                if (!isLoading)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                if (!isLoading)
                  ElevatedButton(
                    onPressed: () async {
                      setState(() {
                        isLoading = true;
                      });
                      try {
                        String? photoUrl = current?.photoUrl;
                        if (newAvatar != null) {
                          try {
                            photoUrl = await ref
                                .read(socialRepositoryProvider)
                                .uploadAvatar(uid, newAvatar!);
                          } catch (e) {
                            debugPrint('Avatar upload failed: $e');
                          }
                        }
                        final updated =
                            (current ??
                                    ExplorerProfile(
                                      uid: uid,
                                      displayName: nameController.text.trim(),
                                      createdAt: DateTime.now(),
                                    ))
                                .copyWith(
                                  displayName: nameController.text.trim(),
                                  bio: bioController.text.trim(),
                                  photoUrl: photoUrl,
                                );
                        await ref
                            .read(socialRepositoryProvider)
                            .upsertProfile(updated);
                        onSaved();
                        if (context.mounted) Navigator.of(context).pop();
                      } finally {
                        if (context.mounted) {
                          setState(() {
                            isLoading = false;
                          });
                        }
                      }
                    },
                    child: const Text('Save'),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FriendRequestTile extends StatelessWidget {
  const _FriendRequestTile({
    required this.profile,
    required this.onAccept,
    required this.onDecline,
  });

  final ExplorerProfile? profile;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return PersonTile(
      avatar: explorerAvatar(profile),
      name: profile?.displayName ?? 'An explorer',
      subtitle: 'Wants to be friends',
      actions: Wrap(
        spacing: 8,
        children: [
          AppButton(label: 'Accept', onPressed: onAccept),
          AppButton.tertiary(label: 'Decline', onPressed: onDecline),
        ],
      ),
    );
  }
}

class _ExplorerTile extends ConsumerWidget {
  const _ExplorerTile({
    required this.profile,
    required this.friendship,
    required this.myUid,
    required this.isMuted,
    required this.onChanged,
  });

  final ExplorerProfile profile;
  final Friendship? friendship;
  final String myUid;
  final bool isMuted;
  final VoidCallback onChanged;

  bool get _isFriend => friendship?.isAccepted == true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = _buildAction(context, ref);
    return PersonTile(
      avatar: explorerAvatar(profile),
      name: profile.displayName,
      subtitle: profile.bio?.isNotEmpty == true ? profile.bio! : null,
      // A friend's row opens their map.
      onTap: _isFriend ? () => _openMap(context) : null,
      // The action sits under the name, so a long name or large text never
      // pushes it (or the name) off a small screen.
      actions: action,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: 'More for ${profile.displayName}',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              final repository = ref.read(socialRepositoryProvider);
              switch (value) {
                case 'map':
                  _openMap(context);
                case 'unfriend':
                  await _confirmUnfriend(context, ref);
                case 'block':
                  await _confirmBlock(context, ref);
                case 'report':
                  _showReportDialog(context, ref);
                case 'mute':
                  await repository.muteUser(myUid, profile.uid);
                  onChanged();
                case 'unmute':
                  await repository.unmuteUser(myUid, profile.uid);
                  onChanged();
              }
            },
            itemBuilder: (context) => [
              if (_isFriend) ...[
                const PopupMenuItem(value: 'map', child: Text('View map')),
                const PopupMenuItem(
                  value: 'unfriend',
                  child: Text('Remove friend'),
                ),
              ],
              PopupMenuItem(
                value: isMuted ? 'unmute' : 'mute',
                child: Text(isMuted ? 'Unmute' : 'Mute'),
              ),
              const PopupMenuItem(value: 'block', child: Text('Block')),
              const PopupMenuItem(value: 'report', child: Text('Report')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUnfriend(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDestructive(
      context,
      title: 'Remove ${profile.displayName} as a friend?',
      message:
          "You'll stop seeing each other's friends-only posts, map and "
          'live location. You can send a new request later.',
      confirmLabel: 'Remove friend',
    );
    if (!ok) return;
    await ref
        .read(socialRepositoryProvider)
        .removeFriendship(myUid, profile.uid);
    onChanged();
  }

  void _openMap(BuildContext context) {
    context.push(
      '/footprint/${profile.uid}?name=${Uri.encodeComponent(profile.displayName)}',
    );
  }

  Future<void> _confirmBlock(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDestructive(
      context,
      title: 'Block ${profile.displayName}?',
      message:
          'You won\'t see each other as friends or in search. You can '
          'unblock them in Settings → Privacy.',
      confirmLabel: 'Block',
    );
    if (!ok) return;
    await ref.read(socialRepositoryProvider).blockUser(myUid, profile.uid);
    onChanged();
  }

  void _showReportDialog(BuildContext context, WidgetRef ref) {
    final reasonController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report ${profile.displayName}'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'What happened?'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(socialRepositoryProvider)
                  .reportUser(
                    reportedUid: profile.uid,
                    reportedBy: myUid,
                    reason: reasonController.text.trim(),
                  );
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Thanks — your report has been submitted.'),
                  ),
                );
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  /// Add, or Requested (tap to cancel, with a confirm). Friends need no
  /// button: removing one is in the ⋮ menu.
  Widget? _buildAction(BuildContext context, WidgetRef ref) {
    final repository = ref.read(socialRepositoryProvider);
    if (friendship == null) {
      return AppButton(
        label: 'Add',
        icon: Icons.person_add_alt_1_outlined,
        onPressed: () async {
          await repository.sendFriendRequest(myUid, profile.uid);
          onChanged();
        },
      );
    }
    if (friendship!.isOutgoingFor(myUid)) {
      return AppButton.secondary(
        label: 'Requested',
        onPressed: () async {
          final ok = await confirmDestructive(
            context,
            title: 'Cancel your friend request?',
            message: '${profile.displayName} will no longer see it.',
            confirmLabel: 'Cancel request',
          );
          if (!ok) return;
          await repository.removeFriendship(myUid, profile.uid);
          onChanged();
        },
      );
    }
    return null;
  }
}

Widget explorerAvatar(
  ExplorerProfile? profile, {
  String? fallbackEmail,
  double size = 44,
}) {
  if (profile != null &&
      profile.photoUrl != null &&
      profile.photoUrl!.isNotEmpty) {
    return CircleAvatar(
      radius: size / 2,
      backgroundImage: NetworkImage(profile.photoUrl!),
    );
  }
  final name =
      profile?.displayName ??
      (fallbackEmail != null ? fallbackEmail.split('@').first : 'A');
  return AppAvatar(initial: name, size: size);
}
