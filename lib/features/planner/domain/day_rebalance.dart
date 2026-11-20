import 'package:latlong2/latlong.dart';

import '../../locations/domain/location.dart';
import '../../weather/domain/weather_advisory.dart';
import '../../weather/domain/weather_model.dart';
import 'trip_plan.dart';

/// Why the user wants the rest of the day changed.
enum RebalanceReason {
  runningLate('Running late', 'Keep what still fits before evening'),
  tired('Feeling tired', 'Shorter visits, at most 2 more stops'),
  placeClosed('A place is closed', 'Drop it and re-route the rest'),
  rain('Caught in rain', 'Drop trails, waterfalls and viewpoints');

  const RebalanceReason(this.label, this.description);
  final String label;
  final String description;
}

/// The day ends at this hour: later stops are dropped.
const rebalanceDayEndHour = 21;

/// Average door-to-door speed between stops in a town (walking, autos and
/// traffic together), and the extra for roads not being straight.
const rebalanceTravelKmh = 15.0;
const rebalanceDetourFactor = 1.3;

/// Shortest hop counted, for parking, finding the entrance and so on.
const rebalanceMinTravelMinutes = 10;

/// Visits are this much shorter when the user is tired.
const tiredVisitFactor = 0.75;

/// Most stops kept when the user is tired.
const tiredMaxStops = 2;

/// Why a stop was left out.
enum DropReason { noTime, closed, weather, tired, userClosed }

class DroppedStop {
  const DroppedStop(this.stop, this.reason);

  final TripStop stop;
  final DropReason reason;

  String get explanation => switch (reason) {
    DropReason.noTime => 'No time left today',
    DropReason.closed => 'Closed when you would get there',
    DropReason.weather => 'Not safe in the rain',
    DropReason.tired => 'Saved for another day',
    DropReason.userClosed => 'You said it is closed',
  };
}

class RebalanceResult {
  const RebalanceResult({
    required this.kept,
    required this.dropped,
    required this.finishAt,
  });

  /// The stops still planned, in the new order, with new visit lengths.
  final List<TripStop> kept;
  final List<DroppedStop> dropped;

  /// When the last kept stop should end.
  final DateTime finishAt;

  bool get changesNothing => dropped.isEmpty && kept.isEmpty;
}

/// Minutes to get from [from] to [to] by the rules above.
int travelMinutesBetween(LatLng from, LatLng to) {
  const distance = Distance();
  final km = distance(from, to) / 1000 * rebalanceDetourFactor;
  final minutes = (km / rebalanceTravelKmh * 60).round();
  return minutes < rebalanceMinTravelMinutes
      ? rebalanceMinTravelMinutes
      : minutes;
}

/// Re-plans the rest of a day from where the user is ([from]; null means
/// the first pending stop) at [now].
///
/// Pending stops are visited nearest-next. A stop is dropped when the
/// [reason] rules it out, when it would be closed on arrival ([isOpenAt]
/// says `false`; `null` means unknown and keeps it), or when it would end
/// after [rebalanceDayEndHour]. Dropping one doesn't stop the rest: a nearer
/// or shorter stop may still fit.
RebalanceResult rebalanceDay({
  required List<TripStop> pending,
  required DateTime now,
  required RebalanceReason reason,
  LatLng? from,
  Set<String> closedStopIds = const {},
  bool? Function(TripStop stop, DateTime at)? isOpenAt,
  LocationCategory Function(TripStop stop)? categoryOf,
}) {
  final dropped = <DroppedStop>[];
  final candidates = <TripStop>[];

  final rainAdvisory = reason == RebalanceReason.rain
      ? WeatherAdvisory.from(
          const WeatherData(
            temperature: 20,
            windSpeed: 0,
            weatherCode: 65, // Heavy rain.
            isDay: true,
          ),
        )
      : null;

  for (final stop in pending) {
    if (closedStopIds.contains(stop.id)) {
      dropped.add(DroppedStop(stop, DropReason.userClosed));
    } else if (rainAdvisory != null &&
        categoryOf != null &&
        !rainAdvisory.suits(categoryOf(stop))) {
      dropped.add(DroppedStop(stop, DropReason.weather));
    } else {
      candidates.add(stop);
    }
  }

  final dayEnd = DateTime(now.year, now.month, now.day, rebalanceDayEndHour);
  final kept = <TripStop>[];
  var clock = now;
  var here = from ?? (candidates.isEmpty ? null : candidates.first.coordinates);

  while (candidates.isNotEmpty) {
    // Nearest next stop from where the user will be.
    candidates.sort(
      (a, b) => travelMinutesBetween(
        here!,
        a.coordinates,
      ).compareTo(travelMinutesBetween(here, b.coordinates)),
    );
    final stop = candidates.removeAt(0);

    if (reason == RebalanceReason.tired && kept.length >= tiredMaxStops) {
      dropped.add(DroppedStop(stop, DropReason.tired));
      continue;
    }

    final visit = reason == RebalanceReason.tired
        ? (stop.durationMinutes * tiredVisitFactor).round()
        : stop.durationMinutes;
    final arrive = clock.add(
      Duration(minutes: travelMinutesBetween(here!, stop.coordinates)),
    );
    final leave = arrive.add(Duration(minutes: visit));

    if (isOpenAt?.call(stop, arrive) == false) {
      dropped.add(DroppedStop(stop, DropReason.closed));
      continue;
    }
    if (leave.isAfter(dayEnd)) {
      dropped.add(DroppedStop(stop, DropReason.noTime));
      continue;
    }

    kept.add(stop.copyWith(durationMinutes: visit));
    clock = leave;
    here = stop.coordinates;
  }

  return RebalanceResult(kept: kept, dropped: dropped, finishAt: clock);
}

/// [day] with its pending stops replaced by [result]: done stops stay first,
/// in their order; dropped stops leave the day.
TripDayPlan applyRebalance(TripDayPlan day, RebalanceResult result) =>
    day.copyWith(
      stops: [
        for (final s in day.stops)
          if (s.isCompleted) s,
        ...result.kept,
      ],
    );
