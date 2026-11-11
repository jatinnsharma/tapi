import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../locations/data/place_photos_service.dart';
import '../../locations/domain/location.dart';
import '../../locations/presentation/place_style.dart';
import '../../weather/data/weather_repository.dart';
import '../../weather/domain/weather_model.dart';
import '../data/opening_hours_service.dart';
import '../data/saved_trips_repository.dart';
import '../domain/opening_hours.dart';
import '../domain/trip_extras.dart';
import '../domain/trip_plan.dart';
import 'itinerary_detail_screen.dart';
import 'stop_actions.dart';
import 'stop_hours.dart';

enum HomeTripKind {
  /// The trip is on today.
  today,

  /// The next trip with dates still to come.
  upcoming,

  /// A recent trip with no dates yet.
  planning,
}

typedef HomeTrip = ({
  TripPlan plan,
  HomeTripKind kind,

  /// Today's day of the trip (0 = Day 1), for [HomeTripKind.today].
  int dayIndex,

  /// Days until it starts, for [HomeTripKind.upcoming].
  int daysAway,
});

/// Which trip Home features: one on today, else the soonest coming up, else
/// one being planned (no dates, made in the last [planningWindow]). Null when
/// there's none of these.
HomeTrip? pickHomeTrip(
  List<TripPlan> trips,
  DateTime now, {
  Duration planningWindow = const Duration(days: 45),
}) {
  final today = DateUtils.dateOnly(now);
  HomeTrip? upcoming;
  HomeTrip? planning;
  for (final trip in trips) {
    final start = trip.startDate == null
        ? null
        : DateUtils.dateOnly(trip.startDate!);
    if (start == null) {
      final recent = now.difference(trip.createdAt) <= planningWindow;
      if (recent &&
          (planning == null ||
              trip.createdAt.isAfter(planning.plan.createdAt))) {
        planning = (
          plan: trip,
          kind: HomeTripKind.planning,
          dayIndex: 0,
          daysAway: 0,
        );
      }
      continue;
    }
    final dayIndex = today.difference(start).inDays;
    if (dayIndex >= 0 && dayIndex < trip.daysCount) {
      return (
        plan: trip,
        kind: HomeTripKind.today,
        dayIndex: dayIndex.clamp(0, trip.days.length - 1),
        daysAway: 0,
      );
    }
    if (dayIndex < 0 && (upcoming == null || -dayIndex < upcoming.daysAway)) {
      upcoming = (
        plan: trip,
        kind: HomeTripKind.upcoming,
        dayIndex: 0,
        daysAway: -dayIndex,
      );
    }
  }
  return upcoming ?? planning;
}

typedef _ForecastKey = ({double lat, double lng, DateTime day});

final _firstDayForecastProvider = FutureProvider.autoDispose
    .family<DailyForecast?, _ForecastKey>((ref, key) async {
      final days = await ref
          .read(weatherRepositoryProvider)
          .getDailyForecast(key.lat, key.lng, start: key.day, days: 1);
      return days == null || days.isEmpty ? null : days.first;
    });

/// Home's "Your trip": today's next stop with a Go button while a trip is on,
/// a countdown with weather and packing before it, or an invitation to plan
/// one.
class TripHomeCard extends ConsumerWidget {
  const TripHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(savedTripsListProvider).value;
    if (trips == null) return const SizedBox.shrink(); // Loading: no flash.
    final featured = pickHomeTrip(trips, DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: featured?.kind == HomeTripKind.today
              ? 'Your trip today'
              : 'Your trip',
          actionLabel: trips.isEmpty ? null : 'All trips',
          onAction: trips.isEmpty ? null : () => context.push('/my-trips'),
        ),
        switch (featured) {
          null => const _PlanTripInvite(),
          (
            kind: HomeTripKind.today,
            :final plan,
            :final dayIndex,
            daysAway: _,
          ) =>
            _TodayCard(plan: plan, dayIndex: dayIndex),
          (
            kind: HomeTripKind.upcoming,
            :final plan,
            dayIndex: _,
            :final daysAway,
          ) =>
            _UpcomingCard(plan: plan, daysAway: daysAway),
          (
            kind: HomeTripKind.planning,
            :final plan,
            dayIndex: _,
            daysAway: _,
          ) =>
            _PlanningCard(plan: plan),
        },
      ],
    );
  }
}

void _openTrip(BuildContext context, TripPlan plan, {int day = 0}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ItineraryDetailScreen(plan: plan, initialDayIndex: day),
    ),
  );
}

const _titleStyle = TextStyle(
  fontSize: 19,
  fontWeight: FontWeight.w800,
  color: AppTheme.ink,
  letterSpacing: -0.3,
);
const _mutedStyle = TextStyle(fontSize: 13, color: AppTheme.inkMuted);

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: AppTheme.primary,
    ),
  );
}

// ---------------------------------------------------------------------------
// Today
// ---------------------------------------------------------------------------

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.plan, required this.dayIndex});

  final TripPlan plan;
  final int dayIndex;

  Future<void> _go(BuildContext context, WidgetRef ref, int stopIndex) async {
    final stop = plan.days[dayIndex].stops[stopIndex];
    final reached = await goToStop(context, ref, plan, dayIndex, stopIndex);
    if (!reached) return;
    // Use the latest copy: it may have changed during the trip.
    final latest = ref
        .read(savedTripsListProvider)
        .value
        ?.firstWhere((t) => t.id == plan.id, orElse: () => plan);
    await ref
        .read(savedTripsListProvider.notifier)
        .save(withStopCompleted(latest ?? plan, stop.id, true));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = plan.days[dayIndex];
    final next = day.stops.indexWhere((s) => !s.isCompleted);
    final done = day.stops.where((s) => s.isCompleted).length;

    return SoftCard(
      padding: const EdgeInsets.all(16),
      onTap: () => _openTrip(context, plan, day: dayIndex),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(
            'Day ${day.dayNumber} of ${plan.daysCount} · ${plan.destination}',
          ),
          const SizedBox(height: 4),
          Text(day.title, style: _titleStyle, maxLines: 2),
          if (day.stops.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: done / day.stops.length,
                minHeight: 6,
                backgroundColor: AppTheme.sage.withValues(alpha: 0.4),
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text('$done of ${day.stops.length} stops done', style: _mutedStyle),
          ],
          const SizedBox(height: 12),
          if (next < 0)
            Row(
              children: [
                const Icon(
                  Icons.celebration_rounded,
                  color: AppTheme.amberText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dayIndex + 1 < plan.days.length
                        ? 'Day done! Tomorrow: ${plan.days[dayIndex + 1].title}'
                        : 'Last day done. What a trip!',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          else
            _NextStop(
              plan: plan,
              stop: day.stops[next],
              day: DateUtils.dateOnly(DateTime.now()),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (next >= 0) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _go(context, ref, next),
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: const Text('Go'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.forest,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openTrip(context, plan, day: dayIndex),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  child: const Text("Today's plan"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextStop extends ConsumerWidget {
  const _NextStop({required this.plan, required this.stop, required this.day});

  final TripPlan plan;
  final TripStop stop;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = stopAsPlace(stop, plan.destination);
    final photo = ref
        .watch(placePhotosProvider(place.photosKey))
        .value
        ?.firstOrNull;
    final hoursAsync = ref.watch(
      dayOpeningHoursProvider(
        encodeHoursQueries([
          (
            key: stop.id,
            placeId: stop.placeId,
            name: stop.placeName,
            lat: stop.latitude,
            lng: stop.longitude,
          ),
        ]),
      ),
    );
    final mapHours = OpeningHours.parse(hoursAsync.value?[stop.id]);
    final aiHours = OpeningHours.parse(stop.openingHours);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 72,
            height: 72,
            child: photo != null
                ? Image.network(
                    photo.thumbUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _Artwork(place.category),
                  )
                : _Artwork(place.category),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Next · ${stop.timeSlot}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkMuted,
                ),
              ),
              Text(
                stop.placeName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 2),
              StopHours(
                hours: mapHours ?? aiHours,
                source: mapHours != null
                    ? HoursSource.map
                    : (aiHours != null ? HoursSource.ai : null),
                loading: hoursAsync.isLoading,
                plannedDay: day,
                timeSlot: stop.timeSlot,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork(this.category);
  final LocationCategory category;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: category.gradient,
      ),
    ),
    child: Icon(category.icon, color: Colors.white),
  );
}

// ---------------------------------------------------------------------------
// Coming up
// ---------------------------------------------------------------------------

class _UpcomingCard extends ConsumerWidget {
  const _UpcomingCard({required this.plan, required this.daysAway});

  final TripPlan plan;
  final int daysAway;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = DateUtils.dateOnly(plan.startDate!);
    final end = start.add(Duration(days: plan.daysCount - 1));
    final fmt = DateFormat('d MMM');
    final when = daysAway == 1 ? 'tomorrow' : 'in $daysAway days';

    final firstStop = plan.days.expand((d) => d.stops).firstOrNull;
    final forecast = firstStop == null || daysAway > 15
        ? null
        : ref
              .watch(
                _firstDayForecastProvider((
                  lat: firstStop.latitude,
                  lng: firstStop.longitude,
                  day: start,
                )),
              )
              .value;

    final items = packingListFor(plan).expand((s) => s.items).toList();
    final packed = items.where(plan.packingChecked.contains).length;

    return SoftCard(
      padding: const EdgeInsets.all(16),
      onTap: () => _openTrip(context, plan),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('Coming up · ${plan.daysCount} days'),
          const SizedBox(height: 4),
          Text('${plan.destination} $when', style: _titleStyle),
          const SizedBox(height: 2),
          Text('${fmt.format(start)} – ${fmt.format(end)}', style: _mutedStyle),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (forecast != null)
                MetaPill(
                  icon: Icons.wb_sunny_outlined,
                  label:
                      'Day 1: ${forecast.maxTemp.round()}° / ${forecast.minTemp.round()}° · ${forecast.conditionDescription}',
                  background: AppTheme.sage.withValues(alpha: 0.45),
                  foreground: AppTheme.forest,
                ),
              MetaPill(
                icon: Icons.luggage_outlined,
                label: '$packed / ${items.length} packed',
                background: AppTheme.amber.withValues(alpha: 0.18),
                foreground: AppTheme.amberText,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _openTrip(context, plan),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.forest,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Open plan'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  // The Essentials tab, after the days.
                  onPressed: () =>
                      _openTrip(context, plan, day: plan.days.length),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  child: const Text('Packing & budget'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Being planned
// ---------------------------------------------------------------------------

class _PlanningCard extends StatelessWidget {
  const _PlanningCard({required this.plan});
  final TripPlan plan;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(16),
      onTap: () => _openTrip(context, plan),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Color(0xFFE6F4EA),
            child: Icon(Icons.map_outlined, color: AppTheme.forest),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Label('Keep planning'),
                Text(
                  '${plan.destination} · ${plan.daysCount} days',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const Text(
                  'Add dates to get a countdown, weather and opening hours for each day.',
                  style: _mutedStyle,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.inkMuted),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// No trip yet
// ---------------------------------------------------------------------------

class _PlanTripInvite extends StatelessWidget {
  const _PlanTripInvite();

  @override
  Widget build(BuildContext context) {
    return HeroCard(
      minHeight: 0,
      onTap: () => context.push('/trip-planner'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: AppTheme.amber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Plan a trip anywhere in India',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Day-by-day plans with real places, photos, opening hours and '
            'a budget. Varanasi for 5 days with a friend? Start here.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          AmberPillButton(
            label: 'Plan a trip',
            onPressed: () => context.push('/trip-planner'),
          ),
        ],
      ),
    );
  }
}
