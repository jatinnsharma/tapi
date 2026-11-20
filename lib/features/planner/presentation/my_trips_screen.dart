import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/confirm_destructive.dart';
import '../domain/trip_groups.dart';
import '../data/saved_trips_repository.dart';
import '../domain/trip_plan.dart';

class MyTripsScreen extends ConsumerWidget {
  const MyTripsScreen({super.key});

  Future<void> _deleteTrip(
    BuildContext context,
    WidgetRef ref,
    TripPlan plan,
  ) async {
    final uid = ref.read(tripSyncUidProvider);
    // Someone else's shared trip is left, not deleted: they keep it.
    final leaving = uid != null && !plan.isOwnedBy(uid);
    final confirmed = await confirmDestructive(
      context,
      title: leaving ? 'Leave this trip?' : 'Delete this trip?',
      message: leaving
          ? 'You\'ll stop seeing "${plan.title}". The friend who shared it '
                'keeps their copy.'
          : plan.isShared
          ? 'This removes "${plan.title}" for everyone it\'s shared with.'
          : '"${plan.title}" will be removed from this phone and your '
                'account.',
      confirmLabel: leaving ? 'Leave trip' : 'Delete trip',
    );
    if (!confirmed) return;
    await ref.read(savedTripsListProvider.notifier).delete(plan.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(leaving ? 'Left the trip' : 'Trip deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(savedTripsListProvider);
    final uid = ref.watch(tripSyncUidProvider);
    final hasTrips = tripsAsync.value?.isNotEmpty ?? false;
    Future<void> refresh() =>
        ref.read(savedTripsListProvider.notifier).refresh();

    return Scaffold(
      // A tab now (Trips), so no back arrow.
      appBar: AppBar(title: const Text('Trips')),
      body: SafeArea(
        child: tripsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ErrorState(
            error: err,
            onRetry: () => ref.invalidate(savedTripsListProvider),
          ),
          data: (trips) {
            if (trips.isEmpty) {
              // Scrollable so pull-to-refresh can fetch trips from the cloud.
              return RefreshIndicator(
                onRefresh: refresh,
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: constraints.maxHeight,
                      child: GateCard(
                        icon: Icons.luggage_outlined,
                        title: 'No trips yet',
                        message:
                            'Tell us where you\'re going and get a day-by-day '
                            'plan with real places, saved on this phone.',
                        actionLabel: 'Plan a trip',
                        onAction: () => context.push('/trip-planner'),
                      ),
                    ),
                  ),
                ),
              );
            }

            final groups = groupTrips(trips, DateTime.now());
            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Room for the button floating over the list.
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  for (final MapEntry(key: group, value: plans)
                      in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text(
                        group.label.toUpperCase(),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.of(context).textSecondary,
                            ),
                      ),
                    ),
                    for (final plan in plans) ...[
                      TripCard(
                        plan: plan,
                        highlight: group == TripGroup.now,
                        sharedWithMe: uid != null && !plan.isOwnedBy(uid),
                        onOpen: () => context.push('/trips/${plan.id}'),
                        onDelete: () => _deleteTrip(context, ref, plan),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
      // Empty, the page's own button does this.
      floatingActionButton: hasTrips
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Plan a trip'),
              onPressed: () => context.push('/trip-planner'),
            )
          : null,
    );
  }
}

/// A saved trip: where, when, how far along, and who it's shared with.
class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.plan,
    required this.onOpen,
    required this.onDelete,
    this.highlight = false,
    this.sharedWithMe = false,
  });

  final TripPlan plan;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  /// Happening now: drawn in the brand tint.
  final bool highlight;

  /// Someone else's shared trip: "Leave" instead of "Delete".
  final bool sharedWithMe;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dates = tripDates(plan);
    final dayFormat = DateFormat('d MMM');
    final days = plan.days.isEmpty ? plan.daysCount : plan.days.length;
    final when = dates == null
        ? 'No dates yet'
        : days <= 1
        ? dayFormat.format(dates.start)
        : '${dayFormat.format(dates.start)} – ${dayFormat.format(dates.end)}';
    final total = plan.totalStops;
    final done = completedStops(plan);

    return Material(
      color: highlight ? scheme.primaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: highlight ? scheme.primary : colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              when,
                              '$days ${days == 1 ? 'day' : 'days'}',
                              plan.companion.label,
                            ].join(' · '),
                            style: text.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Trip options',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (_) => onDelete(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            sharedWithMe
                                ? Icons.logout_rounded
                                : Icons.delete_outline_rounded,
                          ),
                          title: Text(
                            sharedWithMe ? 'Leave trip' : 'Delete trip',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (plan.isShared) ...[
                const SizedBox(height: 6),
                Tag(
                  sharedWithMe
                      ? 'Shared with you'
                      : 'Shared with ${plan.memberUids.length - 1} '
                            '${plan.memberUids.length == 2 ? 'friend' : 'friends'}',
                  icon: Icons.group_outlined,
                ),
              ],
              if (total > 0) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: LinearProgressIndicator(
                          value: done / total,
                          minHeight: 6,
                          backgroundColor: colors.surfaceMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        done == 0
                            ? '$total stops planned'
                            : '$done of $total stops done',
                        style: text.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
