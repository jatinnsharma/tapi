import 'memory_model.dart';

/// Firestore doc `shared_memories/{id}`: the online copy of a photo or video
/// someone chose to share. The file itself is in Firebase Storage at [url].
class SharedMemory {
  const SharedMemory({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.type,
    required this.url,
    required this.visibility,
    required this.createdAt,
    this.caption,
    this.latitude,
    this.longitude,
    this.placeName,
  });

  final String id;
  final String uid;
  final String displayName;
  final MemoryType type;
  final String url;
  final MemoryVisibility visibility;
  final DateTime createdAt;
  final String? caption;
  final double? latitude;
  final double? longitude;
  final String? placeName;

  bool get isVideo => type == MemoryType.video;

  Map<String, Object?> toMap() => {
    'uid': uid,
    'displayName': displayName,
    'type': type.name,
    'url': url,
    'visibility': visibility.name,
    'createdAt': createdAt.toIso8601String(),
    'caption': caption,
    'latitude': latitude,
    'longitude': longitude,
    'placeName': placeName,
  };

  factory SharedMemory.fromMap(String id, Map<String, Object?> map) {
    return SharedMemory(
      id: id,
      uid: map['uid'] as String,
      displayName: (map['displayName'] as String?) ?? 'Explorer',
      type: map['type'] == MemoryType.video.name
          ? MemoryType.video
          : MemoryType.photo,
      url: map['url'] as String,
      visibility:
          MemoryVisibility.fromName(map['visibility']) ??
          MemoryVisibility.friends,
      createdAt:
          DateTime.tryParse((map['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      caption: map['caption'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      placeName: map['placeName'] as String?,
    );
  }
}
