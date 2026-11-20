import '../../planner/domain/trip_plan.dart';
import 'food.dart';

/// How long a snack stop is planned for.
const snackStopMinutes = 30;

/// The planner's time-of-day slot for [now].
String timeSlotAt(DateTime now) => now.hour < 12
    ? 'Morning'
    : now.hour < 17
    ? 'Afternoon'
    : 'Evening';

/// [plan] with [spot] added to day [dayIndex] as the next stop (after the
/// ones already done). Adding the same spot twice changes nothing.
TripPlan withSnackStop(
  TripPlan plan,
  int dayIndex,
  FoodSpot spot, {
  required DateTime now,
}) {
  final day = plan.days[dayIndex];
  final id = 'snack-${spot.id}';
  if (day.stops.any((s) => s.id == id)) return plan;

  final stop = TripStop(
    id: id,
    placeName: spot.name,
    description: [spot.kind, ?spot.cuisine].join(' · '),
    timeSlot: timeSlotAt(now),
    durationMinutes: snackStopMinutes,
    latitude: spot.latitude,
    longitude: spot.longitude,
    category: 'food',
    placeId: spot.id,
    openingHours: spot.openingHours,
  );
  final firstPending = day.stops.indexWhere((s) => !s.isCompleted);
  final at = firstPending < 0 ? day.stops.length : firstPending;
  final days = [...plan.days];
  days[dayIndex] = day.copyWith(stops: [...day.stops]..insert(at, stop));
  return plan.copyWith(days: days, updatedAt: now);
}
