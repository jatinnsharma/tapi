import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../tracking/data/adventure_repository.dart';
import '../../tracking/domain/adventure_session.dart';
import 'adventure_detail_screen.dart';

final journalAdventuresProvider =
    FutureProvider.autoDispose<List<AdventureSession>>((ref) {
      return ref
          .watch(adventureRepositoryProvider)
          .getRecentAdventures(limit: 100);
    });

class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adventuresAsync = ref.watch(journalAdventuresProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adventure Journal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'Calendar',
            onPressed: () => context.push('/calendar'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: adventuresAsync.when(
        loading: () => const Padding(
          padding: AppSpacing.page,
          child: Shimmer(
            child: Column(
              children: [
                SkeletonBox(height: 78, radius: 24),
                SizedBox(height: 12),
                SkeletonBox(height: 78, radius: 24),
                SizedBox(height: 12),
                SkeletonBox(height: 78, radius: 24),
                SizedBox(height: 12),
                SkeletonBox(height: 78, radius: 24),
              ],
            ),
          ),
        ),
        error: (error, stack) => Padding(
          padding: AppSpacing.page,
          child: Align(
            alignment: Alignment.topCenter,
            child: EmptyStateCard(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load journal',
              message: '$error',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(journalAdventuresProvider),
            ),
          ),
        ),
        data: (adventures) {
          if (adventures.isEmpty) {
            return const Padding(
              padding: AppSpacing.page,
              child: Align(
                alignment: Alignment.topCenter,
                child: EmptyStateCard(
                  icon: Icons.menu_book_outlined,
                  title: 'No adventures yet',
                  message: 'No adventures recorded yet.',
                ),
              ),
            );
          }
          return RefreshIndicator(
            color: AppTheme.forest,
            onRefresh: () async => ref.invalidate(journalAdventuresProvider),
            child: ListView.builder(
              padding: AppSpacing.page,
              itemCount: adventures.length,
              itemBuilder: (context, index) {
                final adventure = adventures[index];
                final color = _statusColor(adventure.status);
                return FadeSlideIn(
                  delay: Duration(milliseconds: 50 * (index > 5 ? 5 : index)),
                  child: SoftCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              AdventureDetailScreen(adventureId: adventure.id),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            _statusIcon(adventure.status),
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                adventure.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_formatDate(adventure.startedAt)} • '
                                '${(adventure.trekMeters / 1000).toStringAsFixed(1)} km trek • '
                                '+${adventure.xpEarned} XP',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.inkMuted,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(AdventureStatus status) {
    switch (status) {
      case AdventureStatus.completed:
        return AppTheme.emerald;
      case AdventureStatus.active:
        return AppTheme.forest;
      case AdventureStatus.paused:
        return AppTheme.amber;
      case AdventureStatus.discarded:
      case AdventureStatus.unverified:
        return AppTheme.inkMuted;
    }
  }

  IconData _statusIcon(AdventureStatus status) {
    switch (status) {
      case AdventureStatus.completed:
        return Icons.check_circle;
      case AdventureStatus.active:
        return Icons.play_circle;
      case AdventureStatus.paused:
        return Icons.pause_circle;
      case AdventureStatus.discarded:
        return Icons.cancel;
      case AdventureStatus.unverified:
        return Icons.help_outline_rounded;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays <= 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
