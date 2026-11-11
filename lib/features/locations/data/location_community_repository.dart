import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/location_tip.dart';

final locationCommunityRepositoryProvider =
    Provider<LocationCommunityRepository>((ref) {
      return LocationCommunityRepository(FirebaseFirestore.instance);
    });

/// The social layer over a location (spec §44 — explorer count, tips),
/// kept entirely separate from `LocationRepository`'s per-device local
/// SQLite discovery tracking. This works as a pure *addition*, not a
/// migration: `ExploreLocation.id` values are static constants baked into
/// the app (`location_seed.dart`), identical across every install, so they
/// make a stable shared key without needing to move any existing local
/// data anywhere.
class LocationCommunityRepository {
  LocationCommunityRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _community(String locationId) =>
      _firestore.collection('location_communities').doc(locationId);

  CollectionReference<Map<String, dynamic>> _visitors(String locationId) =>
      _community(locationId).collection('visitors');

  CollectionReference<Map<String, dynamic>> _tips(String locationId) =>
      _community(locationId).collection('tips');

  /// Counts this user as an explorer of this location, exactly once ever —
  /// a `visitors/{uid}` marker doc dedupes repeat calls (e.g. re-discovering
  /// after reinstalling the app locally). Best-effort: callers should treat
  /// failures as non-fatal, since this is just a social nicety layered on
  /// top of fog-of-war, not the discovery mechanic itself.
  Future<void> recordVisitIfNew(String locationId, String uid) async {
    final visitorDoc = _visitors(locationId).doc(uid);
    final existing = await visitorDoc.get();
    if (existing.exists) return;

    await visitorDoc.set({'visitedAt': DateTime.now().toIso8601String()});
    await _community(
      locationId,
    ).set({'explorerCount': FieldValue.increment(1)}, SetOptions(merge: true));
  }

  Future<int> getExplorerCount(String locationId) async {
    final doc = await _community(locationId).get();
    return (doc.data()?['explorerCount'] as int?) ?? 0;
  }

  Future<void> postTip(String locationId, LocationTip tip) {
    return _tips(locationId).add(tip.toMap());
  }

  Future<List<LocationTip>> getTips(String locationId) async {
    final snapshot = await _tips(locationId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();
    return snapshot.docs
        .map((doc) => LocationTip.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<void> deleteTip(String locationId, String tipId) {
    return _tips(locationId).doc(tipId).delete();
  }
}
