import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../memories/data/memory_repository.dart';
import '../../memories/presentation/memory_widgets.dart';
import '../../tracking/data/adventure_repository.dart';
import '../../tracking/domain/adventure_session.dart';
import '../../tracking/presentation/journey_trek_breakdown.dart';
import '../domain/calendar_month.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];
const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];

/// Everything that happened in one month, by local day.
final calendarMonthProvider = FutureProvider.autoDispose
    .family<Map<DateTime, DayActivity>, DateTime>((ref, month) async {
      final from = monthOf(month);
      final to = DateTime(from.year, from.month + 1);
      // Both repositories before any await: the provider may be disposed
      // while it waits (the screen closed, or the month changed).
      final adventures = ref.watch(adventureRepositoryProvider);
      final memoryRepository = ref.watch(memoryRepositoryProvider);
      final trips = await adventures.getAdventuresBetween(from, to);
      final memories = await memoryRepository.getBetween(from, to);
      return groupByDay(trips, memories)
        ..removeWhere((day, _) => day.isBefore(from) || !day.isBefore(to));
    });

/// A month at a glance: each day shows its trips and memories (a day with a
/// photo shows the photo). Tap a day to open its trips and memories.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.initialMonth, this.today});

  final DateTime? initialMonth;

  /// For tests; defaults to now.
  final DateTime? today;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month = monthOf(
    widget.initialMonth ?? widget.today ?? DateTime.now(),
  );

  DateTime get _today => dayOf(widget.today ?? DateTime.now());

  bool get _isCurrentMonth => _month == monthOf(_today);

  void _go(int months) {
    final next = DateTime(_month.year, _month.month + months);
    if (next.isAfter(monthOf(_today))) return; // nothing in the future
    setState(() => _month = next);
  }

  @override
  Widget build(BuildContext context) {
    final daysAsync = ref.watch(calendarMonthProvider(_month));
    final days = daysAsync.value ?? const <DateTime, DayActivity>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          if (!_isCurrentMonth)
            TextButton(
              onPressed: () => setState(() => _month = monthOf(_today)),
              child: const Text('Today'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        // Swipe left for the next month, right for the previous one.
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -250) _go(1);
          if (v > 250) _go(-1);
        },
        child: ListView(
          padding: AppSpacing.page,
          children: [
            _MonthHeader(
              month: _month,
              onPrevious: () => _go(-1),
              onNext: _isCurrentMonth ? null : () => _go(1),
            ),
            const SizedBox(height: 14),
            FadeSlideIn(child: _MonthSummary(totals: MonthTotals.of(days))),
            const SizedBox(height: 16),
            SoftCard(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
              child: Column(
                children: [
                  const _WeekdayRow(),
                  const SizedBox(height: 8),
                  if (daysAsync.isLoading && daysAsync.value == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    _MonthGrid(
                      month: _month,
                      days: days,
                      today: _today,
                      onTapDay: (day) => showDayDetails(
                        context,
                        day: day,
                        activity: days[day] ?? const DayActivity(),
                        onChanged: () =>
                            ref.invalidate(calendarMonthProvider(_month)),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const _Legend(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Tap a day to see its trips and memories',
                style: TextStyle(color: AppTheme.inkMuted, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        RoundIconButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous month',
          onPressed: onPrevious,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                _monthNames[month.month - 1],
                key: const ValueKey('month-name'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppTheme.ink,
                ),
              ),
              Text(
                '${month.year}',
                style: const TextStyle(
                  color: AppTheme.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Opacity(
          opacity: onNext == null ? 0.35 : 1,
          child: RoundIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next month',
            onPressed: onNext,
          ),
        ),
      ],
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.totals});

  final MonthTotals totals;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return HeroCard(
      key: const ValueKey('month-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      radius: 26,
      child: Row(
        children: [
          stat('${totals.trips}', 'Trips'),
          stat(formatTripDistance(totals.trekMeters), 'Trekked'),
          stat('${totals.memories}', 'Memories'),
          stat('${totals.activeDays}', 'Active days'),
        ],
      ),
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                _weekdayNames[i].substring(0, 1),
                semanticsLabel: _weekdayNames[i],
                style: TextStyle(
                  color: i >= 5 ? AppTheme.amberText : AppTheme.inkMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.days,
    required this.today,
    required this.onTapDay,
  });

  final DateTime month;
  final Map<DateTime, DayActivity> days;
  final DateTime today;
  final ValueChanged<DateTime> onTapDay;

  @override
  Widget build(BuildContext context) {
    final cells = monthGrid(month);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: cells.length,
      itemBuilder: (context, i) {
        final day = cells[i];
        if (day == null) return const SizedBox.shrink();
        return _DayCell(
          day: day,
          activity: days[day],
          isToday: day == today,
          isFuture: day.isAfter(today),
          onTap: () => onTapDay(day),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.activity,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  final DateTime day;
  final DayActivity? activity;
  final bool isToday;
  final bool isFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final cover = a?.coverPhoto;
    final hasTrips = a != null && a.trips.isNotEmpty;
    final hasMemories = a != null && a.memories.isNotEmpty;
    final onPhoto = cover != null;

    final label = [
      '${day.day} ${_monthNames[day.month - 1]}',
      if (hasTrips) '${a.trips.length} trip${a.trips.length == 1 ? '' : 's'}',
      if (hasMemories)
        '${a.memories.length} memor${a.memories.length == 1 ? 'y' : 'ies'}',
    ].join(', ');

    return Semantics(
      button: !isFuture,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: isFuture ? 0.35 : 1,
        child: PressableScale(
          child: GestureDetector(
            key: ValueKey('day-${day.day}'),
            onTap: isFuture ? null : onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: hasTrips
                    ? AppTheme.emerald.withValues(alpha: 0.16)
                    : AppTheme.forest.withValues(alpha: 0.035),
                border: isToday
                    ? Border.all(color: AppTheme.amber, width: 2.2)
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null) ...[
                    Image.file(
                      File(cover.filePath),
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66000000), Color(0x22000000)],
                        ),
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      children: [
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            color: onPhoto
                                ? Colors.white
                                : (hasTrips ? AppTheme.forest : AppTheme.ink),
                            fontWeight: hasTrips || isToday || onPhoto
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hasTrips)
                              for (
                                var i = 0;
                                i < a.trips.length.clamp(1, 3);
                                i++
                              )
                                const _Dot(color: AppTheme.emerald),
                            if (hasMemories) const _Dot(color: AppTheme.amber),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 0.8),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(color: AppTheme.inkMuted, fontSize: 12),
        ),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 6,
      children: [
        item(AppTheme.emerald, 'Trip'),
        item(AppTheme.amber, 'Memory'),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AppTheme.amber, width: 2),
              ),
            ),
            const SizedBox(width: 5),
            const Text(
              'Today',
              style: TextStyle(color: AppTheme.inkMuted, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

/// The day's trips (with journey and trek) and memories, in a sheet.
Future<void> showDayDetails(
  BuildContext context, {
  required DateTime day,
  required DayActivity activity,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: activity.isEmpty ? 0.4 : 0.8,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scroll) => DayDetails(
        day: day,
        activity: activity,
        scrollController: scroll,
        onChanged: onChanged,
      ),
    ),
  );
}

class DayDetails extends StatelessWidget {
  const DayDetails({
    super.key,
    required this.day,
    required this.activity,
    this.scrollController,
    this.onChanged,
  });

  final DateTime day;
  final DayActivity activity;
  final ScrollController? scrollController;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Text(
          _weekdayNames[day.weekday - 1],
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: AppTheme.ink,
          ),
        ),
        Text(
          '${day.day} ${_monthNames[day.month - 1]} ${day.year}',
          style: const TextStyle(
            color: AppTheme.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        if (activity.isEmpty)
          const EmptyStateCard(
            icon: Icons.event_busy_rounded,
            title: 'Nothing on this day',
            message: 'Trips you take and memories you save will show up here.',
          ),
        if (activity.trips.isNotEmpty) ...[
          _SectionTitle(
            icon: Icons.hiking_rounded,
            text: activity.trips.length == 1
                ? '1 trip'
                : '${activity.trips.length} trips',
          ),
          const SizedBox(height: 10),
          for (final trip in activity.trips) ...[
            _TripOfDay(trip: trip),
            const SizedBox(height: 12),
          ],
        ],
        if (activity.memories.isNotEmpty) ...[
          const SizedBox(height: 6),
          _SectionTitle(
            icon: Icons.photo_library_rounded,
            text: activity.memories.length == 1
                ? '1 memory'
                : '${activity.memories.length} memories',
          ),
          const SizedBox(height: 10),
          MemoriesGrid(memories: activity.memories, onChanged: onChanged),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: AppTheme.primaryGreen, size: 20),
      const SizedBox(width: 8),
      Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppTheme.ink,
        ),
      ),
    ],
  );
}

class _TripOfDay extends StatelessWidget {
  const _TripOfDay({required this.trip});
  final AdventureSession trip;

  String _time(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ended = trip.endedAt;
    final notCounted = trip.status == AdventureStatus.unverified;
    final ongoing =
        trip.status == AdventureStatus.active ||
        trip.status == AdventureStatus.paused;

    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trip.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              if (notCounted || ongoing)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (notCounted ? Colors.orange : AppTheme.emerald)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    notCounted ? 'Not counted' : 'In progress',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: notCounted ? AppTheme.amberText : AppTheme.forest,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            ended == null
                ? 'Started ${_time(trip.startedAt)}'
                : '${_time(trip.startedAt)} – ${_time(ended)}',
            style: const TextStyle(color: AppTheme.inkMuted),
          ),
          const SizedBox(height: 12),
          JourneyTrekBreakdown.ofSession(trip),
          const SizedBox(height: 10),
          Row(
            children: [
              MetaPill(
                icon: Icons.bolt_rounded,
                label: '+${trip.xpEarned} XP',
                background: AppTheme.amber,
                foreground: AppTheme.ink,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/journal/${trip.id}');
                      },
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Trip details'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
