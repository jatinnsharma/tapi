import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../application/footprint_service.dart';
import '../data/social_repository.dart';
import '../domain/explorer_profile.dart';
import '../domain/footprint.dart';
import '../../../core/ui/friendly_error.dart';
import 'social_screen.dart';

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

/// Settings → Privacy: who can see your map, and the people you've blocked
/// or muted. (These used to sit at the bottom of the Friends tab.)
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final user = ref.watch(authStateProvider).value;

    void refresh() {
      ref.invalidate(_blockedByMeProvider);
      ref.invalidate(_mutedByMeProvider);
      ref.invalidate(mutedUidsProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: !firebaseReady
          ? const GateCard(
              icon: Icons.cloud_off_rounded,
              title: 'Not available yet',
              message:
                  'Sharing isn\'t available in this version of the app, so '
                  'nothing of yours is shared.',
            )
          : user == null
          ? SignInPrompt(
              reason: 'choose who sees your map and manage blocked people',
              onSignIn: () => context.push('/login'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _FootprintPrivacyCard(
                  uid: user.uid,
                  fallbackName: user.email?.split('@').first ?? 'Explorer',
                ),
                _BlockedUsersSection(myUid: user.uid, onChanged: refresh),
                _MutedUsersSection(myUid: user.uid, onChanged: refresh),
                const SizedBox(height: 16),
                Text(
                  'Block or mute someone from the ⋮ menu next to their name '
                  'in Friends.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.of(context).textSecondary),
                ),
              ],
            ),
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
        SnackBar(
          content: Text('Could not update map visibility. ${friendlyError(e)}'),
        ),
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
          explorerAvatar(profile),
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
          AppButton.secondary(label: actionLabel, onPressed: onPressed),
        ],
      ),
    );
  }
}
