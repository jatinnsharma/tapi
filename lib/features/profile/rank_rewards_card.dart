import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/components.dart';
import 'application/rank_style_service.dart';
import 'domain/rank_style.dart';
import 'rank_frame.dart';

/// Rank rewards: every rank unlocks a profile frame and a trail colour. Tap an
/// unlocked one to wear it; locked ones show how much XP is missing.
class RankRewardsCard extends ConsumerWidget {
  const RankRewardsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rankStyleProvider).value;
    if (state == null) return const SizedBox.shrink();
    final next = nextLocked(state.totalXp);

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rank rewards',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            next == null
                ? 'Every rank unlocked. Wear any style you like.'
                : '${next.minXp - state.totalXp} XP to unlock the '
                      '${next.title} style',
          ),
          const SizedBox(height: 12),
          for (final style in rankStyles)
            _StyleRow(
              style: style,
              unlocked: style.isUnlocked(state.totalXp),
              equipped: style.id == state.equipped.id,
              missingXp: style.minXp - state.totalXp,
              onTap: () async {
                final done = await equipStyle(style, state.totalXp);
                if (!context.mounted || !done) return;
                ref.invalidate(rankStyleProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${style.title} style equipped')),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StyleRow extends StatelessWidget {
  const _StyleRow({
    required this.style,
    required this.unlocked,
    required this.equipped,
    required this.missingXp,
    required this.onTap,
  });

  final RankStyle style;
  final bool unlocked;
  final bool equipped;
  final int missingXp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: unlocked ? onTap : null,
      child: Opacity(
        opacity: unlocked ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              RankFrame(
                style: style,
                child: const AppAvatar(initial: 'E', size: 38),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      style.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 6,
                          decoration: BoxDecoration(
                            color: style.trail,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          unlocked
                              ? 'Frame + trail colour'
                              : '${style.minXp} XP ($missingXp to go)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (equipped)
                const Icon(Icons.check_circle_rounded, color: AppTheme.emerald)
              else if (!unlocked)
                const Icon(Icons.lock_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
