import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_components.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/components.dart';
import '../../core/theme/glass.dart';
import '../auth/application/display_name_provider.dart';
import '../challenges/presentation/streak_flame_badge.dart';
import '../locations/data/location_repository.dart';
import '../locations/domain/location.dart';
import '../passport/application/passport_service.dart';
import '../tracking/data/adventure_repository.dart';
import '../tracking/domain/adventure_session.dart';
import 'application/achievement_service.dart';
import 'application/user_profile_service.dart';
import 'domain/explorer_level.dart';
import 'rank_frame.dart';
import 'rank_rewards_card.dart';

const _pagePadding = EdgeInsets.symmetric(horizontal: 20);

/// The city you've explored most, for the one Exploration row on You.
final _topCityProvider = FutureProvider.autoDispose<RegionProgress?>((
  ref,
) async {
  final cities = await ref
      .watch(locationRepositoryProvider)
      .getCityCompletion();
  final started = cities.where((c) => c.discovered > 0).toList()
    ..sort((a, b) => b.discovered.compareTo(a.discovered));
  return started.firstOrNull;
});

/// You: who you are and how far you've come (one rank meter), your
/// collections, where you've explored, recent trips, and your records.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userProfileProvider);
    final name = ref.watch(displayNameProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(userProfileProvider);
            ref.invalidate(_topCityProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              Padding(
                padding: _pagePadding,
                child: Row(
                  children: [
                    Expanded(child: Text('You', style: text.headlineLarge)),
                    AppIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Settings',
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              statsAsync.when(
                loading: () => const _PassportSkeleton(),
                error: (error, _) => Padding(
                  padding: _pagePadding,
                  child: ErrorState(
                    error: error,
                    onRetry: () => ref.invalidate(userProfileProvider),
                  ),
                ),
                data: (stats) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeSlideIn(
                      child: Padding(
                        padding: _pagePadding,
                        child: _PassportHero(stats: stats, name: name),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: Padding(
                        padding: _pagePadding,
                        child: _StatsRow(stats: stats),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const FadeSlideIn(
                      delay: Duration(milliseconds: 100),
                      child: Padding(
                        padding: _pagePadding,
                        child: _Collections(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: _pagePadding,
                      child: _ExplorationSection(),
                    ),
                    Padding(
                      padding: _pagePadding,
                      child: _RecentTrips(adventures: stats.recentAdventures),
                    ),
                    const SizedBox(height: 8),
                    // Everything you've recorded, one tap from You.
                    const Padding(
                      padding: _pagePadding,
                      child: _YourRecordsGroup(),
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
}

String _formatXp(int xp) => NumberFormat.decimalPattern().format(xp);

/// Identity and the one progress meter: your rank, the bar to the next
/// one, and what it unlocks. XP shows once, as what feeds the bar.
class _PassportHero extends StatelessWidget {
  const _PassportHero({required this.stats, required this.name});

  final UserStats stats;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final onHero = Theme.of(context).colorScheme.onPrimary;
    final muted = onHero.withValues(alpha: 0.85);
    final rank = ExplorerLevel.rankProgress(stats.totalXp);
    final next = rank.next;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

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
                      style: text.titleLarge?.copyWith(color: onHero),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${rank.current.title} · Level ${stats.levelNumber}',
                      style: text.bodyMedium?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const StreakFlameBadge(),
            ],
          ),
          const SizedBox(height: 20),
          Semantics(
            label: next == null
                ? '${_formatXp(stats.totalXp)} XP. Top rank reached.'
                : '${_formatXp(stats.totalXp)} XP. '
                      '${_formatXp(rank.xpToNext)} XP to ${next.title}.',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${_formatXp(stats.totalXp)} XP',
                      style: text.titleSmall?.copyWith(color: onHero),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        next == null
                            ? 'Top rank'
                            : '${_formatXp(rank.xpToNext)} XP to ${next.title}',
                        textAlign: TextAlign.end,
                        style: text.labelLarge?.copyWith(color: muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: rank.progress.clamp(0.0, 1.0)),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 900),
                    curve: AppMotion.curve,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 10,
                      backgroundColor: onHero.withValues(alpha: 0.22),
                      valueColor: const AlwaysStoppedAnimation(AppTheme.amber),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: onHero,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => showRankStylesSheet(context, name: name),
            icon: const Icon(Icons.workspace_premium_outlined, size: 20),
            label: Text(
              next == null
                  ? 'Rank & styles'
                  : 'Rank & styles · ${next.title} unlocks a new frame',
            ),
          ),
        ],
      ),
    );
  }
}

/// Three lifetime numbers in one card: trips, distance on foot, places.
class _StatsRow extends ConsumerWidget {
  const _StatsRow({required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(visitedPlaceIdsProvider).value?.length;
    final colors = AppColors.of(context);
    Widget stat(String value, String label) => Expanded(
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          stat('${stats.completedAdventureCount}', 'Trips'),
          stat('${stats.totalDistanceKm.toStringAsFixed(1)} km', 'On foot'),
          stat(places == null ? '–' : '$places', 'Places visited'),
        ],
      ),
    );
  }
}

/// Achievements, stamps and the exploration map as three equal tiles.
class _Collections extends ConsumerWidget {
  const _Collections();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(achievementsProvider).value;
    final earned = achievements?.fold<int>(0, (n, a) => n + a.earnedStars);
    final total = (achievements?.length ?? 0) * 3;
    final waitingXp =
        achievements?.fold<int>(0, (n, a) => n + a.claimableXp) ?? 0;
    final stamps = ref.watch(passportStampsProvider).value?.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Collections'),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CollectionTile(
                  icon: Icons.emoji_events_outlined,
                  value: earned == null ? '–' : '$earned/$total',
                  label: 'Stars',
                  badge: waitingXp > 0 ? 'Claim' : null,
                  onTap: () => context.push('/achievements'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CollectionTile(
                  icon: Icons.approval_outlined,
                  value: stamps == null ? '–' : '$stamps',
                  label: stamps == 1 ? 'City stamp' : 'City stamps',
                  onTap: () => context.push('/passport-stamps'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CollectionTile(
                  icon: Icons.route_outlined,
                  value: 'Map',
                  label: 'Routes & poster',
                  onTap: () => context.push('/heatmap'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One collection on You: an icon, a number and what it counts, with an
/// optional badge ("Claim").
class CollectionTile extends StatelessWidget {
  const CollectionTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String value;
  final String label;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      label: '$value $label${badge == null ? '' : ', $badge'}',
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: Theme.of(context).colorScheme.primary),
                    const Spacer(),
                    if (badge != null) Tag(badge!, tone: TagTone.reward),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
                Text(
                  label,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Your most-explored city as one progress row, with every region a tap
/// away. Nothing explored yet: a short invitation instead of 0% bars.
class _ExplorationSection extends ConsumerWidget {
  const _ExplorationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(_topCityProvider);
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final city = top.value;
    if (top.isLoading && city == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Exploration',
          action: city == null
              ? null
              : AppButton.tertiary(
                  label: 'All regions',
                  onPressed: () => context.push('/regions'),
                ),
        ),
        if (city == null)
          Text(
            'Places you discover fill in your map here.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          )
        else
          RegionProgressRow(progress: city),
      ],
    );
  }
}

/// A region's name, how many of its places you've found, and a bar.
class RegionProgressRow extends StatelessWidget {
  const RegionProgressRow({super.key, required this.progress});

  final RegionProgress progress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final percent = (progress.percent * 100).round();
    return Semantics(
      label:
          '${progress.name}: ${progress.discovered} of ${progress.total} '
          'places, $percent percent',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    progress.name,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                ),
                Text(
                  '${progress.discovered} of ${progress.total} places',
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: progress.percent,
                minHeight: 8,
                backgroundColor: colors.surfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The last three trips, each opening its journal page.
class _RecentTrips extends StatelessWidget {
  const _RecentTrips({required this.adventures});

  final List<AdventureSession> adventures;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Recent trips'),
        if (adventures.isEmpty)
          Text(
            'Your trips show up here after you finish one.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          )
        else
          AppListGroup(
            children: [
              for (final adventure in adventures.take(3))
                AppListTile(
                  leading: Icon(
                    Icons.hiking_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: adventure.title,
                  subtitle: [
                    tripDateLabel(adventure.startedAt, DateTime.now()),
                    '${(adventure.trekMeters / 1000).toStringAsFixed(1)} km '
                        'on foot',
                    if (adventure.xpEarned > 0) '+${adventure.xpEarned} XP',
                  ].join(' · '),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                  ),
                  onTap: () => context.push('/journal/${adventure.id}'),
                ),
            ],
          ),
      ],
    );
  }
}

/// "Today", "Yesterday", "3 days ago" for the last week, then a date
/// ("12 Mar", or "12 Mar 2025" in another year).
String tripDateLabel(DateTime date, DateTime now) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return DateFormat(date.year == now.year ? 'd MMM' : 'd MMM y').format(date);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?action,
      ],
    ),
  );
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
            SkeletonBox(height: 190, radius: AppRadius.lg),
            SizedBox(height: 12),
            SkeletonBox(height: 72, radius: AppRadius.md),
            SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: SkeletonBox(height: 96, radius: AppRadius.md)),
                SizedBox(width: 8),
                Expanded(child: SkeletonBox(height: 96, radius: AppRadius.md)),
                SizedBox(width: 8),
                Expanded(child: SkeletonBox(height: 96, radius: AppRadius.md)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Links to the places your trips are kept: journal, photos, calendar.
class _YourRecordsGroup extends StatelessWidget {
  const _YourRecordsGroup();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget row(IconData icon, String title, String subtitle, String path) =>
        AppListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: title,
          subtitle: subtitle,
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colors.textSecondary,
          ),
          onTap: () => context.push(path),
        );
    return AppListGroup(
      title: 'YOUR TRIPS & PHOTOS',
      children: [
        row(
          Icons.menu_book_outlined,
          'Journal',
          'Every trip you\'ve tracked',
          '/journal',
        ),
        row(
          Icons.photo_library_outlined,
          'Memories',
          'Photos from your trips',
          '/memories',
        ),
        row(
          Icons.calendar_month_outlined,
          'Calendar',
          'Your trips by date',
          '/calendar',
        ),
      ],
    );
  }
}
