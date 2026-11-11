enum ChallengeGoalType {
  moreTrekKm,
  firstToReach;

  String get label => this == ChallengeGoalType.moreTrekKm
      ? 'Trek Distance Race'
      : 'First to Reach Destination';
}

enum FriendChallengeStatus { pending, active, completed, declined }

class FriendChallenge {
  const FriendChallenge({
    required this.id,
    required this.challengerUid,
    required this.challengerName,
    required this.challengedUid,
    required this.challengedName,
    required this.type,
    required this.targetValue,
    this.targetPlaceName,
    required this.createdAt,
    required this.expiresAt,
    this.status = FriendChallengeStatus.pending,
    this.challengerProgress = 0,
    this.challengedProgress = 0,
    this.winnerUid,
  });

  final String id;
  final String challengerUid;
  final String challengerName;
  final String challengedUid;
  final String challengedName;
  final ChallengeGoalType type;

  /// Target in meters (for moreTrekKm) or placeId (for firstToReach)
  final String targetValue;
  final String? targetPlaceName;
  final DateTime createdAt;
  final DateTime expiresAt;
  final FriendChallengeStatus status;
  final double challengerProgress;
  final double challengedProgress;
  final String? winnerUid;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool isParticipant(String uid) =>
      challengerUid == uid || challengedUid == uid;

  String otherName(String myUid) =>
      myUid == challengerUid ? challengedName : challengerName;

  double myProgress(String myUid) =>
      myUid == challengerUid ? challengerProgress : challengedProgress;

  double theirProgress(String myUid) =>
      myUid == challengerUid ? challengedProgress : challengerProgress;

  FriendChallenge copyWith({
    FriendChallengeStatus? status,
    double? challengerProgress,
    double? challengedProgress,
    String? winnerUid,
  }) {
    return FriendChallenge(
      id: id,
      challengerUid: challengerUid,
      challengerName: challengerName,
      challengedUid: challengedUid,
      challengedName: challengedName,
      type: type,
      targetValue: targetValue,
      targetPlaceName: targetPlaceName,
      createdAt: createdAt,
      expiresAt: expiresAt,
      status: status ?? this.status,
      challengerProgress: challengerProgress ?? this.challengerProgress,
      challengedProgress: challengedProgress ?? this.challengedProgress,
      winnerUid: winnerUid ?? this.winnerUid,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'challengerUid': challengerUid,
      'challengerName': challengerName,
      'challengedUid': challengedUid,
      'challengedName': challengedName,
      'type': type.name,
      'targetValue': targetValue,
      'targetPlaceName': targetPlaceName,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'status': status.name,
      'challengerProgress': challengerProgress,
      'challengedProgress': challengedProgress,
      'winnerUid': winnerUid,
    };
  }

  factory FriendChallenge.fromMap(Map<String, dynamic> map, [String? docId]) {
    return FriendChallenge(
      id: docId ?? (map['id'] as String? ?? ''),
      challengerUid: map['challengerUid'] as String,
      challengerName: (map['challengerName'] as String?) ?? 'Explorer',
      challengedUid: map['challengedUid'] as String,
      challengedName: (map['challengedName'] as String?) ?? 'Explorer',
      type: ChallengeGoalType.values.byName(map['type'] as String),
      targetValue: (map['targetValue'] as String?) ?? '5000',
      targetPlaceName: map['targetPlaceName'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      expiresAt: DateTime.parse(map['expiresAt'] as String),
      status: FriendChallengeStatus.values.byName(
        (map['status'] as String?) ?? 'pending',
      ),
      challengerProgress:
          (map['challengerProgress'] as num?)?.toDouble() ?? 0.0,
      challengedProgress:
          (map['challengedProgress'] as num?)?.toDouble() ?? 0.0,
      winnerUid: map['winnerUid'] as String?,
    );
  }
}
