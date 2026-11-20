import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/notifications/application/reminder_scheduler.dart';
import 'package:real_world_exploration/features/notifications/application/reminder_settings_service.dart';
import 'package:real_world_exploration/features/notifications/domain/reminder_schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

class _FakeScheduler implements ReminderScheduler {
  _FakeScheduler({this.allow = true});

  bool allow;
  int permissionAsks = 0;
  List<List<int>> applied = [];

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return allow;
  }

  @override
  Future<void> apply(List<ReminderSpec> specs) async {
    applied.add([for (final s in specs) s.id]);
  }
}

void main() {
  group('nextFireTime', () {
    test('daily: later today, else tomorrow', () {
      final morning = DateTime(2026, 11, 17, 8);
      expect(nextFireTime(streakReminder, morning), DateTime(2026, 11, 17, 19));
      final night = DateTime(2026, 11, 17, 20);
      expect(nextFireTime(streakReminder, night), DateTime(2026, 11, 18, 19));
      // Exactly at the time: the next one, not now.
      final exactly = DateTime(2026, 11, 17, 19);
      expect(nextFireTime(streakReminder, exactly), DateTime(2026, 11, 18, 19));
    });

    test('weekly: the coming Sunday at 11', () {
      final tuesday = DateTime(2026, 11, 17, 12); // A Tuesday.
      expect(tuesday.weekday, DateTime.tuesday);
      expect(nextFireTime(socialReminder, tuesday), DateTime(2026, 11, 22, 11));
      final sundayAfter = DateTime(2026, 11, 22, 12);
      expect(
        nextFireTime(socialReminder, sundayAfter),
        DateTime(2026, 11, 29, 11),
      );
      final sundayBefore = DateTime(2026, 11, 22, 9);
      expect(
        nextFireTime(socialReminder, sundayBefore),
        DateTime(2026, 11, 22, 11),
      );
    });
  });

  test('which reminders each switch turns on', () {
    expect(remindersFor(ReminderSettingsNotifier.off), isEmpty);
    expect(
      remindersFor(
        const ReminderSettings(
          streakReminders: true,
          challengeReminders: false,
          socialReminders: true,
        ),
      ).map((r) => r.id),
      [streakReminder.id, socialReminder.id],
    );
    expect(allReminderIds.toSet(), {
      streakReminder.id,
      challengeReminder.id,
      socialReminder.id,
    });
  });

  test("India's time zone is picked for +05:30", () {
    tzdata.initializeTimeZones();
    expect(
      localLocation(const Duration(hours: 5, minutes: 30)).name,
      'Asia/Kolkata',
    );
  });

  group('settings', () {
    Future<(ProviderContainer, _FakeScheduler)> start(
      Map<String, Object> stored, {
      bool allow = true,
    }) async {
      SharedPreferences.setMockInitialValues(stored);
      final fake = _FakeScheduler(allow: allow);
      final container = ProviderContainer(
        overrides: [reminderSchedulerProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      container.read(reminderSettingsProvider);
      await Future<void>.delayed(Duration.zero);
      return (container, fake);
    }

    test('off by default; saved switches are re-applied at start', () async {
      var (container, fake) = await start({});
      expect(container.read(reminderSettingsProvider).streakReminders, false);
      expect(fake.applied.last, isEmpty);

      (container, fake) = await start({'reminder_challenge': true});
      expect(fake.applied.last, [challengeReminder.id]);
    });

    test('turning on asks permission, saves and schedules', () async {
      final (container, fake) = await start({});
      final ok = await container
          .read(reminderSettingsProvider.notifier)
          .setStreakReminders(true);
      expect(ok, isTrue);
      expect(fake.permissionAsks, 1);
      expect(fake.applied.last, [streakReminder.id]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reminder_streak'), isTrue);
    });

    test('refused permission leaves it off', () async {
      final (container, fake) = await start({}, allow: false);
      final ok = await container
          .read(reminderSettingsProvider.notifier)
          .setSocialReminders(true);
      expect(ok, isFalse);
      expect(container.read(reminderSettingsProvider).socialReminders, false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reminder_social'), isNull);
    });

    test('turning off needs no permission and cancels it', () async {
      final (container, fake) = await start({'reminder_streak': true});
      await container
          .read(reminderSettingsProvider.notifier)
          .setStreakReminders(false);
      expect(fake.permissionAsks, 0);
      expect(fake.applied.last, isEmpty);
    });
  });
}
