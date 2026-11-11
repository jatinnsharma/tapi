import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../auth/application/auth_service.dart';
import '../../memories/data/shared_memory_service.dart';
import '../application/footprint_service.dart';
import '../data/social_repository.dart';
import '../domain/explorer_profile.dart';
import '../domain/footprint.dart';
import '../domain/friendship.dart';
import '../domain/live_location.dart';
import 'friend_challenges_section.dart';

final _explorersProvider = FutureProvider.autoDispose<List<ExplorerProfile>>((
  ref,
) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return [];
  return ref.watch(socialRepositoryProvider).getAllExplorers(excludingUid: uid);
});

final _friendshipsProvider = FutureProvider.autoDispose<List<Friendship>>((
  ref,
) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return [];
  return ref.watch(socialRepositoryProvider).getFriendshipsFor(uid);
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

final _blockedByMeProvider = FutureProvider.autoDispose<List<ExplorerProfile>>((
  ref,
) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return [];
  final repository = ref.watch(socialRepositoryProvider);
  final blockedUids = await repository.getBlockedUids(uid);
  final profiles = <ExplorerProfile>[];
  for (final blockedUid in blockedUids) {
    final profile = await repository.getProfile(blockedUid);
    if (profile != null) profiles.add(profile);
  }
  return profiles;
});

/// Public (not file-private) because `ActivityFeedScreen` also needs this to
/// filter muted authors out of the feed.
final mutedUidsProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return {};
  return ref.watch(socialRepositoryProvider).getMutedUids(uid);
});

final _mutedByMeProvider = FutureProvider.autoDispose<List<ExplorerProfile>>((
  ref,
) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return [];
  final repository = ref.watch(socialRepositoryProvider);
  final mutedUids = await repository.getMutedUids(uid);
  final profiles = <ExplorerProfile>[];
  for (final mutedUid in mutedUids) {
    final profile = await repository.getProfile(mutedUid);
    if (profile != null) profiles.add(profile);
  }
  return profiles;
});

const _pagePadding = EdgeInsets.symmetric(horizontal: 20);

/// Big "Social" title with circular header actions, shared by every state.
class _SocialHeader extends StatelessWidget {
  const _SocialHeader({this.actions = const []});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _pagePadding,
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Social',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                color: AppTheme.ink,
              ),
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 8), action],
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

class SocialScreen extends ConsumerWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = ref.watch(firebaseReadyProvider);

    if (!firebaseReady) {
      return const _SocialMessage(
        child: EmptyStateCard(
          icon: Icons.cloud_off_rounded,
          title: 'Social is unavailable',
          message:
              'Firebase isn\'t configured yet, so Social features are unavailable. '
              'See PENDING_TASKS.md for setup steps.',
        ),
      );
    }

    final authState = ref.watch(authStateProvider);
    final user = authState.value;

    if (user == null) {
      return _SocialMessage(
        child: EmptyStateCard(
          icon: Icons.group_outlined,
          title: 'Find fellow explorers',
          message: 'Sign in to find and friend other explorers.',
          actionLabel: 'Sign In',
          onAction: () => context.push('/login'),
        ),
      );
    }

    final explorersAsync = ref.watch(_explorersProvider);
    final friendshipsAsync = ref.watch(_friendshipsProvider);
    final hiddenUidsAsync = ref.watch(_hiddenUidsProvider);
    final mutedUidsAsync = ref.watch(mutedUidsProvider);

    void refresh() {
      ref.invalidate(_explorersProvider);
      ref.invalidate(_friendshipsProvider);
      ref.invalidate(_myProfileProvider);
      ref.invalidate(_friendsLiveProvider);
      ref.invalidate(_hiddenUidsProvider);
      ref.invalidate(_blockedByMeProvider);
      ref.invalidate(mutedUidsProvider);
      ref.invalidate(_mutedByMeProvider);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.forest,
          onRefresh: () async => refresh(),
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              _SocialHeader(
                actions: [
                  RoundIconButton(
                    icon: Icons.diversity_3_outlined,
                    tooltip: 'Groups',
                    size: 42,
                    onPressed: () => context.push('/groups'),
                  ),
                  RoundIconButton(
                    icon: Icons.groups_outlined,
                    tooltip: 'Group Adventures',
                    size: 42,
                    onPressed: () => context.push('/group-adventures'),
                  ),
                  RoundIconButton(
                    icon: Icons.dynamic_feed,
                    tooltip: 'Activity Feed',
                    size: 42,
                    onPressed: () => context.push('/activity-feed'),
                  ),
                  // Sign out lives in the Account section at the bottom.
                  RoundIconButton(
                    icon: Icons.emoji_events_outlined,
                    tooltip: 'Leaderboard',
                    size: 42,
                    onPressed: () => context.push('/leaderboard'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              explorersAsync.when(
                loading: () => const _SocialSkeleton(),
                error: (error, stack) => Padding(
                  padding: _pagePadding,
                  child: EmptyStateCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not load explorers',
                    message: '$error',
                    actionLabel: 'Try again',
                    onAction: refresh,
                  ),
                ),
                data: (allExplorers) {
                  final friendships = friendshipsAsync.value ?? const [];
                  final byOtherUid = {
                    for (final f in friendships) f.otherUid(user.uid): f,
                  };
                  final incoming = friendships
                      .where((f) => f.isIncomingFor(user.uid))
                      .toList();
                  final hiddenUids = hiddenUidsAsync.value ?? const {};
                  final explorers = allExplorers
                      .where((e) => !hiddenUids.contains(e.uid))
                      .toList();
                  final mutedUids = mutedUidsAsync.value ?? const {};

                  return Padding(
                    padding: _pagePadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeSlideIn(
                          child: _MyProfileCard(
                            myUid: user.uid,
                            fallbackEmail: user.email ?? '',
                            onChanged: refresh,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 60),
                          child: _FootprintPrivacyCard(
                            uid: user.uid,
                            fallbackName:
                                user.email?.split('@').first ?? 'Explorer',
                          ),
                        ),
                        const _FriendsLiveSection(),
                        const FriendChallengesSection(),
                        if (incoming.isNotEmpty) ...[
                          const SectionHeader(
                            title: 'Friend Requests',
                            padding: EdgeInsets.only(top: 24, bottom: 12),
                          ),
                          for (final request in incoming)
                            _FriendRequestTile(
                              profile: explorers
                                  .where(
                                    (e) => e.uid == request.otherUid(user.uid),
                                  )
                                  .firstOrNull,
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
                        const SectionHeader(
                          title: 'Explorers',
                          padding: EdgeInsets.only(top: 24, bottom: 12),
                        ),
                        if (explorers.isEmpty)
                          const EmptyStateCard(
                            icon: Icons.explore_outlined,
                            title: 'No explorers yet',
                            message: 'No other explorers have signed up yet.',
                          ),
                        for (final explorer in explorers)
                          _ExplorerTile(
                            profile: explorer,
                            friendship: byOtherUid[explorer.uid],
                            myUid: user.uid,
                            isMuted: mutedUids.contains(explorer.uid),
                            onChanged: refresh,
                          ),
                        _BlockedUsersSection(
                          myUid: user.uid,
                          onChanged: refresh,
                        ),
                        _MutedUsersSection(myUid: user.uid, onChanged: refresh),
                        _AccountSection(uid: user.uid, email: user.email),
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

/// Sign out and account deletion (required by app stores for any app that
/// lets people create an account).
class _AccountSection extends ConsumerWidget {
  const _AccountSection({required this.uid, required this.email});

  final String uid;
  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Account',
          padding: EdgeInsets.only(top: 24, bottom: 12),
        ),
        SoftCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email ?? 'Signed in',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => ref.read(authServiceProvider).signOut(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _DeleteAccountDialog(uid: uid),
                    ),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Delete account'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog({required this.uid});

  final String uid;

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final auth = ref.read(authServiceProvider);
    final social = ref.read(socialRepositoryProvider);
    final memories = ref.read(sharedMemoryServiceProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Password first: nothing is deleted if it's wrong.
      await auth.reauthenticate(_password.text);
      await memories.deleteAllFor(widget.uid);
      await social.deleteAllDataFor(widget.uid);
      await auth.deleteCurrentUser();
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _working = false;
        _error = e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'That password is incorrect.'
            : 'Could not delete the account (${e.code}). Try again.';
      });
    } catch (e) {
      setState(() {
        _working = false;
        _error = 'Could not delete the account: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your profile, friends, feed posts, '
              'shared map and live location, and your sign-in. It can\'t be '
              'undone.\n\nMessages you sent in group chats stay, under the '
              'name you used. Adventures, places and photos stored on this '
              'phone are not affected.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              enabled: !_working,
              // Rebuild so the delete button enables once there's a password.
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Confirm your password',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _working || _password.text.isEmpty ? null : _delete,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
            shape: const StadiumBorder(),
          ),
          child: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Text('Delete my account'),
        ),
      ],
    );
  }
}

/// "Who can see my map": the visibility choice for the user's exploration
/// footprint. Choosing Friends or Public uploads their routes and visited
/// places; choosing Private clears the shared copy again.
class _FootprintPrivacyCard extends ConsumerStatefulWidget {
  const _FootprintPrivacyCard({required this.uid, required this.fallbackName});

  final String uid;
  final String fallbackName;

  @override
  ConsumerState<_FootprintPrivacyCard> createState() =>
      _FootprintPrivacyCardState();
}

class _FootprintPrivacyCardState extends ConsumerState<_FootprintPrivacyCard> {
  bool _saving = false;

  Future<void> _change(FootprintVisibility visibility) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(footprintServiceProvider)
          .setVisibility(
            uid: widget.uid,
            fallbackName: widget.fallbackName,
            visibility: visibility,
          );
      ref.invalidate(myFootprintProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update map visibility: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current =
        ref.watch(myFootprintProvider).value?.visibility ??
        FootprintVisibility.private;

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, color: AppTheme.primaryGreen),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Who can see my map',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              if (_saving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<FootprintVisibility>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppTheme.forest,
                selectedForegroundColor: Colors.white,
                foregroundColor: AppTheme.ink,
              ),
              segments: const [
                ButtonSegment(
                  value: FootprintVisibility.private,
                  icon: Icon(Icons.lock_outline_rounded, size: 18),
                  label: Text('Private'),
                ),
                ButtonSegment(
                  value: FootprintVisibility.friends,
                  icon: Icon(Icons.group_outlined, size: 18),
                  label: Text('Friends'),
                ),
                ButtonSegment(
                  value: FootprintVisibility.public,
                  icon: Icon(Icons.public, size: 18),
                  label: Text('Public'),
                ),
              ],
              selected: {current},
              onSelectionChanged: _saving
                  ? null
                  : (selection) => _change(selection.first),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            current.description,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppTheme.inkMuted,
            ),
          ),
        ],
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
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Updated ${_relativeTime(live.updatedAt)}',
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
        message: '$error',
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
                child: _avatarFor(
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile?.bio?.isNotEmpty == true
                          ? profile!.bio!
                          : 'No bio yet',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14,
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
    final name = profile?.displayName ?? 'An explorer';
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      radius: 22,
      child: Row(
        children: [
          _avatarFor(profile),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const Text(
                  'wants to be friends',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_rounded, color: Colors.green),
            onPressed: onAccept,
          ),
          IconButton(
            icon: const Icon(Icons.cancel_rounded, color: Colors.red),
            onPressed: onDecline,
          ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      radius: 22,
      child: Row(
        children: [
          _avatarFor(profile),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                Text(
                  profile.bio?.isNotEmpty == true ? profile.bio! : 'Explorer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildAction(ref),
          if (friendship?.isAccepted == true)
            IconButton(
              icon: const Icon(
                Icons.map_outlined,
                color: AppTheme.primaryGreen,
              ),
              tooltip: 'View map',
              onPressed: () => _openMap(context),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.inkMuted),
            onSelected: (value) async {
              if (value == 'map') {
                _openMap(context);
              } else if (value == 'block') {
                _confirmBlock(context, ref);
              } else if (value == 'report') {
                _showReportDialog(context, ref);
              } else if (value == 'mute') {
                await ref
                    .read(socialRepositoryProvider)
                    .muteUser(myUid, profile.uid);
                onChanged();
              } else if (value == 'unmute') {
                await ref
                    .read(socialRepositoryProvider)
                    .unmuteUser(myUid, profile.uid);
                onChanged();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'map', child: Text('View map')),
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

  void _openMap(BuildContext context) {
    context.push(
      '/footprint/${profile.uid}?name=${Uri.encodeComponent(profile.displayName)}',
    );
  }

  void _confirmBlock(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block this explorer?'),
        content: Text(
          'You and ${profile.displayName} will no longer see each other as friends or in '
          'each other\'s Explorers list. You can unblock them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(socialRepositoryProvider)
                  .blockUser(myUid, profile.uid);
              onChanged();
              if (context.mounted) Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
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
          ElevatedButton(
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

  Widget _buildAction(WidgetRef ref) {
    final repository = ref.read(socialRepositoryProvider);

    if (friendship == null) {
      return FilledButton(
        onPressed: () async {
          await repository.sendFriendRequest(myUid, profile.uid);
          onChanged();
        },
        style: _pillStyle(filled: true),
        child: const Text('Add Friend'),
      );
    }

    if (friendship!.isAccepted) {
      return OutlinedButton(
        onPressed: () async {
          await repository.removeFriendship(myUid, profile.uid);
          onChanged();
        },
        style: _pillStyle(),
        child: const Text('Friends'),
      );
    }

    if (friendship!.isOutgoingFor(myUid)) {
      return OutlinedButton(
        onPressed: () async {
          await repository.removeFriendship(myUid, profile.uid);
          onChanged();
        },
        style: _pillStyle(),
        child: const Text('Requested'),
      );
    }

    // Incoming request — already surfaced in the "Friend Requests" section.
    return const Text(
      'Respond above',
      style: TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
    );
  }
}

ButtonStyle _pillStyle({bool filled = false}) {
  final shape = const StadiumBorder();
  const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 0);
  const minimumSize = Size(0, 36);
  return filled
      ? FilledButton.styleFrom(
          shape: shape,
          padding: padding,
          minimumSize: minimumSize,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )
      : OutlinedButton.styleFrom(
          shape: shape,
          padding: padding,
          minimumSize: minimumSize,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
}

class _BlockedUsersSection extends ConsumerWidget {
  const _BlockedUsersSection({required this.myUid, required this.onChanged});

  final String myUid;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(_blockedByMeProvider);

    return blockedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (blocked) {
        if (blocked.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Blocked (${blocked.length})',
              padding: const EdgeInsets.only(top: 24, bottom: 12),
            ),
            for (final profile in blocked)
              _ManagedUserTile(
                profile: profile,
                actionLabel: 'Unblock',
                onPressed: () async {
                  await ref
                      .read(socialRepositoryProvider)
                      .unblockUser(myUid, profile.uid);
                  onChanged();
                },
              ),
          ],
        );
      },
    );
  }
}

class _MutedUsersSection extends ConsumerWidget {
  const _MutedUsersSection({required this.myUid, required this.onChanged});

  final String myUid;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mutedAsync = ref.watch(_mutedByMeProvider);

    return mutedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (muted) {
        if (muted.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Muted (${muted.length})',
              padding: const EdgeInsets.only(top: 24, bottom: 12),
            ),
            for (final profile in muted)
              _ManagedUserTile(
                profile: profile,
                actionLabel: 'Unmute',
                onPressed: () async {
                  await ref
                      .read(socialRepositoryProvider)
                      .unmuteUser(myUid, profile.uid);
                  onChanged();
                },
              ),
          ],
        );
      },
    );
  }
}

/// Row used by the Blocked / Muted lists: avatar, name and one action.
class _ManagedUserTile extends StatelessWidget {
  const _ManagedUserTile({
    required this.profile,
    required this.actionLabel,
    required this.onPressed,
  });

  final ExplorerProfile profile;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      radius: 22,
      child: Row(
        children: [
          _avatarFor(profile),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              profile.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: onPressed,
            style: _pillStyle(),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

Widget _avatarFor(
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
