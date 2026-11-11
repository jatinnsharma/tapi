import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../data/saved_trips_repository.dart';
import '../domain/trip_plan.dart';
import 'itinerary_detail_screen.dart';

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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(leaving ? 'Leave Trip?' : 'Delete Trip?'),
        content: Text(
          leaving
              ? 'You will stop seeing "${plan.title}". The friend who shared it keeps their copy.'
              : plan.isShared
              ? 'This removes "${plan.title}" for everyone it is shared with.'
              : 'Are you sure you want to remove "${plan.title}" from your saved trips?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(leaving ? 'Leave' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(savedTripsListProvider.notifier).delete(plan.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(leaving ? 'Left the trip' : 'Trip deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(savedTripsListProvider);
    final uid = ref.watch(tripSyncUidProvider);
    Future<void> refresh() =>
        ref.read(savedTripsListProvider.notifier).refresh();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Trips & Itineraries'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/explore');
            }
          },
        ),
      ),
      body: SafeArea(
        child: tripsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Text(
              'Could not load trips: $err',
              style: const TextStyle(color: AppTheme.inkMuted),
            ),
          ),
          data: (trips) {
            if (trips.isEmpty) {
              final empty = Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.flight_takeoff,
                          size: 40,
                          color: AppTheme.forest,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'No Saved Trips Yet',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Generate an AI itinerary for Varanasi, Goa, Manali or any Indian destination and save it offline here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.inkMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.auto_awesome, size: 20),
                        label: const Text('Plan Your First Trip'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.forest,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => context.push('/trip-planner'),
                      ),
                    ],
                  ),
                ),
              );
              // Scrollable so pull-to-refresh can fetch trips from the cloud.
              return RefreshIndicator(
                onRefresh: refresh,
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: constraints.maxHeight,
                      child: empty,
                    ),
                  ),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                itemCount: trips.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final plan = trips[index];
                  return SoftCard(
                    padding: const EdgeInsets.all(16),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ItineraryDetailScreen(plan: plan),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${plan.daysCount} DAYS',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.forest,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.amber.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                plan.companion.label.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.amberText,
                                ),
                              ),
                            ),
                            if (plan.isShared) ...[
                              const SizedBox(width: 8),
                              Tooltip(
                                message: uid != null && !plan.isOwnedBy(uid)
                                    ? 'Shared with you by a friend'
                                    : 'Shared with ${plan.memberUids.length - 1} friend${plan.memberUids.length == 2 ? '' : 's'}',
                                child: const Icon(
                                  Icons.group_outlined,
                                  size: 18,
                                  color: AppTheme.forest,
                                ),
                              ),
                            ],
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                uid != null && !plan.isOwnedBy(uid)
                                    ? Icons.logout
                                    : Icons.delete_outline,
                                color: Colors.grey,
                                size: 20,
                              ),
                              tooltip: uid != null && !plan.isOwnedBy(uid)
                                  ? 'Leave trip'
                                  : 'Delete trip',
                              onPressed: () => _deleteTrip(context, ref, plan),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          plan.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '📍 ${plan.destination} · ${plan.totalStops} planned stops · ${plan.pace.label} pace',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.inkMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (plan.overview != null &&
                            plan.overview!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            plan.overview!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.ink,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'New Trip',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        backgroundColor: AppTheme.forest,
        onPressed: () => context.push('/trip-planner'),
      ),
    );
  }
}
