/// `friends`-scoped visibility is deliberately not modeled — same reasoning
/// as `GroupAdventureVisibility`: a listing query for it would need a
/// per-document `get()` lookup, which doesn't compose safely with Firestore's
/// list-query rule verification.
enum GroupVisibility { public, private }

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.description,
    required this.createdBy,
    required this.createdByName,
    required this.visibility,
    required this.memberUids,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String createdBy;
  final String createdByName;
  final GroupVisibility visibility;
  final List<String> memberUids;
  final DateTime createdAt;

  bool isMember(String uid) => uid == createdBy || memberUids.contains(uid);

  /// Includes the creator, who isn't duplicated into `memberUids`.
  int get memberCount => memberUids.length + 1;

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'description': description,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'visibility': visibility.name,
      'memberUids': memberUids,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Group.fromMap(String id, Map<String, Object?> map) {
    return Group(
      id: id,
      name: map['name'] as String,
      description: map['description'] as String,
      createdBy: map['createdBy'] as String,
      createdByName: map['createdByName'] as String,
      visibility: GroupVisibility.values.byName(map['visibility'] as String),
      memberUids: (map['memberUids'] as List<dynamic>).cast<String>(),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
