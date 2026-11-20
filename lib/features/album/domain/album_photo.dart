/// Where one of your album photos is on its way to the trip album.
enum UploadStatus {
  /// Kept on this phone only: the album isn't shared (signed out, the trip
  /// isn't backed up, or Drive isn't set up in this build).
  local('On this phone'),

  /// In the queue: no connection yet, Drive not connected, or retrying soon.
  waiting('Waiting'),
  uploading('Uploading'),
  shared('Shared'),

  /// Stopped retrying on its own (e.g. the file is gone). Tap to retry.
  failed('Failed');

  const UploadStatus(this.label);
  final String label;

  static UploadStatus parse(String? s) => UploadStatus.values.firstWhere(
    (v) => v.name == s,
    orElse: () => UploadStatus.waiting,
  );
}

/// One of your photos in a trip album, as the phone's upload queue knows it.
class QueuedPhoto {
  const QueuedPhoto({
    required this.id,
    required this.tripId,
    required this.filePath,
    required this.takenAt,
    required this.status,
    this.memoryId,
    this.latitude,
    this.longitude,
    this.includeLocation = false,
    this.attempts = 0,
    this.nextTryAt,
    this.lastError,
    this.viewFileId,
    this.thumbFileId,
    this.sharedOutAt,
  });

  /// Also the id of the photo in the shared album, so uploading twice can
  /// never make two copies.
  final String id;
  final String tripId;
  final String? memoryId;
  final String filePath;
  final DateTime takenAt;
  final double? latitude;
  final double? longitude;

  /// Show where it was taken to the other members (off by default).
  final bool includeLocation;
  final UploadStatus status;
  final int attempts;
  final DateTime? nextTryAt;
  final String? lastError;

  /// Drive files already uploaded, kept so a retry doesn't upload again.
  final String? viewFileId;
  final String? thumbFileId;

  /// When it was last sent through the share sheet (WhatsApp, Telegram...).
  final DateTime? sharedOutAt;

  QueuedPhoto copyWith({
    UploadStatus? status,
    int? attempts,
    DateTime? nextTryAt,
    bool clearNextTry = false,
    String? lastError,
    bool clearError = false,
    String? viewFileId,
    String? thumbFileId,
    DateTime? sharedOutAt,
    bool? includeLocation,
  }) => QueuedPhoto(
    id: id,
    tripId: tripId,
    memoryId: memoryId,
    filePath: filePath,
    takenAt: takenAt,
    latitude: latitude,
    longitude: longitude,
    includeLocation: includeLocation ?? this.includeLocation,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    nextTryAt: clearNextTry ? null : (nextTryAt ?? this.nextTryAt),
    lastError: clearError ? null : (lastError ?? this.lastError),
    viewFileId: viewFileId ?? this.viewFileId,
    thumbFileId: thumbFileId ?? this.thumbFileId,
    sharedOutAt: sharedOutAt ?? this.sharedOutAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'trip_id': tripId,
    'memory_id': memoryId,
    'file_path': filePath,
    'taken_at': takenAt.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'include_location': includeLocation ? 1 : 0,
    'status': status.name,
    'attempts': attempts,
    'next_try_at': nextTryAt?.toIso8601String(),
    'last_error': lastError,
    'view_file_id': viewFileId,
    'thumb_file_id': thumbFileId,
    'shared_out_at': sharedOutAt?.toIso8601String(),
  };

  factory QueuedPhoto.fromMap(Map<String, Object?> m) => QueuedPhoto(
    id: m['id']! as String,
    tripId: m['trip_id']! as String,
    memoryId: m['memory_id'] as String?,
    filePath: m['file_path']! as String,
    takenAt: DateTime.parse(m['taken_at']! as String),
    latitude: (m['latitude'] as num?)?.toDouble(),
    longitude: (m['longitude'] as num?)?.toDouble(),
    includeLocation: (m['include_location'] as int? ?? 0) == 1,
    status: UploadStatus.parse(m['status'] as String?),
    attempts: m['attempts'] as int? ?? 0,
    nextTryAt: m['next_try_at'] == null
        ? null
        : DateTime.parse(m['next_try_at']! as String),
    lastError: m['last_error'] as String?,
    viewFileId: m['view_file_id'] as String?,
    thumbFileId: m['thumb_file_id'] as String?,
    sharedOutAt: m['shared_out_at'] == null
        ? null
        : DateTime.parse(m['shared_out_at']! as String),
  );
}

/// A photo in the shared album, as every trip member sees it.
class AlbumPhoto {
  const AlbumPhoto({
    required this.id,
    required this.uploaderUid,
    required this.uploaderName,
    required this.takenAt,
    required this.thumbFileId,
    required this.viewFileId,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String uploaderUid;
  final String uploaderName;
  final DateTime takenAt;
  final String thumbFileId;
  final String viewFileId;
  final double? latitude;
  final double? longitude;

  bool get hasLocation => latitude != null && longitude != null;

  Map<String, Object?> toFirestore(DateTime now) => {
    'uploaderUid': uploaderUid,
    'uploaderName': uploaderName,
    'takenAt': takenAt.toUtc().toIso8601String(),
    'thumbFileId': thumbFileId,
    'viewFileId': viewFileId,
    'latitude': ?latitude,
    'longitude': ?longitude,
    'createdAt': now.toUtc().toIso8601String(),
  };

  static AlbumPhoto? fromFirestore(String id, Map<String, Object?> d) {
    final thumb = d['thumbFileId'], view = d['viewFileId'];
    final uploader = d['uploaderUid'], taken = d['takenAt'];
    if (thumb is! String || view is! String) return null;
    if (uploader is! String || taken is! String) return null;
    final at = DateTime.tryParse(taken);
    if (at == null) return null;
    return AlbumPhoto(
      id: id,
      uploaderUid: uploader,
      uploaderName: d['uploaderName'] as String? ?? 'A member',
      takenAt: at.toLocal(),
      thumbFileId: thumb,
      viewFileId: view,
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
    );
  }
}

/// How long to wait before the next try after [attempts] failures:
/// 30 s, 1 min, 2 min ... up to an hour.
Duration retryDelay(int attempts) {
  final seconds = 30 * (1 << attempts.clamp(0, 7));
  return Duration(seconds: seconds.clamp(30, 3600));
}

/// After this many failures in a row, stop retrying on our own: the photo
/// is marked Failed until the user taps Retry.
const maxAutoAttempts = 8;
