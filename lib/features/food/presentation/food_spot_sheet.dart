import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_components.dart';
import '../../locations/domain/location.dart';
import '../../locations/presentation/place_sheet.dart';
import '../../planner/domain/opening_hours.dart';
import '../../planner/data/saved_trips_repository.dart';
import '../../planner/presentation/trip_home_card.dart';
import '../domain/food.dart';
import '../domain/snack_stop.dart';
import 'signature_dishes_section.dart';

/// Details of a place to eat: open now or not, and **Go there** (a tracked
/// trip with directions). "Add to today's plan" when a planned trip is on.
Future<void> showFoodSpotSheet(BuildContext context, FoodSpot spot) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _FoodSpotSheet(spot, parentContext: context),
  );
}

/// The spot as a place a trip can go to.
ExploreLocation foodSpotAsPlace(FoodSpot spot) => ExploreLocation(
  id: spot.id,
  name: spot.name,
  category: LocationCategory.food,
  description: [spot.kind, ?spot.cuisine].join(' · '),
  latitude: spot.latitude,
  longitude: spot.longitude,
);

class _FoodSpotSheet extends ConsumerWidget {
  const _FoodSpotSheet(this.spot, {required this.parentContext});

  final FoodSpot spot;

  /// The screen under the sheet, for starting a trip after it closes.
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final trips = ref.watch(savedTripsListProvider).value ?? const [];
    final now = DateTime.now();
    final today = pickHomeTrip(trips, now);
    final todayTrip = today?.kind == HomeTripKind.today ? today : null;

    final hours = OpeningHours.parse(spot.openingHours);
    final openNow = hours?.isOpenAt(now);
    final todayHours = hours?.describeDay(now.weekday) ?? hours?.summary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (spot.diet != null) ...[
                  DietMark(spot.diet!),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(spot.name, style: text.titleLarge)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [spot.kind, ?spot.cuisine].join(' · '),
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            if (openNow != null || todayHours != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (openNow != null)
                    StatusBadge(
                      kind: openNow ? StatusKind.success : StatusKind.warning,
                      label: openNow ? 'Open now' : 'Closed now',
                    ),
                  if (todayHours != null)
                    Text(
                      openNow == null
                          ? 'Hours: $todayHours'
                          : 'Today: $todayHours',
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'From OpenStreetMap: check it\'s open before you go.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Go there',
              icon: Icons.directions_walk_rounded,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                startTripToPlace(parentContext, ref, foodSpotAsPlace(spot));
              },
            ),
            if (todayTrip != null) ...[
              const SizedBox(height: 8),
              AppButton.secondary(
                label: "Add to today's plan · Day ${todayTrip.dayIndex + 1}",
                icon: Icons.add_location_alt_outlined,
                expand: true,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  await ref
                      .read(savedTripsListProvider.notifier)
                      .save(
                        withSnackStop(
                          todayTrip.plan,
                          todayTrip.dayIndex,
                          spot,
                          now: DateTime.now(),
                        ),
                      );
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('${spot.name} added as your next stop.'),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
