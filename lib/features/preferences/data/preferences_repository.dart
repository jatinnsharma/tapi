import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/user_preferences.dart';

final preferencesRepositoryProvider = Provider<PreferencesRepository>((ref) {
  return PreferencesRepository();
});

class PreferencesRepository {
  static const _interestsKey = 'pref_interests';
  static const _durationKey = 'pref_duration';
  static const _difficultyKey = 'pref_difficulty';
  static const _socialKey = 'pref_social';

  Future<UserPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return UserPreferences(
      interests: (prefs.getStringList(_interestsKey) ?? const []).toSet(),
      duration: prefs.getString(_durationKey),
      difficulty: prefs.getString(_difficultyKey),
      socialPreference: prefs.getString(_socialKey),
    );
  }

  Future<void> save(UserPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_interestsKey, preferences.interests.toList());
    await _setOrRemove(prefs, _durationKey, preferences.duration);
    await _setOrRemove(prefs, _difficultyKey, preferences.difficulty);
    await _setOrRemove(prefs, _socialKey, preferences.socialPreference);
  }

  Future<void> _setOrRemove(
    SharedPreferences prefs,
    String key,
    String? value,
  ) {
    if (value == null) return prefs.remove(key);
    return prefs.setString(key, value);
  }
}
