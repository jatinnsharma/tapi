import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/reminder_schedule.dart';
import 'reminder_scheduler.dart';

class ReminderSettings {
  const ReminderSettings({
    required this.streakReminders,
    required this.challengeReminders,
    required this.socialReminders,
  });

  final bool streakReminders;
  final bool challengeReminders;
  final bool socialReminders;

  ReminderSettings copyWith({
    bool? streakReminders,
    bool? challengeReminders,
    bool? socialReminders,
  }) {
    return ReminderSettings(
      streakReminders: streakReminders ?? this.streakReminders,
      challengeReminders: challengeReminders ?? this.challengeReminders,
      socialReminders: socialReminders ?? this.socialReminders,
    );
  }
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
      ReminderSettingsNotifier.new,
    );

/// The three reminder switches, kept in SharedPreferences. Every change (and
/// app start) re-schedules the phone's reminders to match. Reminders are
/// opt-in: turning one on asks for notification permission first.
class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  static const String _kStreak = 'reminder_streak';
  static const String _kChallenge = 'reminder_challenge';
  static const String _kSocial = 'reminder_social';

  static const off = ReminderSettings(
    streakReminders: false,
    challengeReminders: false,
    socialReminders: false,
  );

  @override
  ReminderSettings build() {
    _load();
    return off;
  }

  ReminderScheduler get _scheduler => ref.read(reminderSchedulerProvider);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ReminderSettings(
        streakReminders: prefs.getBool(_kStreak) ?? false,
        challengeReminders: prefs.getBool(_kChallenge) ?? false,
        socialReminders: prefs.getBool(_kSocial) ?? false,
      );
      await _scheduler.apply(remindersFor(state));
    } catch (_) {}
  }

  /// Each returns false when turning on was refused (no permission); the
  /// switch then stays off.
  Future<bool> setStreakReminders(bool enabled) =>
      _set(_kStreak, enabled, (s) => s.copyWith(streakReminders: enabled));

  Future<bool> setChallengeReminders(bool enabled) => _set(
    _kChallenge,
    enabled,
    (s) => s.copyWith(challengeReminders: enabled),
  );

  Future<bool> setSocialReminders(bool enabled) =>
      _set(_kSocial, enabled, (s) => s.copyWith(socialReminders: enabled));

  Future<bool> _set(
    String key,
    bool enabled,
    ReminderSettings Function(ReminderSettings) change,
  ) async {
    if (enabled && !await _scheduler.requestPermission()) return false;
    state = change(state);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, enabled);
    await _scheduler.apply(remindersFor(state));
    return true;
  }
}
