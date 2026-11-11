enum FriendshipStatus { pending, accepted }

class Friendship {
  const Friendship({
    required this.id,
    required this.uidA,
    required this.uidB,
    required this.status,
    required this.requestedBy,
    required this.createdAt,
  });

  final String id;
  final String uidA;
  final String uidB;
  final FriendshipStatus status;
  final String requestedBy;
  final DateTime createdAt;

  bool get isAccepted => status == FriendshipStatus.accepted;

  /// True when [myUid] sent this request and it's still awaiting a response.
  bool isOutgoingFor(String myUid) => !isAccepted && requestedBy == myUid;

  /// True when [myUid] received this request and hasn't responded yet.
  bool isIncomingFor(String myUid) => !isAccepted && requestedBy != myUid;

  String otherUid(String myUid) => uidA == myUid ? uidB : uidA;

  static String idFor(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Map<String, Object?> toMap() {
    return {
      'uidA': uidA,
      'uidB': uidB,
      'status': status.name,
      'requestedBy': requestedBy,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Friendship.fromMap(String id, Map<String, Object?> map) {
    return Friendship(
      id: id,
      uidA: map['uidA'] as String,
      uidB: map['uidB'] as String,
      status: FriendshipStatus.values.byName(map['status'] as String),
      requestedBy: map['requestedBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
