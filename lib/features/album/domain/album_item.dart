import 'album_photo.dart';

/// One tile in a trip album: a photo in the shared album, one of yours
/// still on its way, or both (your shared photo, shown from the phone).
class AlbumItem {
  const AlbumItem({this.shared, this.mine})
    : assert(shared != null || mine != null);

  final AlbumPhoto? shared;
  final QueuedPhoto? mine;

  String get id => shared?.id ?? mine!.id;
  DateTime get takenAt => shared?.takenAt ?? mine!.takenAt;
  bool get isMine => mine != null;

  /// The label under your own photos until they're in the shared album.
  UploadStatus? get status => mine?.status;
}

/// Everyone's shared photos plus your own not shared yet, newest first.
/// Your shared photos appear once (matched by id) and are drawn from the
/// file on your phone, so they don't need downloading.
List<AlbumItem> mergeAlbum({
  required List<AlbumPhoto> shared,
  required List<QueuedPhoto> mine,
}) {
  final mineById = {for (final m in mine) m.id: m};
  final items = [
    for (final s in shared) AlbumItem(shared: s, mine: mineById.remove(s.id)),
    for (final m in mineById.values) AlbumItem(mine: m),
  ]..sort((a, b) => b.takenAt.compareTo(a.takenAt));
  return items;
}

/// "2 waiting · 1 uploading" for the album header, or null when nothing of
/// yours is pending.
String? queueSummary(List<QueuedPhoto> mine) {
  int count(UploadStatus s) => mine.where((m) => m.status == s).length;
  final parts = [
    for (final s in const [
      UploadStatus.uploading,
      UploadStatus.waiting,
      UploadStatus.failed,
    ])
      if (count(s) > 0) '${count(s)} ${s.label.toLowerCase()}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
