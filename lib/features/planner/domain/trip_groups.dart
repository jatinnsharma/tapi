import 'trip_plan.dart';

/// The sections of the Trips tab, in the order they're shown.
enum TripGroup {
  now('Happening now'),
  upcoming('Upcoming'),
  undated('Not dated yet'),
  past('Past');

  const TripGroup(this.label);
  final String label;
}

/// The trip's first and last day (dates only), or null without a start
/// date.
({DateTime start, DateTime end})? tripDates(TripPlan plan) {
  final start = plan.startDate;
  if (start == null) return null;
  final first = DateTime(start.year, start.month, start.day);
  final days = plan.days.isEmpty ? plan.daysCount : plan.days.length;
  return (
    start: first,
    end: first.add(Duration(days: days < 1 ? 0 : days - 1)),
  );
}

TripGroup groupOf(TripPlan plan, DateTime now) {
  final dates = tripDates(plan);
  if (dates == null) return TripGroup.undated;
  final today = DateTime(now.year, now.month, now.day);
  if (today.isBefore(dates.start)) return TripGroup.upcoming;
  if (today.isAfter(dates.end)) return TripGroup.past;
  return TripGroup.now;
}

/// Trips by section: soonest first for now/upcoming, most recent first for
/// past, newest first when undated. Empty sections are left out.
Map<TripGroup, List<TripPlan>> groupTrips(List<TripPlan> trips, DateTime now) {
  final groups = {for (final g in TripGroup.values) g: <TripPlan>[]};
  for (final t in trips) {
    groups[groupOf(t, now)]!.add(t);
  }
  int byStart(TripPlan a, TripPlan b) =>
      tripDates(a)!.start.compareTo(tripDates(b)!.start);
  groups[TripGroup.now]!.sort(byStart);
  groups[TripGroup.upcoming]!.sort(byStart);
  groups[TripGroup.past]!.sort((a, b) => byStart(b, a));
  groups[TripGroup.undated]!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return {
    for (final e in groups.entries)
      if (e.value.isNotEmpty) e.key: e.value,
  };
}

/// Stops ticked off across the whole trip.
int completedStops(TripPlan plan) => plan.days.fold(
  0,
  (sum, d) => sum + d.stops.where((s) => s.isCompleted).length,
);
