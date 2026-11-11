import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../locations/domain/location.dart';
import '../../tracking/data/adventure_repository.dart';
import '../data/itinerary_repair.dart';
import '../domain/trip_plan.dart';

/// The place id a trip to [stop] is recorded under.
String placeIdOfStop(TripStop stop) =>
    stop.placeId ?? ItineraryRepairer.stableIdFor(stop);

/// Starts a tracked trip to a stop of [plan]. Its place id goes with it, so
/// arriving (confirmed with the live photo, as for any place) counts as
/// visiting that place and pays its XP. Completes once the user is back from
/// the trip screen, with whether the stop was reached.
Future<bool> goToStop(
  BuildContext context,
  WidgetRef ref,
  TripPlan plan,
  int dayIndex,
  int stopIndex,
) async {
  final day = plan.days[dayIndex];
  final stop = day.stops[stopIndex];
  final placeId = placeIdOfStop(stop);

  await context.push(
    Uri(
      path: '/tracking',
      queryParameters: {
        'title':
            '${plan.destination} · Day ${day.dayNumber}, stop ${stopIndex + 1}',
        'destId': placeId,
        'destName': stop.placeName,
        'destLat': '${stop.latitude}',
        'destLng': '${stop.longitude}',
        'destXp': '${stop.xpReward ?? TripStop.defaultXp}',
        'autostart': '1',
      },
    ).toString(),
  );
  if (!context.mounted) return false;
  ref.invalidate(visitedPlaceIdsProvider);
  final visited = await ref.read(visitedPlaceIdsProvider.future);
  return visited.contains(placeId);
}

/// [plan] with the stop whose id is [stopId] marked done (or not). The stop
/// is found by id, since the plan may have changed (a friend's edit).
TripPlan withStopCompleted(TripPlan plan, String stopId, bool done) {
  return plan.copyWith(
    days: [
      for (final day in plan.days)
        day.stops.any((s) => s.id == stopId)
            ? day.copyWith(
                stops: [
                  for (final s in day.stops)
                    s.id == stopId ? s.copyWith(isCompleted: done) : s,
                ],
              )
            : day,
    ],
    updatedAt: DateTime.now(),
  );
}

/// A stop as a place, for its photos: its real place id (a `wiki-` id finds
/// the article's photos), its position (for photos taken there) and its
/// category (for the artwork shown when there are none). [destination]'s
/// main name keeps a search by name to photos from that town.
ExploreLocation stopAsPlace(TripStop stop, String destination) =>
    ExploreLocation(
      id: placeIdOfStop(stop),
      name: stop.placeName,
      category: categoryOfStop(stop.category),
      description: stop.description,
      latitude: stop.latitude,
      longitude: stop.longitude,
      city: destination.split(RegExp(r'[&(,]')).first.trim(),
    );

/// The AI writes categories freely ("heritage / spiritual", "food").
LocationCategory categoryOfStop(String raw) {
  final text = raw.toLowerCase();
  for (final c in LocationCategory.values) {
    if (text.contains(c.name.toLowerCase())) return c;
  }
  if (text.contains('spiritual') ||
      text.contains('temple') ||
      text.contains('ghat')) {
    return LocationCategory.heritage;
  }
  if (text.contains('market') || text.contains('bazaar')) {
    return LocationCategory.food;
  }
  if (text.contains('park') || text.contains('garden')) {
    return LocationCategory.nature;
  }
  return LocationCategory.city;
}
