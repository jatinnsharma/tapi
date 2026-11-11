class ActivityEntry {
  const ActivityEntry({
    this.id,
    required this.uid,
    required this.displayName,
    required this.title,
    required this.distanceKm,
    required this.xpEarned,
    required this.timestamp,
    this.encodedPolyline,
  });

  final String? id;
  final String uid;
  final String displayName;
  final String title;
  final double distanceKm;
  final int xpEarned;
  final DateTime timestamp;
  final String? encodedPolyline;

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'title': title,
      'distanceKm': distanceKm,
      'xpEarned': xpEarned,
      'timestamp': timestamp.toIso8601String(),
      if (encodedPolyline != null) 'encodedPolyline': encodedPolyline,
    };
  }

  factory ActivityEntry.fromMap(String id, Map<String, Object?> map) {
    return ActivityEntry(
      id: id,
      uid: map['uid'] as String,
      displayName: map['displayName'] as String,
      title: map['title'] as String,
      distanceKm: (map['distanceKm'] as num).toDouble(),
      xpEarned: map['xpEarned'] as int,
      timestamp: DateTime.parse(map['timestamp'] as String),
      encodedPolyline: map['encodedPolyline'] as String?,
    );
  }
}
