import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../profile/application/user_profile_service.dart';
import '../application/daily_challenge_service.dart';

class DailyChallengeCard extends ConsumerWidget {
  const DailyChallengeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengeAsync = ref.watch(todayChallengeProgressProvider);

    return challengeAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (progress) {
        final challenge = progress.challenge;
        final isDone = progress.isCompleted;
        final isClaimed = progress.isClaimed;

        return GlassCard(
          margin: EdgeInsets.zero,
          radius: 24,
          tint: isDone ? AppTheme.amber : AppTheme.primaryGreen,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDone
                          ? AppTheme.amber.withValues(alpha: 0.2)
                          : AppTheme.primaryGreen.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isDone ? Icons.stars_rounded : Icons.flag_rounded,
                      color: isDone
                          ? AppTheme.amberText
                          : AppTheme.primaryGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'DAILY CHALLENGE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '+${challenge.xpReward} XP',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.amberText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                challenge.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                challenge.description,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.inkMuted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress.progressRatio,
                  minHeight: 7,
                  backgroundColor: Colors.black.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDone ? AppTheme.amber : AppTheme.primaryGreen,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${progress.currentValue} / ${challenge.targetValue}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkMuted,
                    ),
                  ),
                  if (isClaimed)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: AppTheme.primaryGreen,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Claimed',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                      ],
                    )
                  else if (isDone)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.amber,
                        foregroundColor: AppTheme.ink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () async {
                        final success = await ref
                            .read(dailyChallengeServiceProvider)
                            .claimReward(progress);
                        if (success) {
                          ref.invalidate(todayChallengeProgressProvider);
                          ref.invalidate(userProfileProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Claimed +${challenge.xpReward} XP! 🎉',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: const Text(
                        'Claim XP',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    )
                  else
                    const Text(
                      'In progress',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
