import '../../planner/domain/planner_input.dart';
import 'user_preferences.dart';

/// How the exploration preferences shape the rest of the app. Each returns
/// null when the preference isn't set, so the screen keeps its own default.

/// "Who you explore with" as the trip planner's "Who's going".
TripCompanion? companionFor(UserPreferences prefs) =>
    switch (prefs.socialPreference) {
      'Solo' => TripCompanion.solo,
      'Family' => TripCompanion.family,
      'Friends' || 'Group' || 'Meet explorers' => TripCompanion.friends,
      _ => null,
    };

/// Difficulty as the planner's pace: easy-going explorers get fewer stops a
/// day, hard-core ones more.
TripPace? paceFor(UserPreferences prefs) => switch (prefs.difficulty) {
  'Beginner' || 'Easy' => TripPace.relaxed,
  'Moderate' => TripPace.moderate,
  'Hard' || 'Expert' => TripPace.packed,
  _ => null,
};

/// The planner's interest chips that match the user's interests, or null
/// when none do.
Set<String>? plannerInterestsFor(UserPreferences prefs) {
  const map = {
    'Nature': 'Nature & Views',
    'Sunrise': 'Nature & Views',
    'Sunset': 'Nature & Views',
    'Photography': 'Photography',
    'Heritage': 'Heritage',
    'History': 'Heritage',
    'Architecture': 'Heritage',
    'Culture': 'Spiritual',
    'Shopping': 'Local Bazaars',
    'Local experiences': 'Street Food',
    'Adventure': 'Adventure',
  };
  final mapped = {for (final interest in prefs.interests) ?map[interest]};
  return mapped.isEmpty ? null : mapped;
}

/// How far Home's "Around you" looks by default, in km, from how long the
/// user likes to be out. One of `AroundYouSection`'s distance options.
double? aroundRadiusKmFor(UserPreferences prefs) => switch (prefs.duration) {
  '30 minutes' || '1 hour' => 5,
  '2 hours' => 10,
  '3 hours' || 'Half day' => 15,
  'Full day' => 25,
  'Multiple days' => 50,
  _ => null,
};
