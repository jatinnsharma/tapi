import '../../memories/domain/memory_model.dart';
import '../../tracking/domain/adventure_session.dart';

/// Midnight (local time) of the day [t] falls on: the key for a calendar day.
DateTime dayOf(DateTime t) {
  final local = t.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// The first day of [t]'s month.
DateTime monthOf(DateTime t) => DateTime(t.year, t.month);

/// The cells of a month grid, weeks starting on Monday: `null` for the blank
/// cells before the 1st and after the last day, so the length is a multiple
/// of 7.
List<DateTime?> monthGrid(DateTime month) {
  final first = DateTime(month.year, month.month);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final leading = first.weekday - DateTime.monday; // 0..6
  final cells = <DateTime?>[
    for (var i = 0; i < leading; i++) null,
    for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}

/// What happened on one day.
class DayActivity {
  const DayActivity({this.trips = const [], this.memories = const []});

  final List<AdventureSession> trips;
  final List<Memory> memories;

  bool get isEmpty => trips.isEmpty && memories.isEmpty;

  /// A photo to show on the day's cell, if there is one.
  Memory? get coverPhoto {
    for (final m in memories) {
      if (m.type == MemoryType.photo) return m;
    }
    return null;
  }

  double get trekMeters => trips.fold(0.0, (sum, t) => sum + t.trekMeters);
}

/// Trips and memories grouped by the local day they started or were made.
/// Discarded trips are left out. Trips come oldest first, memories in time
/// order.
Map<DateTime, DayActivity> groupByDay(
  Iterable<AdventureSession> trips,
  Iterable<Memory> memories,
) {
  final tripsByDay = <DateTime, List<AdventureSession>>{};
  for (final t in trips) {
    if (t.status == AdventureStatus.discarded) continue;
    tripsByDay.putIfAbsent(dayOf(t.startedAt), () => []).add(t);
  }
  final memoriesByDay = <DateTime, List<Memory>>{};
  for (final m in memories) {
    memoriesByDay.putIfAbsent(dayOf(m.timestamp), () => []).add(m);
  }
  return {
    for (final day in {...tripsByDay.keys, ...memoriesByDay.keys})
      day: DayActivity(
        trips: (tripsByDay[day] ?? [])
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt)),
        memories: (memoriesByDay[day] ?? [])
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
      ),
  };
}

/// Totals for a month's summary strip.
class MonthTotals {
  const MonthTotals({
    required this.trips,
    required this.trekMeters,
    required this.memories,
    required this.activeDays,
  });

  factory MonthTotals.of(Map<DateTime, DayActivity> days) {
    var trips = 0;
    var meters = 0.0;
    var memories = 0;
    for (final d in days.values) {
      trips += d.trips.length;
      meters += d.trekMeters;
      memories += d.memories.length;
    }
    return MonthTotals(
      trips: trips,
      trekMeters: meters,
      memories: memories,
      activeDays: days.values.where((d) => !d.isEmpty).length,
    );
  }

  final int trips;
  final double trekMeters;
  final int memories;
  final int activeDays;
}
