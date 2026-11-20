import '../application/reminder_settings_service.dart';

/// One repeating reminder.
class ReminderSpec {
  const ReminderSpec({
    required this.id,
    required this.title,
    required this.body,
    required this.hour,
    this.minute = 0,
    this.weekday,
  });

  /// Notification id; stable, so re-scheduling replaces it.
  final int id;
  final String title;
  final String body;
  final int hour;
  final int minute;

  /// [DateTime.monday]..[DateTime.sunday] for a weekly reminder; null for
  /// every day.
  final int? weekday;
}

const streakReminder = ReminderSpec(
  id: 1,
  title: 'Keep your streak alive',
  body: 'A short walk to a nearby place counts. Open Tabi to find one.',
  hour: 19,
);

const challengeReminder = ReminderSpec(
  id: 2,
  title: "Today's challenge is ready",
  body: 'See what it is and earn bonus XP.',
  hour: 9,
);

const socialReminder = ReminderSpec(
  id: 3,
  title: 'See where your friends explored',
  body: 'Catch up on their trips this week, and plan your next one.',
  hour: 11,
  weekday: DateTime.sunday,
);

/// Every reminder id the app uses, for cancelling.
const allReminderIds = [1, 2, 3];

/// The reminders [settings] turns on.
List<ReminderSpec> remindersFor(ReminderSettings settings) => [
  if (settings.streakReminders) streakReminder,
  if (settings.challengeReminders) challengeReminder,
  if (settings.socialReminders) socialReminder,
];

/// The next time [spec] should fire after [now] (strictly later), in
/// [now]'s time zone.
DateTime nextFireTime(ReminderSpec spec, DateTime now) {
  var next = DateTime(now.year, now.month, now.day, spec.hour, spec.minute);
  final weekday = spec.weekday;
  if (weekday != null) {
    next = next.add(Duration(days: (weekday - next.weekday) % 7));
    if (!next.isAfter(now)) next = next.add(const Duration(days: 7));
  } else if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }
  return next;
}
