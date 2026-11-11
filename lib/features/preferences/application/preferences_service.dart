import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/preferences_repository.dart';
import '../domain/user_preferences.dart';

final userPreferencesProvider =
    AsyncNotifierProvider<UserPreferencesNotifier, UserPreferences>(
      UserPreferencesNotifier.new,
    );

class UserPreferencesNotifier extends AsyncNotifier<UserPreferences> {
  @override
  Future<UserPreferences> build() {
    return ref.watch(preferencesRepositoryProvider).load();
  }

  void toggleInterest(String interest) {
    final current = state.value ?? const UserPreferences();
    final interests = <String>{...current.interests};
    if (!interests.remove(interest)) {
      interests.add(interest);
    }
    state = AsyncData(current.copyWith(interests: interests));
  }

  void setDuration(String? value) =>
      _update((p) => p.copyWith(duration: value));
  void setDifficulty(String? value) =>
      _update((p) => p.copyWith(difficulty: value));
  void setSocialPreference(String? value) =>
      _update((p) => p.copyWith(socialPreference: value));

  void _update(UserPreferences Function(UserPreferences) updater) {
    final current = state.value ?? const UserPreferences();
    state = AsyncData(updater(current));
  }

  Future<void> save() async {
    final current = state.value;
    if (current == null) return;
    await ref.read(preferencesRepositoryProvider).save(current);
  }
}
