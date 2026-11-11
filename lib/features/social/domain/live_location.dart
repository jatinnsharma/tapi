class LiveLocation {
  const LiveLocation({
    required this.uid,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.adventureTitle,
    required this.updatedAt,
    required this.sharing,
    this.groupAdventureId,
  });

  final String uid;
  final String displayName;
  final double latitude;
  final double longitude;
  final String adventureTitle;
  final DateTime updatedAt;
  final bool sharing;

  /// Set when sharing from an adventure started off a Group Adventure —
  /// lets every member of that group see this position, not just friends.
  final String? groupAdventureId;

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'latitude': latitude,
      'longitude': longitude,
      'adventureTitle': adventureTitle,
      'updatedAt': updatedAt.toIso8601String(),
      'sharing': sharing,
      'groupAdventureId': groupAdventureId,
    };
  }

  factory LiveLocation.fromMap(Map<String, Object?> map) {
    return LiveLocation(
      uid: map['uid'] as String,
      displayName: map['displayName'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      adventureTitle: map['adventureTitle'] as String,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      sharing: map['sharing'] as bool,
      groupAdventureId: map['groupAdventureId'] as String?,
    );
  }
}
