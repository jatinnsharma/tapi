import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/planner/domain/planner_input.dart';
import 'package:real_world_exploration/features/preferences/domain/preference_mapping.dart';
import 'package:real_world_exploration/features/preferences/domain/user_preferences.dart';

void main() {
  const none = UserPreferences();

  test('nothing set: every screen keeps its own default', () {
    expect(companionFor(none), isNull);
    expect(paceFor(none), isNull);
    expect(plannerInterestsFor(none), isNull);
    expect(aroundRadiusKmFor(none), isNull);
  });

  test('social preference sets who is going', () {
    expect(
      companionFor(const UserPreferences(socialPreference: 'Solo')),
      TripCompanion.solo,
    );
    expect(
      companionFor(const UserPreferences(socialPreference: 'Family')),
      TripCompanion.family,
    );
    expect(
      companionFor(const UserPreferences(socialPreference: 'Meet explorers')),
      TripCompanion.friends,
    );
  });

  test('difficulty sets the pace', () {
    expect(
      paceFor(const UserPreferences(difficulty: 'Beginner')),
      TripPace.relaxed,
    );
    expect(
      paceFor(const UserPreferences(difficulty: 'Moderate')),
      TripPace.moderate,
    );
    expect(
      paceFor(const UserPreferences(difficulty: 'Expert')),
      TripPace.packed,
    );
  });

  test('interests map onto the planner chips, without duplicates', () {
    expect(
      plannerInterestsFor(
        const UserPreferences(
          interests: {'History', 'Architecture', 'Sunset', 'Shopping'},
        ),
      ),
      {'Heritage', 'Nature & Views', 'Local Bazaars'},
    );
    // An interest with no planner match is left out.
    expect(
      plannerInterestsFor(const UserPreferences(interests: {'Hidden gems'})),
      isNull,
    );
  });

  test('every option maps to a real planner chip or distance', () {
    const plannerChips = {
      'Heritage',
      'Spiritual',
      'Street Food',
      'Nature & Views',
      'Photography',
      'Local Bazaars',
      'Cafes',
      'Adventure',
    };
    final all = plannerInterestsFor(
      UserPreferences(interests: interestOptions.toSet()),
    )!;
    expect(plannerChips.containsAll(all), isTrue);

    for (final d in durationOptions) {
      expect(
        [5.0, 10.0, 15.0, 25.0, 50.0],
        contains(aroundRadiusKmFor(UserPreferences(duration: d))),
        reason: d,
      );
    }
    for (final d in difficultyOptions) {
      expect(paceFor(UserPreferences(difficulty: d)), isNotNull, reason: d);
    }
    for (final s in socialPreferenceOptions) {
      expect(companionFor(UserPreferences(socialPreference: s)), isNotNull);
    }
  });
}
