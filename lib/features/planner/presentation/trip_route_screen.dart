import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_components.dart';
import '../data/saved_trips_repository.dart';
import 'itinerary_detail_screen.dart';

/// `/trips/:tripId[?day=N]`: a saved trip's itinerary, found by id, so trips
/// open through a route (deep links, predictable Back) instead of a pushed
/// screen. [day] is the day tab to open (0 = Day 1).
class TripRouteScreen extends ConsumerWidget {
  const TripRouteScreen({super.key, required this.tripId, this.day = 0});

  final String tripId;
  final int day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(savedTripsListProvider);
    final trips = tripsAsync.value;
    if (trips == null) {
      if (tripsAsync.hasError) {
        return Scaffold(
          appBar: AppBar(),
          body: ErrorState(
            error: tripsAsync.error!,
            onRetry: () => ref.invalidate(savedTripsListProvider),
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final plan = trips.where((t) => t.id == tripId).firstOrNull;
    if (plan == null) {
      return Scaffold(
        appBar: AppBar(),
        body: GateCard(
          icon: Icons.luggage_outlined,
          title: 'Trip not found',
          message: 'It may have been deleted, or its owner stopped sharing it.',
          actionLabel: 'Go to Trips',
          onAction: () => context.go('/trips'),
        ),
      );
    }
    return ItineraryDetailScreen(
      key: ValueKey(plan.id),
      plan: plan,
      initialDayIndex: day,
    );
  }
}
