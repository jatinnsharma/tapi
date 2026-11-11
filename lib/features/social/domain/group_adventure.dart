/// `friends`-scoped visibility is deliberately not modeled: a listing query
/// for "adventures visible to me because the creator is my friend" would
/// need a `get()` friendship lookup per candidate document, which doesn't
/// compose safely with Firestore's per-query security rule verification.
/// See the comment on `SocialRepository`'s group adventure methods.
enum GroupAdventureVisibility { public, private }

class GroupAdventure {
  const GroupAdventure({
    required this.id,
    required this.name,
    required this.description,
    required this.createdBy,
    required this.createdByName,
    required this.locationHint,
    required this.date,
    required this.time,
    required this.meetingPoint,
    required this.difficulty,
    required this.groupSizeLimit,
    required this.visibility,
    required this.memberUids,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String createdBy;
  final String createdByName;
  final String locationHint;
  final String date;
  final String time;
  final String meetingPoint;
  final String difficulty;
  final int groupSizeLimit;
  final GroupAdventureVisibility visibility;
  final List<String> memberUids;
  final DateTime createdAt;

  bool isMember(String uid) => uid == createdBy || memberUids.contains(uid);
  bool get isFull => memberUids.length >= groupSizeLimit;

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'description': description,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'locationHint': locationHint,
      'date': date,
      'time': time,
      'meetingPoint': meetingPoint,
      'difficulty': difficulty,
      'groupSizeLimit': groupSizeLimit,
      'visibility': visibility.name,
      'memberUids': memberUids,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory GroupAdventure.fromMap(String id, Map<String, Object?> map) {
    return GroupAdventure(
      id: id,
      name: map['name'] as String,
      description: map['description'] as String,
      createdBy: map['createdBy'] as String,
      createdByName: map['createdByName'] as String,
      locationHint: map['locationHint'] as String,
      date: map['date'] as String,
      time: map['time'] as String,
      meetingPoint: map['meetingPoint'] as String,
      difficulty: map['difficulty'] as String,
      groupSizeLimit: map['groupSizeLimit'] as int,
      visibility: GroupAdventureVisibility.values.byName(
        map['visibility'] as String,
      ),
      memberUids: (map['memberUids'] as List<dynamic>).cast<String>(),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
