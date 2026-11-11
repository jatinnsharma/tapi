class Checkpoint {
  const Checkpoint({
    required this.id,
    required this.adventureId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 30,
    this.xpReward = 50,
    this.reachedAt,
    this.orderIndex = 0,
  });

  final String id;
  final String adventureId;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final int xpReward;
  final DateTime? reachedAt;
  final int orderIndex;

  bool get isReached => reachedAt != null;

  Checkpoint copyWith({DateTime? reachedAt}) {
    return Checkpoint(
      id: id,
      adventureId: adventureId,
      name: name,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      xpReward: xpReward,
      reachedAt: reachedAt ?? this.reachedAt,
      orderIndex: orderIndex,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'adventure_id': adventureId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'xp_reward': xpReward,
      'reached_at': reachedAt?.toIso8601String(),
      'order_index': orderIndex,
    };
  }

  factory Checkpoint.fromMap(Map<String, Object?> map) {
    return Checkpoint(
      id: map['id'] as String,
      adventureId: map['adventure_id'] as String,
      name: map['name'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      radiusMeters: map['radius_meters'] as double,
      xpReward: map['xp_reward'] as int,
      reachedAt: map['reached_at'] == null
          ? null
          : DateTime.parse(map['reached_at'] as String),
      orderIndex: map['order_index'] as int,
    );
  }
}
