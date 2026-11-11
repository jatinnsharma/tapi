const List<String> interestOptions = [
  'Nature',
  'Photography',
  'Heritage',
  'History',
  'Architecture',
  'Art',
  'Culture',
  'Shopping',
  'Sunrise',
  'Sunset',
  'Hidden gems',
  'Adventure',
  'Local experiences',
];

const List<String> durationOptions = [
  '30 minutes',
  '1 hour',
  '2 hours',
  '3 hours',
  'Half day',
  'Full day',
  'Multiple days',
];

const List<String> difficultyOptions = [
  'Beginner',
  'Easy',
  'Moderate',
  'Hard',
  'Expert',
];

const List<String> socialPreferenceOptions = [
  'Solo',
  'Friends',
  'Family',
  'Group',
  'Meet explorers',
];

class UserPreferences {
  const UserPreferences({
    this.interests = const {},
    this.duration,
    this.difficulty,
    this.socialPreference,
  });

  final Set<String> interests;
  final String? duration;
  final String? difficulty;
  final String? socialPreference;

  bool get hasAnyPreference =>
      interests.isNotEmpty ||
      duration != null ||
      difficulty != null ||
      socialPreference != null;

  UserPreferences copyWith({
    Set<String>? interests,
    String? duration,
    String? difficulty,
    String? socialPreference,
  }) {
    return UserPreferences(
      interests: interests ?? this.interests,
      duration: duration ?? this.duration,
      difficulty: difficulty ?? this.difficulty,
      socialPreference: socialPreference ?? this.socialPreference,
    );
  }
}
