import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_status.dart';
import '../domain/album_photo.dart';

/// The shared album: one record per photo under the trip
/// (`trip_plans/{tripId}/photos/{photoId}`), readable only by the trip's
/// members (see firestore.rules). The photos themselves are in each
/// uploader's Google Drive.
abstract class AlbumCloud {
  Stream<List<AlbumPhoto>> watch(String tripId);

  /// Adds or replaces the record (same id: retrying never duplicates).
  Future<void> put(String tripId, AlbumPhoto photo);
  Future<void> delete(String tripId, String photoId);
}

class FirestoreAlbumCloud implements AlbumCloud {
  FirestoreAlbumCloud(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _photos(String tripId) =>
      _firestore.collection('trip_plans').doc(tripId).collection('photos');

  @override
  Stream<List<AlbumPhoto>> watch(String tripId) =>
      _photos(tripId)
          .orderBy('takenAt', descending: true)
          .limit(500)
          .snapshots()
          .map(
            (snap) => [
              for (final doc in snap.docs)
                ?AlbumPhoto.fromFirestore(doc.id, doc.data()),
            ],
          );

  @override
  Future<void> put(String tripId, AlbumPhoto photo) =>
      _photos(tripId).doc(photo.id).set(photo.toFirestore(DateTime.now()));

  @override
  Future<void> delete(String tripId, String photoId) =>
      _photos(tripId).doc(photoId).delete();
}

final albumCloudProvider = Provider<AlbumCloud?>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return null;
  return FirestoreAlbumCloud(FirebaseFirestore.instance);
});

/// Everyone's photos in a trip's shared album (empty when offline-only).
final sharedAlbumProvider = StreamProvider.autoDispose
    .family<List<AlbumPhoto>, String>((ref, tripId) {
      final cloud = ref.watch(albumCloudProvider);
      if (cloud == null) return Stream.value(const []);
      return cloud.watch(tripId);
    });
