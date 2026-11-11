class ExplorerProfile {
  const ExplorerProfile({
    required this.uid,
    required this.displayName,
    required this.createdAt,
    this.bio,
    this.photoUrl,
    this.totalXp = 0,
    this.weeklyXp = 0,
    this.weeklyKey,
  });

  final String uid;
  final String displayName;
  final DateTime createdAt;
  final String? bio;
  final String? photoUrl;

  /// Best-effort mirror of the device-local XP total (see
  /// `TrackingService._syncXpBestEffort`) — XP itself lives in each user's
  /// local SQLite database, not Firestore, so this is a denormalized copy
  /// synced after every completed adventure, purely so things like a Group's
  /// total XP can be computed without each member needing to be online at
  /// the same time.
  final int totalXp;
  final int weeklyXp;
  final String? weeklyKey;

  ExplorerProfile copyWith({
    String? displayName,
    String? bio,
    String? photoUrl,
    int? totalXp,
    int? weeklyXp,
    String? weeklyKey,
  }) {
    return ExplorerProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt,
      bio: bio ?? this.bio,
      photoUrl: photoUrl ?? this.photoUrl,
      totalXp: totalXp ?? this.totalXp,
      weeklyXp: weeklyXp ?? this.weeklyXp,
      weeklyKey: weeklyKey ?? this.weeklyKey,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'createdAt': createdAt.toIso8601String(),
      'bio': bio,
      'photoUrl': photoUrl,
      'totalXp': totalXp,
      'weeklyXp': weeklyXp,
      'weeklyKey': weeklyKey,
    };
  }

  factory ExplorerProfile.fromMap(Map<String, Object?> map) {
    return ExplorerProfile(
      uid: map['uid'] as String,
      displayName: map['displayName'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      bio: map['bio'] as String?,
      photoUrl: map['photoUrl'] as String?,
      totalXp: map['totalXp'] as int? ?? 0,
      weeklyXp: map['weeklyXp'] as int? ?? 0,
      weeklyKey: map['weeklyKey'] as String?,
    );
  }
}
