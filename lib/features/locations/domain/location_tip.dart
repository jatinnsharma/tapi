/// Longest tip (also enforced by the Firestore rules).
const maxTipLength = 280;

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

/// The tips to show: not written by someone in [hiddenAuthors] (people the
/// user blocked) and not one the user reported ([reportedTipIds]).
List<LocationTip> visibleTips(
  List<LocationTip> tips, {
  Set<String> hiddenAuthors = const {},
  Set<String> reportedTipIds = const {},
}) => [
  for (final tip in tips)
    if (!hiddenAuthors.contains(tip.uid) && !reportedTipIds.contains(tip.id))
      tip,
];
