class StreakData {
  const StreakData({
    required this.currentStreak,
    required this.bestStreak,
    required this.completedToday,
    required this.freezesAvailable,
    this.freezeUsedToday = false,
  });

  final int currentStreak;
  final int bestStreak;
  final bool completedToday;
  final int freezesAvailable;
  final bool freezeUsedToday;

  bool get isActive => currentStreak > 0;
}
