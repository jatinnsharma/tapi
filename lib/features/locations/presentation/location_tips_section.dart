import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../../social/data/social_repository.dart';
import '../data/location_community_repository.dart';
import '../domain/location.dart';
import '../domain/location_tip.dart';

import 'package:go_router/go_router.dart';

import '../../../core/theme/app_components.dart';

/// SharedPreferences key of tips this user reported (hidden for them).
const reportedTipsKey = 'reported_tips_v1';

/// How many tips are shown at once.
const shownTipCount = 5;

/// Why a tip can be reported.
const tipReportReasons = [
  'Spam or advertising',
  'Rude or hateful',
  'False or dangerous',
  'Other',
];

/// Explorer count and tips for a place, with posting (up to [maxTipLength]
/// characters), deleting your own tips, and reporting or blocking others.
/// Signed out it says so, rather than waiting on a read the rules refuse.
class LocationTipsSection extends ConsumerStatefulWidget {
  const LocationTipsSection({super.key, required this.location});

  final ExploreLocation location;

  @override
  ConsumerState<LocationTipsSection> createState() =>
      _LocationTipsSectionState();
}

typedef _TipsData = ({int explorers, List<LocationTip> tips});

class _LocationTipsSectionState extends ConsumerState<LocationTipsSection> {
  _TipsData? _data;
  bool _failed = false;

  /// Which load is newest, so a slow earlier one can't overwrite it.
  int _loadId = 0;

  String? get _uid => ref.read(authStateProvider).value?.uid;

  Future<void> _load(String uid) async {
    final id = ++_loadId;
    try {
      final community = ref.read(locationCommunityRepositoryProvider);
      final count = await community.getExplorerCount(widget.location.id);
      final tips = await community.getTips(widget.location.id);
      Set<String> blocked = const {};
      try {
        blocked = await ref.read(socialRepositoryProvider).getBlockedUids(uid);
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      final reported = (prefs.getStringList(reportedTipsKey) ?? const [])
          .toSet();
      if (!mounted || id != _loadId) return;
      setState(() {
        _failed = false;
        _data = (
          explorers: count,
          tips: visibleTips(
            tips,
            hiddenAuthors: blocked,
            reportedTipIds: reported,
          ),
        );
      });
    } catch (_) {
      if (!mounted || id != _loadId) return;
      setState(() => _failed = true);
    }
  }

  void _reload() {
    final uid = _uid;
    if (uid != null) _load(uid);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(firebaseReadyProvider)) return const SizedBox.shrink();
    final uid = ref.watch(authStateProvider).value?.uid;
    if (uid == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Sign in to see and share tips about this place.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.of(context).textSecondary),
              ),
            ),
            AppButton.tertiary(
              label: 'Sign in',
              onPressed: () => context.push('/login'),
            ),
          ],
        ),
      );
    }
    final data = _data;
    if (data == null && !_failed && _loadId == 0) {
      // First build while signed in: start loading after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(uid));
    }

    if (_failed && data == null) {
      return Row(
        children: [
          const Expanded(
            child: Text(
              'Could not load tips.',
              style: TextStyle(color: AppTheme.inkMuted),
            ),
          ),
          TextButton(onPressed: _reload, child: const Text('Retry')),
        ],
      );
    }
    if (data == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Shimmer(child: SkeletonBox(height: 44, radius: 16)),
      );
    }
    final (:explorers, :tips) = data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.people_outline, size: 18, color: AppTheme.forest),
            const SizedBox(width: 6),
            Text(
              '$explorers explorer${explorers == 1 ? '' : 's'}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addTip(uid),
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              label: const Text('Add Tip'),
            ),
          ],
        ),
        for (final tip in tips.take(shownTipCount))
          _TipTile(
            tip: tip,
            mine: tip.uid == uid,
            onDelete: () => _delete(tip),
            onReport: () => _report(uid, tip),
            onBlock: () => _block(uid, tip),
          ),
      ],
    );
  }

  Future<void> _addTip(String uid) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _AddTipDialog(),
    );
    if (text == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final profile = await ref.read(socialRepositoryProvider).getProfile(uid);
      final user = ref.read(authStateProvider).value;
      final name =
          profile?.displayName ?? user?.email?.split('@').first ?? 'Explorer';
      await ref
          .read(locationCommunityRepositoryProvider)
          .postTip(
            widget.location.id,
            LocationTip(
              id: '',
              uid: uid,
              displayName: name.length > 60 ? name.substring(0, 60) : name,
              text: text,
              timestamp: DateTime.now(),
            ),
          );
      _reload();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not post your tip.')),
      );
    }
  }

  Future<void> _delete(LocationTip tip) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(locationCommunityRepositoryProvider)
          .deleteTip(widget.location.id, tip.id);
      _reload();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete the tip.')),
      );
    }
  }

  Future<void> _report(String uid, LocationTip tip) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Report this tip'),
        children: [
          for (final r in tipReportReasons)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(r),
              child: Text(r),
            ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(locationCommunityRepositoryProvider)
          .reportTip(
            locationId: widget.location.id,
            tip: tip,
            reportedBy: uid,
            reason: reason,
          );
      // Hidden for this user straight away, whatever the review decides.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(reportedTipsKey, [
        ...?prefs.getStringList(reportedTipsKey),
        tip.id,
      ]);
      _reload();
      messenger.showSnackBar(
        const SnackBar(content: Text('Thanks. The tip is hidden for you.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send the report.')),
      );
    }
  }

  Future<void> _block(String uid, LocationTip tip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block ${tip.displayName}?'),
        content: const Text(
          "You won't see their tips, and you'll no longer be friends.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(socialRepositoryProvider).blockUser(uid, tip.uid);
      _reload();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not block them.')),
      );
    }
  }
}

class _TipTile extends StatelessWidget {
  const _TipTile({
    required this.tip,
    required this.mine,
    required this.onDelete,
    required this.onReport,
    required this.onBlock,
  });

  final LocationTip tip;
  final bool mine;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${tip.displayName}: ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: tip.text),
                ],
              ),
              style: const TextStyle(color: AppTheme.ink, height: 1.35),
            ),
          ),
          if (mine)
            IconButton(
              tooltip: 'Delete my tip',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
            )
          else
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (action) =>
                  action == 'report' ? onReport() : onBlock(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('Report tip')),
                PopupMenuItem(value: 'block', child: Text('Block author')),
              ],
            ),
        ],
      ),
    );
  }
}

class _AddTipDialog extends StatefulWidget {
  const _AddTipDialog();

  @override
  State<_AddTipDialog> createState() => _AddTipDialogState();
}

class _AddTipDialogState extends State<_AddTipDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share a Tip'),
      content: TextField(
        controller: _text,
        maxLength: maxTipLength,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'e.g. Best visited at sunrise',
          helperText: 'Visible to everyone signed in. Be kind and useful.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(shape: const StadiumBorder()),
          onPressed: () {
            final text = _text.text.trim();
            if (text.isEmpty) return;
            Navigator.of(context).pop(text);
          },
          child: const Text('Post'),
        ),
      ],
    );
  }
}
