class LocationTip {
  const LocationTip({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String uid;
  final String displayName;
  final String text;
  final DateTime timestamp;

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory LocationTip.fromMap(String id, Map<String, Object?> map) {
    return LocationTip(
      id: id,
      uid: map['uid'] as String,
      displayName: map['displayName'] as String,
      text: map['text'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
