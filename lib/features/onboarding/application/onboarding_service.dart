import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kOnboardingKey = 'onboarding_completed_v1';

/// Whether onboarding was finished, read once at start-up (before the first
/// screen), so a new user never sees Explore flash by first. If the setting
/// can't be read, onboarding is skipped rather than shown every time.
Future<bool> readOnboardingCompleted() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingKey) ?? false;
  } catch (_) {
    return true;
  }
}

/// Where the app opens: onboarding for a new user, Explore otherwise.
String startLocation({required bool onboarded}) =>
    onboarded ? '/explore' : '/onboarding';

/// Until onboarding is done, every other screen sends you back to it.
String? onboardingRedirect({
  required bool onboarded,
  required String location,
}) => !onboarded && location != '/onboarding' ? '/onboarding' : null;

final onboardingCompletedProvider = NotifierProvider<OnboardingNotifier, bool>(
  OnboardingNotifier.new,
);

class OnboardingNotifier extends Notifier<bool> {
  /// [initial] is the value read at start-up ([readOnboardingCompleted]).
  /// Without it (tests, or if start-up didn't provide it) the setting is
  /// loaded here, starting as "done".
  OnboardingNotifier({this.initial});

  final bool? initial;

  @override
  bool build() {
    final known = initial;
    if (known != null) return known;
    _load();
    return true;
  }

  Future<void> _load() async {
    state = await readOnboardingCompleted();
  }

  Future<void> completeOnboarding() async {
    state = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOnboardingKey, true);
    } catch (_) {}
  }
}
