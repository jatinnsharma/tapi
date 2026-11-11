enum WishlistType { location, quest }

class WishlistEntry {
  const WishlistEntry({
    required this.type,
    required this.targetId,
    required this.addedAt,
  });

  final WishlistType type;
  final String targetId;
  final DateTime addedAt;

  String get key => '${type.name}:$targetId';

  Map<String, Object?> toMap() {
    return {
      'target_type': type.name,
      'target_id': targetId,
      'added_at': addedAt.toIso8601String(),
    };
  }

  factory WishlistEntry.fromMap(Map<String, Object?> map) {
    return WishlistEntry(
      type: WishlistType.values.byName(map['target_type'] as String),
      targetId: map['target_id'] as String,
      addedAt: DateTime.parse(map['added_at'] as String),
    );
  }
}
