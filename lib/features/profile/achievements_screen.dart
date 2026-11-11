import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/components.dart';
import '../../core/theme/glass.dart';
import 'application/achievement_service.dart';
import 'domain/achievement.dart';
import 'rank_rewards_card.dart';

const _bronze = Color(0xFFCD7F32);
const _silver = Color(0xFF9EA7B0);
const _gold = Color(0xFFF5B301);
const _starColors = [_bronze, _silver, _gold];

/// Achievements with three stars each. Reach a target to earn a star, then
/// claim it for bonus XP.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievementsAsync = ref.watch(achievementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: achievementsAsync.when(
        loading: () => const Padding(
          padding: AppSpacing.page,
          child: Shimmer(
            child: Column(
              children: [
                SkeletonBox(height: 110, radius: 28),
                SizedBox(height: 14),
                SkeletonBox(height: 120, radius: 24),
                SizedBox(height: 12),
                SkeletonBox(height: 120, radius: 24),
              ],
            ),
          ),
        ),
        error: (error, _) => ListView(
          padding: AppSpacing.page,
          children: [
            EmptyStateCard(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load achievements',
              message: '$error',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(achievementsProvider),
            ),
          ],
        ),
        data: (list) {
          final earned = list.fold<int>(0, (n, a) => n + a.earnedStars);
          final waitingXp = list.fold<int>(0, (n, a) => n + a.claimableXp);
          // Achievements with something to claim come first, like in Clash of
          // Clans; the rest keep their order.
          final sorted = [
            ...list.where((a) => a.hasClaimable),
            ...list.where((a) => !a.hasClaimable),
          ];

          return RefreshIndicator(
            color: AppTheme.forest,
            onRefresh: () async => ref.invalidate(achievementsProvider),
            child: ListView(
              padding: AppSpacing.page,
              children: [
                FadeSlideIn(
                  child: HeroCard(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_rounded,
                          color: AppTheme.amber,
                          size: 44,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$earned / ${list.length * 3} stars',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                waitingXp > 0
                                    ? '$waitingXp XP ready to claim'
                                    : 'Keep exploring to earn more',
                                style: TextStyle(
                                  color: waitingXp > 0
                                      ? AppTheme.amber
                                      : Colors.white.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const RankRewardsCard(),
                const SizedBox(height: 14),
                for (final progress in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AchievementCard(progress: progress),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AchievementCard extends ConsumerStatefulWidget {
  const _AchievementCard({required this.progress});

  final AchievementProgress progress;

  @override
  ConsumerState<_AchievementCard> createState() => _AchievementCardState();
}

class _AchievementCardState extends ConsumerState<_AchievementCard> {
  bool _claiming = false;

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(achievementServiceProvider)
          .claim(widget.progress);
      refreshAfterClaim(ref);
      if (result != null && mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => _RewardDialog(result: result),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not claim: $e')));
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final next = p.nextTarget;

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: p.earnedStars == 0
                        ? [Colors.grey.shade400, Colors.grey.shade500]
                        : [AppTheme.emerald, AppTheme.forest],
                  ),
                ),
                child: Icon(p.def.icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.def.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    Text(
                      next == null ? 'Every star earned' : p.def.describe(next),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Icon(
                      i < p.earnedStars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 26,
                      color: i < p.earnedStars
                          ? _starColors[i]
                          : Colors.grey.shade400,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress to the next star.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: p.progressToNext),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 10,
                backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(
                  p.isMaxed ? _gold : AppTheme.emerald,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  p.progressLabel,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ),
              if (next != null)
                Text(
                  'Next: +${p.def.rewards[p.earnedStars]} XP',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkMuted,
                  ),
                ),
            ],
          ),
          if (p.hasClaimable) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PressableScale(
                child: FilledButton.icon(
                  onPressed: _claiming ? null : _claim,
                  icon: _claiming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.card_giftcard_rounded),
                  label: Text('Claim +${p.claimableXp} XP'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.amber,
                    foregroundColor: AppTheme.ink,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The reward celebration: stars, XP, and a level-up if it happened.
class _RewardDialog extends StatelessWidget {
  const _RewardDialog({required this.result});

  final ClaimResult result;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final star in result.stars)
                  Icon(
                    Icons.star_rounded,
                    size: result.stars.length == 1 ? 72 : 52,
                    color: _starColors[star - 1],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            result.def.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          Text(
            result.stars.map((s) => bronzeSilverGold[s - 1]).join(' + ') +
                (result.stars.length == 1 ? ' star' : ' stars'),
            style: const TextStyle(color: AppTheme.inkMuted),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.amber,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.amber.withValues(alpha: 0.45),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Text(
              '+${result.xp} XP',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppTheme.ink,
              ),
            ),
          ),
          if (result.leveledUp) ...[
            const SizedBox(height: 14),
            Text(
              'Level up! ${result.levelBefore} → ${result.levelAfter}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.emerald,
                fontSize: 16,
              ),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
          ),
          child: const Text('Awesome!'),
        ),
      ],
    );
  }
}
