import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/journal/domain/calendar_month.dart';
import 'package:real_world_exploration/features/memories/domain/memory_model.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';

AdventureSession _trip(
  String id,
  DateTime at, {
  AdventureStatus? status,
  double trek = 0,
}) => AdventureSession(
  id: id,
  title: id,
  startedAt: at,
  status: status ?? AdventureStatus.completed,
  trekMeters: trek,
);

Memory _memory(String id, DateTime at, {MemoryType type = MemoryType.photo}) =>
    Memory(id: id, type: type, filePath: '/m/$id.jpg', timestamp: at);

void main() {
  group('Month grid', () {
    test('October 2026 starts on a Thursday', () {
      final cells = monthGrid(DateTime(2026, 10));
      expect(cells.take(3), [null, null, null]); // Mon, Tue, Wed blank
      expect(cells[3], DateTime(2026, 10, 1));
      expect(cells.whereType<DateTime>(), hasLength(31));
      expect(cells.length % 7, 0);
    });

    test('a month starting on Monday has no leading blanks', () {
      final cells = monthGrid(DateTime(2026, 6)); // 1 June 2026 is a Monday
      expect(cells.first, DateTime(2026, 6, 1));
    });

    test('February in a leap year has 29 days', () {
      expect(monthGrid(DateTime(2028, 2)).whereType<DateTime>(), hasLength(29));
      expect(monthGrid(DateTime(2027, 2)).whereType<DateTime>(), hasLength(28));
    });
  });

  group('Grouping by day', () {
    test('trips and memories land on their own local day', () {
      final days = groupByDay(
        [
          _trip('morning', DateTime(2026, 10, 15, 7)),
          _trip('evening', DateTime(2026, 10, 15, 19)),
          _trip('next', DateTime(2026, 10, 16, 6)),
        ],
        [
          _memory('a', DateTime(2026, 10, 15, 8)),
          _memory('b', DateTime(2026, 10, 14, 23, 59)),
        ],
      );
      final day15 = days[DateTime(2026, 10, 15)]!;
      expect(day15.trips.map((t) => t.id), ['morning', 'evening']);
      expect(day15.memories.map((m) => m.id), ['a']);
      expect(days[DateTime(2026, 10, 14)]!.trips, isEmpty);
      expect(days[DateTime(2026, 10, 16)]!.trips.single.id, 'next');
    });

    test('a memory saved in UTC still lands on the local day', () {
      final local = DateTime(2026, 10, 15, 12);
      final days = groupByDay([], [_memory('u', local.toUtc())]);
      expect(days.keys.single, DateTime(2026, 10, 15));
    });

    test('discarded trips are left out', () {
      final days = groupByDay([
        _trip(
          'gone',
          DateTime(2026, 10, 15, 7),
          status: AdventureStatus.discarded,
        ),
      ], []);
      expect(days, isEmpty);
    });

    test('the cover is the first photo, not a video or voice note', () {
      final days = groupByDay([], [
        _memory('v', DateTime(2026, 10, 15, 8), type: MemoryType.video),
        _memory('n', DateTime(2026, 10, 15, 9), type: MemoryType.voiceNote),
        _memory('p', DateTime(2026, 10, 15, 10)),
      ]);
      expect(days.values.single.coverPhoto!.id, 'p');
    });
  });

  test('month totals add up', () {
    final days = groupByDay(
      [
        _trip('a', DateTime(2026, 10, 2, 7), trek: 1200),
        _trip('b', DateTime(2026, 10, 9, 7), trek: 800),
      ],
      [
        _memory('m', DateTime(2026, 10, 9, 8)),
        _memory('n', DateTime(2026, 10, 20)),
      ],
    );
    final totals = MonthTotals.of(days);
    expect(totals.trips, 2);
    expect(totals.trekMeters, 2000);
    expect(totals.memories, 2);
    expect(totals.activeDays, 3);
  });
}
