import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import 'rank_frame.dart';
import '../../core/theme/components.dart';
import '../../core/theme/glass.dart';
import '../auth/application/display_name_provider.dart';
import '../journal/presentation/adventure_detail_screen.dart';
import '../locations/data/location_repository.dart';
import '../locations/domain/location.dart';
import '../tracking/domain/adventure_session.dart';
import 'application/user_profile_service.dart';
import 'application/achievement_service.dart';

const _pagePadding = EdgeInsets.symmetric(horizontal: 20);

class _RegionalCompletion {
  const _RegionalCompletion({
    required this.neighborhoods,
    required this.cities,
    required this.districts,
    required this.regions,
    required this.countries,
  });

  final List<RegionProgress> neighborhoods;
  final List<RegionProgress> cities;
  final List<RegionProgress> districts;
  final List<RegionProgress> regions;
  final List<RegionProgress> countries;
}

final _regionalCompletionProvider =
    FutureProvider.autoDispose<_RegionalCompletion>((ref) async {
      final repository = ref.watch(locationRepositoryProvider);
      return _RegionalCompletion(
        neighborhoods: await repository.getNeighborhoodCompletion(),
        cities: await repository.getCityCompletion(),
        districts: await repository.getDistrictCompletion(),
        regions: await repository.getRegionCompletion(),
        countries: await repository.getCountryCompletion(),
      );
    });

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userProfileProvider);
    final name = ref.watch(displayNameProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.forest,
          onRefresh: () async => ref.invalidate(userProfileProvider),
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              Padding(
                padding: _pagePadding,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Passport',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    RoundIconButton(
                      icon: Icons.menu_book_outlined,
                      tooltip: 'Adventure Journal',
                      onPressed: () => context.push('/journal'),
                    ),
                    const SizedBox(width: 10),
                    RoundIconButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Exploration Preferences',
                      onPressed: () => context.push('/preferences'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              statsAsync.when(
                loading: () => const _PassportSkeleton(),
                error: (error, stack) => Padding(
                  padding: _pagePadding,
                  child: EmptyStateCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not load profile',
                    message: '$error',
                    actionLabel: 'Try again',
                    onAction: () => ref.invalidate(userProfileProvider),
                  ),
                ),
                data: (stats) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FadeSlideIn(
                      child: Padding(
                        padding: _pagePadding,
                        child: _PassportHero(stats: stats, name: name),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 80),
                      child: Padding(
                        padding: _pagePadding,
                        child: _StatsRow(stats: stats),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 140),
                      child: Padding(
                        padding: _pagePadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader(title: 'Achievements'),
                            const _AchievementsCard(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: _pagePadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader(title: 'Regional Exploration'),
                          _buildRegionalCompletion(ref),
                          const SectionHeader(
                            title: 'Recent Adventures',
                            padding: EdgeInsets.only(top: 22, bottom: 12),
                          ),
                          _buildRecentAdventures(
                            context,
                            stats.recentAdventures,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegionalCompletion(WidgetRef ref) {
    final completionAsync = ref.watch(_regionalCompletionProvider);
    return completionAsync.when(
      loading: () => const Shimmer(child: SkeletonBox(height: 70, radius: 24)),
      error: (error, stack) => EmptyStateCard(
        icon: Icons.public_off_outlined,
        title: 'Could not load regional progress',
        message: '$error',
      ),
      data: (completion) {
        if (completion.cities.isEmpty) {
          return const EmptyStateCard(
            icon: Icons.public_outlined,
            title: 'No locations discovered yet',
            message: 'Start exploring and your regions will fill up here.',
          );
        }
        // Matches the spec's §28 full regional hierarchy:
        // Neighborhood → City → District → Region(State) → Country
        return Column(
          children: [
            for (final neighborhood in completion.neighborhoods)
              _RegionRow(progress: neighborhood),
            const SizedBox(height: 8),
            for (final city in completion.cities)
              _RegionRow(progress: city, emphasize: true),
            const SizedBox(height: 8),
            for (final district in completion.districts)
              _RegionRow(progress: district, emphasize: true),
            const SizedBox(height: 8),
            for (final region in completion.regions)
              _RegionRow(progress: region, emphasize: true),
            const SizedBox(height: 8),
            for (final country in completion.countries)
              _RegionRow(progress: country, emphasize: true),
          ],
        );
      },
    );
  }

  Widget _buildRecentAdventures(
    BuildContext context,
    List<AdventureSession> adventures,
  ) {
    if (adventures.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.hiking_outlined,
        title: 'No adventures yet',
        message: 'Start one from the Explore tab!',
      );
    }

    return Column(
      children: [
        for (final adventure in adventures)
          SoftCard(
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
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.emerald, AppTheme.forest],
                    ),
                  ),
                  child: const Icon(Icons.forest, color: Colors.white),
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
                        '${_relativeDate(adventure.startedAt)} • ${(adventure.trekMeters / 1000).toStringAsFixed(1)} km trek • +${adventure.xpEarned} XP',
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
      ],
    );
  }

  String _relativeDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays <= 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    return '${difference.inDays} days ago';
  }
}

/// Deep-green hero: avatar, level and an amber XP progress bar.
class _PassportHero extends StatelessWidget {
  const _PassportHero({required this.stats, required this.name});

  final UserStats stats;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final toNext = stats.xpForNextLevel - stats.xpIntoLevel;
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RankFrame(child: AppAvatar(initial: name ?? 'E', size: 56)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name ?? 'Explorer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Level ${stats.levelNumber} · ${stats.levelTitle}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${stats.totalXp} XP',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              Text(
                '$toNext XP to Level ${stats.levelNumber + 1}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: stats.levelProgress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 10,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                valueColor: const AlwaysStoppedAnimation(AppTheme.amber),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatTile(
            value: '${stats.completedAdventureCount}',
            label: 'Adventures',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            value: '${stats.totalDistanceKm.toStringAsFixed(1)} km',
            label: 'Trekked',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            value: _compactSteps(stats.totalTrekSteps),
            label: 'Steps',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(value: '${stats.totalXp}', label: 'Total XP'),
        ),
      ],
    );
  }
}

/// "950", "12.4k", "1.2M": fits a small stat tile.
String _compactSteps(int steps) {
  if (steps < 1000) return '$steps';
  if (steps < 1000000) {
    final k = steps / 1000;
    return '${k.toStringAsFixed(k < 100 ? 1 : 0)}k';
  }
  return '${(steps / 1000000).toStringAsFixed(1)}M';
}

/// Passport entry to the Achievements screen: stars earned so far, and a
/// badge with the XP waiting to be claimed.
class _AchievementsCard extends ConsumerWidget {
  const _AchievementsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(achievementsProvider).value;
    final earned = achievements?.fold<int>(0, (n, a) => n + a.earnedStars) ?? 0;
    final total = (achievements?.length ?? 0) * 3;
    final waitingXp =
        achievements?.fold<int>(0, (n, a) => n + a.claimableXp) ?? 0;

    return SoftCard(
      padding: const EdgeInsets.all(16),
      onTap: () => context.push('/achievements'),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.amber.withValues(alpha: 0.2),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: AppTheme.amberText,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievements == null
                      ? 'Achievements'
                      : '$earned / $total stars',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  waitingXp > 0
                      ? '$waitingXp XP waiting to be claimed!'
                      : 'Earn stars, claim bonus XP',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: waitingXp > 0
                        ? FontWeight.w800
                        : FontWeight.w400,
                    color: waitingXp > 0
                        ? AppTheme.amberText
                        : AppTheme.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (waitingXp > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.amber,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Claim',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                  fontSize: 13,
                ),
              ),
            )
          else
            const Icon(Icons.chevron_right_rounded, color: AppTheme.inkMuted),
        ],
      ),
    );
  }
}

class _RegionRow extends StatelessWidget {
  const _RegionRow({required this.progress, this.emphasize = false});

  final RegionProgress progress;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  progress.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 15,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              Text(
                '${progress.discovered} / ${progress.total}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.percent,
              minHeight: 8,
              backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(
                emphasize ? AppTheme.emerald : AppTheme.amber,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(progress.percent * 100).toStringAsFixed(1)}% explored',
            style: const TextStyle(fontSize: 12, color: AppTheme.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _PassportSkeleton extends StatelessWidget {
  const _PassportSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: _pagePadding,
      child: Shimmer(
        child: Column(
          children: [
            SkeletonBox(height: 170, radius: 32),
            SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: SkeletonBox(height: 82, radius: 22)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 82, radius: 22)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 82, radius: 22)),
              ],
            ),
            SizedBox(height: 24),
            SkeletonBox(height: 120, radius: 24),
          ],
        ),
      ),
    );
  }
}
