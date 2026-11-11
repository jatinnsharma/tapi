/// Opening hours in OpenStreetMap's `opening_hours` format, for the common
/// cases: "24/7", "Mo-Su 06:00-21:00", "Tu-Su 09:30-17:00; Mo off",
/// "06:00-12:00,16:00-21:00", "sunrise-sunset". Rules later in the text win
/// for the days they name, and days no rule names are closed (as in OSM).
/// Anything else (months, holidays, week numbers…) marks the hours as not
/// fully understood, and the raw text is shown instead.
class OpeningHours {
  OpeningHours._(this.raw, this._days, {required this.understood});

  /// As written, e.g. "Tu-Su 09:30-17:00; Mo off".
  final String raw;

  /// Weekday (1 = Monday … 7 = Sunday) to its open periods; empty = closed.
  final Map<int, List<TimeRange>> _days;

  /// False when the text had parts this parser skipped; then [raw] is the
  /// thing to show, and day-by-day answers are a best guess.
  final bool understood;

  static const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayCodes = ['mo', 'tu', 'we', 'th', 'fr', 'sa', 'su'];

  /// Null for empty text or text with no usable times at all.
  static OpeningHours? parse(String? text) {
    final raw = text?.trim() ?? '';
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower == '24/7' || lower == 'mo-su 00:00-24:00') {
      return OpeningHours._(raw, {
        for (var d = 1; d <= 7; d++) d: const [TimeRange(0, 24 * 60)],
      }, understood: true);
    }

    final days = <int, List<TimeRange>>{};
    var understood = true;
    var anyTimes = false;
    var anyDaySelector = false;

    for (final part in lower.split(';')) {
      var rule = part.trim();
      if (rule.isEmpty) continue;
      // Public/school holidays: can't place them on a weekday; skip quietly.
      if (rule.startsWith('ph') || rule.startsWith('sh')) continue;

      // Day selector at the start, e.g. "mo-fr", "sa,su", "mo-fr,su".
      final dayMatch = RegExp(
        r'^((?:mo|tu|we|th|fr|sa|su)(?:\s*-\s*(?:mo|tu|we|th|fr|sa|su))?(?:\s*,\s*(?:mo|tu|we|th|fr|sa|su)(?:\s*-\s*(?:mo|tu|we|th|fr|sa|su))?)*)\b',
      ).firstMatch(rule);
      Set<int> ruleDays;
      if (dayMatch != null) {
        anyDaySelector = true;
        ruleDays = _parseDays(dayMatch.group(1)!);
        rule = rule.substring(dayMatch.end).trim();
        // "Mo-Fr,PH 10:00-17:00": drop a trailing holiday marker.
        rule = rule.replaceFirst(RegExp(r'^,\s*ph\b'), '').trim();
      } else {
        ruleDays = {1, 2, 3, 4, 5, 6, 7};
      }

      if (rule == 'off' || rule == 'closed') {
        for (final d in ruleDays) {
          days[d] = const [];
        }
        continue;
      }

      final ranges = <TimeRange>[];
      for (final span in rule.split(',')) {
        final range = _parseRange(span.trim());
        if (range == null) {
          understood = false;
        } else {
          ranges.add(range);
        }
      }
      if (ranges.isEmpty) {
        understood = false;
        continue;
      }
      anyTimes = true;
      for (final d in ruleDays) {
        days[d] = ranges;
      }
    }

    if (!anyTimes && days.isEmpty) return null;
    // With day selectors, days no rule mentions are closed.
    if (anyDaySelector) {
      for (var d = 1; d <= 7; d++) {
        days.putIfAbsent(d, () => const []);
      }
    }
    return OpeningHours._(raw, days, understood: understood);
  }

  static Set<int> _parseDays(String selector) {
    final result = <int>{};
    for (final piece in selector.split(',')) {
      final ends = piece.split('-').map((s) => s.trim()).toList();
      final from = _dayCodes.indexOf(ends.first) + 1;
      final to = _dayCodes.indexOf(ends.last) + 1;
      if (from == 0 || to == 0) continue;
      // Wraps around the week: "Sa-Mo".
      for (var d = from; ; d = d % 7 + 1) {
        result.add(d);
        if (d == to) break;
      }
    }
    return result;
  }

  /// "09:30-17:00", "9:30-17:00", "sunrise-sunset", "22:00-02:00".
  static TimeRange? _parseRange(String span) {
    final m = RegExp(
      r'^(sunrise|\d{1,2}:\d{2})\s*-\s*(sunset|\d{1,2}:\d{2})\+?$',
    ).firstMatch(span);
    if (m == null) return null;
    int? minutes(String t) {
      if (t == 'sunrise') return 6 * 60;
      if (t == 'sunset') return 18 * 60 + 30;
      final hm = t.split(':');
      final h = int.tryParse(hm[0]);
      final min = int.tryParse(hm[1]);
      if (h == null || min == null || h > 24 || min > 59) return null;
      return h * 60 + min;
    }

    final start = minutes(m.group(1)!);
    var end = minutes(m.group(2)!);
    if (start == null || end == null) return null;
    if (end <= start) end += 24 * 60; // Past midnight.
    return TimeRange(
      start,
      end,
      bySun: m.group(1) == 'sunrise' || m.group(2) == 'sunset',
    );
  }

  /// Open periods on [weekday] (1 = Monday); empty when closed, null when
  /// the hours don't say.
  List<TimeRange>? on(int weekday) => _days[weekday];

  bool get isAlwaysOpen =>
      _days.length == 7 &&
      _days.values.every(
        (r) => r.length == 1 && r.first.start == 0 && r.first.end >= 24 * 60,
      );

  /// Weekdays it's closed, e.g. {1} for "closed Mondays".
  Set<int> get closedDays => {
    for (final e in _days.entries)
      if (e.value.isEmpty) e.key,
  };

  /// Whether it's open at [when], or null if the hours don't say for that day.
  bool? isOpenAt(DateTime when) {
    final minute = when.hour * 60 + when.minute;
    final today = _days[when.weekday];
    if (today == null) return null;
    if (today.any((r) => minute >= r.start && minute < r.end)) return true;
    // A period from yesterday that runs past midnight.
    final yesterday = _days[(when.weekday + 5) % 7 + 1] ?? const [];
    return yesterday.any((r) => r.end > 24 * 60 && minute < r.end - 24 * 60);
  }

  /// "6 AM – 9 PM" for [weekday], "Closed", "Open 24 hours", or null.
  String? describeDay(int weekday) {
    final ranges = _days[weekday];
    if (ranges == null) return null;
    if (ranges.isEmpty) return 'Closed';
    if (ranges.length == 1 &&
        ranges.first.start == 0 &&
        ranges.first.end >= 24 * 60) {
      return 'Open 24 hours';
    }
    return ranges.map((r) => r.label).join(', ');
  }

  /// One line for the whole week: "6 AM – 9 PM daily", "9:30 AM – 5 PM ·
  /// closed Mon", or the raw text when it isn't simple.
  String get summary {
    if (isAlwaysOpen) return 'Open 24 hours';
    if (!understood) return raw;
    final open = {
      for (final e in _days.entries)
        if (e.value.isNotEmpty) e.key: describeDay(e.key)!,
    };
    final distinct = open.values.toSet();
    final closed = closedDays.toList()..sort();
    if (distinct.length == 1) {
      final hours = distinct.single;
      if (closed.isEmpty) return '$hours daily';
      return '$hours · closed ${closed.map((d) => weekdayNames[d - 1]).join(', ')}';
    }
    return raw;
  }
}

/// An open period in minutes from midnight; [end] may pass 24:00.
class TimeRange {
  const TimeRange(this.start, this.end, {this.bySun = false});

  final int start;
  final int end;

  /// From sunrise or until sunset: the times are rough.
  final bool bySun;

  String get label {
    if (bySun && start == 6 * 60 && end == 18 * 60 + 30) {
      return 'Sunrise – sunset';
    }
    return '${formatClock(start)} – ${formatClock(end)}';
  }

  @override
  bool operator ==(Object other) =>
      other is TimeRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// "6 AM", "9:30 PM", "12 PM", "12 AM" for minutes from midnight.
String formatClock(int minutes) {
  final m = minutes % (24 * 60);
  final h24 = m ~/ 60;
  final min = m % 60;
  final suffix = h24 < 12 ? 'AM' : 'PM';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return min == 0
      ? '$h12 $suffix'
      : '$h12:${min.toString().padLeft(2, '0')} $suffix';
}

/// When a stop in [timeSlot] on a trip day is roughly planned for.
int plannedMinuteFor(String timeSlot) => switch (timeSlot) {
  'Morning' => 9 * 60,
  'Afternoon' => 14 * 60,
  _ => 18 * 60,
};
