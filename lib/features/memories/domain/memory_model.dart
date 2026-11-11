enum MemoryType { photo, video, voiceNote }

/// Who can watch a memory you've shared. A memory that isn't shared has no
/// visibility at all; `friends` and `public` mean it has an online copy.
enum MemoryVisibility {
  friends,
  public;

  String get label => this == MemoryVisibility.friends ? 'Friends' : 'Public';

  String get description => this == MemoryVisibility.friends
      ? 'Your accepted friends can watch it.'
      : 'Any signed-in explorer can watch it.';

  static MemoryVisibility? fromName(Object? name) {
    for (final v in MemoryVisibility.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

class Memory {
  const Memory({
    required this.id,
    required this.type,
    required this.filePath,
    required this.timestamp,
    this.adventureId,
    this.latitude,
    this.longitude,
    this.caption,
    this.durationSeconds,
    this.sharedId,
    this.visibility,
  });

  final String id;
  final MemoryType type;
  final String filePath;
  final DateTime timestamp;
  final String? adventureId;
  final double? latitude;
  final double? longitude;
  final String? caption;
  final int? durationSeconds;

  /// Id of the online copy (`shared_memories/{sharedId}`), once shared.
  final String? sharedId;
  final MemoryVisibility? visibility;

  bool get isShared => sharedId != null && visibility != null;

  Memory copyWith({
    String? caption,
    String? sharedId,
    MemoryVisibility? visibility,
    bool clearSharing = false,
  }) {
    return Memory(
      id: id,
      type: type,
      filePath: filePath,
      timestamp: timestamp,
      adventureId: adventureId,
      latitude: latitude,
      longitude: longitude,
      caption: caption ?? this.caption,
      durationSeconds: durationSeconds,
      sharedId: clearSharing ? null : (sharedId ?? this.sharedId),
      visibility: clearSharing ? null : (visibility ?? this.visibility),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'type': type.name,
      'file_path': filePath,
      'timestamp': timestamp.toIso8601String(),
      'adventure_id': adventureId,
      'latitude': latitude,
      'longitude': longitude,
      'caption': caption,
      'duration_seconds': durationSeconds,
      'shared_id': sharedId,
      'visibility': visibility?.name,
    };
  }

  factory Memory.fromMap(Map<String, Object?> map) {
    return Memory(
      id: map['id'] as String,
      type: MemoryType.values.byName(map['type'] as String),
      filePath: map['file_path'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      adventureId: map['adventure_id'] as String?,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      caption: map['caption'] as String?,
      durationSeconds: map['duration_seconds'] as int?,
      sharedId: map['shared_id'] as String?,
      visibility: MemoryVisibility.fromName(map['visibility']),
    );
  }
}
