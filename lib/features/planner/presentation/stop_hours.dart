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

  static const _muted = TextStyle(fontSize: 12.5, color: AppTheme.inkMuted);

  @override
  Widget build(BuildContext context) {
    final hours = widget.hours;
    if (hours == null) {
      return Row(
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 16,
            color: AppTheme.inkMuted.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Text(
            widget.loading
                ? 'Checking opening hours…'
                : 'Opening hours not listed · check locally',
            style: _muted,
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
      HoursVerdict.closedThatDay => (
        const Color(0xFFD93025),
        'Closed that day',
      ),
      HoursVerdict.wrongTime => (
        AppTheme.amberText,
        _timingHint(hours, day, widget.timeSlot),
      ),
      HoursVerdict.open => (const Color(0xFF188038), 'Open'),
      HoursVerdict.unknown => (AppTheme.inkMuted, null),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$dayLabel: ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: dayText),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.ink),
                  ),
                ),
                if (chip != null) ...[
                  const SizedBox(width: 6),
                  _Chip(text: chip, color: color),
                ],
                if (widget.source == HoursSource.ai) ...[
                  const SizedBox(width: 6),
                  const _Chip(text: 'Approx.', color: AppTheme.inkMuted),
                ],
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppTheme.inkMuted,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) _week(hours, day),
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

  Widget _week(OpeningHours hours, DateTime highlight) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F7),
        borderRadius: BorderRadius.circular(12),
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
                      width: 44,
                      child: Text(
                        OpeningHours.weekdayNames[d - 1],
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: d == highlight.weekday
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        hours.describeDay(d) ?? 'Not listed',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: d == highlight.weekday
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: hours.describeDay(d) == 'Closed'
                              ? const Color(0xFFD93025)
                              : AppTheme.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              )
          else
            Text(hours.raw, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 6),
          Text(
            widget.source == HoursSource.ai
                ? 'Typical hours suggested by AI. Check before you go.'
                : 'From OpenStreetMap. Hours can change on festivals and holidays.',
            style: const TextStyle(fontSize: 11, color: AppTheme.inkMuted),
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
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  );
}
