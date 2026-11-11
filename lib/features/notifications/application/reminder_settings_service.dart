import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  static const String _kStreak = 'reminder_streak';
  static const String _kChallenge = 'reminder_challenge';
  static const String _kSocial = 'reminder_social';

  @override
  ReminderSettings build() {
    _load();
    return const ReminderSettings(
      streakReminders: true,
      challengeReminders: true,
      socialReminders: true,
    );
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ReminderSettings(
        streakReminders: prefs.getBool(_kStreak) ?? true,
        challengeReminders: prefs.getBool(_kChallenge) ?? true,
        socialReminders: prefs.getBool(_kSocial) ?? true,
      );
    } catch (_) {}
  }

  Future<void> setStreakReminders(bool enabled) async {
    state = state.copyWith(streakReminders: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStreak, enabled);
  }

  Future<void> setChallengeReminders(bool enabled) async {
    state = state.copyWith(challengeReminders: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kChallenge, enabled);
  }

  Future<void> setSocialReminders(bool enabled) async {
    state = state.copyWith(socialReminders: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSocial, enabled);
  }
}
