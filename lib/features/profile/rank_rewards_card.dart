import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_components.dart';
import '../../core/theme/components.dart';
import 'application/rank_style_service.dart';
import 'domain/rank_style.dart';
import 'rank_frame.dart';

/// "Rank & styles": every rank unlocks a frame for your profile photo and
/// a colour for the routes you walk. Tap an unlocked one to wear it.
Future<void> showRankStylesSheet(BuildContext context, {String? name}) {
  return showAppSheet<void>(
    context,
    title: 'Rank & styles',
    body: RankStylesList(initial: name),
  );
}

class RankStylesList extends ConsumerWidget {
  const RankStylesList({super.key, this.initial});

  /// Your name, so the previews show your own initial.
  final String? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final async = ref.watch(rankStyleProvider);
    final state = async.value;
    if (state == null) {
      return async.hasError
          ? ErrorState(
              error: async.error!,
              onRetry: () => ref.invalidate(rankStyleProvider),
            )
          : const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
    }
    final next = nextLocked(state.totalXp);
    final letter = (initial == null || initial!.isEmpty)
        ? 'E'
        : initial!.substring(0, 1).toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Each rank unlocks a frame for your profile photo and a colour for '
          'the routes you walk on the map.',
          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          next == null
              ? 'Every rank unlocked. Wear any style you like.'
              : '${_xp(next.minXp - state.totalXp)} XP to unlock '
                    '${next.title}.',
          style: text.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final style in rankStyles)
          _StyleRow(
            style: style,
            letter: letter,
            unlocked: style.isUnlocked(state.totalXp),
            equipped: style.id == state.equipped.id,
            onTap: () async {
              final done = await equipStyle(style, state.totalXp);
              if (!context.mounted || !done) return;
              ref.invalidate(rankStyleProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Wearing the ${style.title} style')),
              );
            },
          ),
      ],
    );
  }
}

String _xp(int n) => NumberFormat.decimalPattern().format(n);

class _StyleRow extends StatelessWidget {
  const _StyleRow({
    required this.style,
    required this.letter,
    required this.unlocked,
    required this.equipped,
    required this.onTap,
  });

  final RankStyle style;
  final String letter;
  final bool unlocked;
  final bool equipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Semantics(
      button: unlocked,
      selected: equipped,
      label:
          '${style.title} style, '
          '${equipped
              ? 'wearing'
              : unlocked
              ? 'unlocked'
              : 'locked, unlocks at ${_xp(style.minXp)} XP'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: unlocked ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(
            children: [
              // Locked previews stay at full contrast; the lock says it.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  RankFrame(
                    style: style,
                    child: AppAvatar(initial: letter, size: 40),
                  ),
                  if (!unlocked)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.border),
                        ),
                        child: Icon(
                          Icons.lock_rounded,
                          size: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(style.title, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 8,
                          decoration: BoxDecoration(
                            color: style.trail,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            unlocked
                                ? 'Frame and route colour'
                                : 'Unlocks at ${_xp(style.minXp)} XP',
                            style: text.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (equipped)
                Tag('Wearing', icon: Icons.check_rounded, tone: TagTone.brand),
            ],
          ),
        ),
      ),
    );
  }
}
