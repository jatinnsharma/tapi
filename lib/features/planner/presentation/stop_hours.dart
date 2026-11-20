import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/opening_hours.dart';

/// Where a stop's hours came from.
enum HoursSource {
  /// OpenStreetMap's own `opening_hours` for the place.
  map,

  /// The AI's typical hours: an estimate.
  ai,
}

/// What the hours mean for when a stop is planned.
enum HoursVerdict {
  /// Open at the planned time.
  open,

  /// Open that day, but not at the planned time of day.
  wrongTime,

  /// Closed all day on the planned day.
  closedThatDay,

  /// Can't tell (no date, or the hours don't cover that day).
  unknown,
}

/// The verdict for [hours] on [day] in [timeSlot] (Morning/Afternoon/
/// Evening).
HoursVerdict verdictFor(OpeningHours? hours, DateTime? day, String timeSlot) {
  if (hours == null || day == null) return HoursVerdict.unknown;
  final ranges = hours.on(day.weekday);
  if (ranges == null) return HoursVerdict.unknown;
  if (ranges.isEmpty) return HoursVerdict.closedThatDay;
  final minute = plannedMinuteFor(timeSlot);
  final when = DateTime(
    day.year,
    day.month,
    day.day,
    minute ~/ 60,
    minute % 60,
  );
  return hours.isOpenAt(when) == true
      ? HoursVerdict.open
      : HoursVerdict.wrongTime;
}

/// A stop's opening hours: the planned day's hours and whether that works,
/// tap for the whole week.
class StopHours extends StatefulWidget {
  const StopHours({
    super.key,
    required this.hours,
    required this.source,
    required this.loading,
    required this.plannedDay,
    required this.timeSlot,
  });

  final OpeningHours? hours;
  final HoursSource? source;
  final bool loading;

  /// The trip day this stop is on, when the trip has dates.
  final DateTime? plannedDay;
  final String timeSlot;

  @override
  State<StopHours> createState() => _StopHoursState();
}

class _StopHoursState extends State<StopHours> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final small = text.bodySmall;
    final hours = widget.hours;
    if (hours == null) {
      return Row(
        children: [
          Icon(Icons.schedule_rounded, size: 16, color: colors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.loading
                  ? 'Checking opening hours…'
                  : 'Opening hours not listed · check locally',
              style: small?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      );
    }

    // The day that matters: the planned day, else today.
    final day = widget.plannedDay ?? DateTime.now();
    final verdict = verdictFor(hours, widget.plannedDay, widget.timeSlot);
    final dayText = hours.describeDay(day.weekday) ?? hours.summary;
    final dayLabel = widget.plannedDay == null
        ? 'Today'
        : DateFormat('EEEE').format(day);

    final (Color color, String? chip) = switch (verdict) {
      HoursVerdict.closedThatDay => (colors.danger, 'Closed that day'),
      HoursVerdict.wrongTime => (
        colors.warning,
        _timingHint(hours, day, widget.timeSlot),
      ),
      HoursVerdict.open => (colors.success, 'Open'),
      HoursVerdict.unknown => (colors.textSecondary, null),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => setState(() => _expanded = !_expanded),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.schedule_rounded, size: 16, color: color),
                  ),
                  const SizedBox(width: 6),
                  // Hours first, the verdict chips wrap under them on small
                  // phones instead of squeezing the hours out.
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '$dayLabel: ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: dayText),
                            ],
                          ),
                          style: small,
                        ),
                        if (chip != null) _Chip(text: chip, color: color),
                        if (widget.source == HoursSource.ai)
                          _Chip(text: 'Approx.', color: colors.textSecondary),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: colors.textSecondary,
                    semanticLabel: _expanded ? 'Hide week' : 'Show week',
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) _week(context, hours, day),
      ],
    );
  }

  /// "Opens 10 AM" / "Closes 5 PM" / "Closed then" for a stop planned at a
  /// time the place isn't open.
  String _timingHint(OpeningHours hours, DateTime day, String slot) {
    final minute = plannedMinuteFor(slot);
    final ranges = hours.on(day.weekday) ?? const [];
    final later = ranges.where((r) => r.start > minute).toList();
    if (later.isNotEmpty) return 'Opens ${formatClock(later.first.start)}';
    final earlier = ranges.where((r) => r.end <= minute).toList();
    if (earlier.isNotEmpty) return 'Closes ${formatClock(earlier.last.end)}';
    return 'Closed then';
  }

  Widget _week(BuildContext context, OpeningHours hours, DateTime highlight) {
    final colors = AppColors.of(context);
    final small = Theme.of(context).textTheme.bodySmall;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hours.understood)
            for (var d = 1; d <= 7; d++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        OpeningHours.weekdayNames[d - 1],
                        style: small?.copyWith(
                          fontWeight: d == highlight.weekday
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        hours.describeDay(d) ?? 'Not listed',
                        style: small?.copyWith(
                          fontWeight: d == highlight.weekday
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: hours.describeDay(d) == 'Closed'
                              ? colors.danger
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              )
          else
            Text(hours.raw, style: small),
          const SizedBox(height: 6),
          Text(
            widget.source == HoursSource.ai
                ? 'Typical hours suggested by AI. Check before you go.'
                : 'From OpenStreetMap. Hours can change on festivals and holidays.',
            style: small?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
    ),
  );
}
