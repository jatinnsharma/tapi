enum ChallengeType {
  trekDistance,
  visitCategory,
  morningWalk,
  snapPhoto,
  newPlace,
}

class DailyChallenge {
  const DailyChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.targetValue,
    required this.xpReward,
    this.targetCategory,
  });

  final String id;
  final String title;
  final String description;
  final ChallengeType type;
  final int targetValue;
  final int xpReward;
  final String? targetCategory;
}

class DailyChallengeProgress {
  const DailyChallengeProgress({
    required this.challenge,
    required this.currentValue,
    required this.isCompleted,
    required this.isClaimed,
  });

  final DailyChallenge challenge;
  final int currentValue;
  final bool isCompleted;
  final bool isClaimed;

  double get progressRatio => challenge.targetValue <= 0
      ? 1.0
      : (currentValue / challenge.targetValue).clamp(0.0, 1.0);

  DailyChallengeProgress copyWith({
    DailyChallenge? challenge,
    int? currentValue,
    bool? isCompleted,
    bool? isClaimed,
  }) {
    return DailyChallengeProgress(
      challenge: challenge ?? this.challenge,
      currentValue: currentValue ?? this.currentValue,
      isCompleted: isCompleted ?? this.isCompleted,
      isClaimed: isClaimed ?? this.isClaimed,
    );
  }
}
