import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../social/data/social_repository.dart';
import '../domain/trip_plan.dart';

final tripCloudRepositoryProvider = Provider<TripCloudRepository>((ref) {
  return TripCloudRepository(ref.watch(firestoreProvider));
});

/// Saved trips in Firestore: one `trip_plans/{tripId}` doc per trip, readable
/// and editable by everyone in its `memberUids` (the owner included). The same
/// doc serves backup across devices and sharing with friends. Only the owner
/// can add or remove members or delete the trip; a member can leave. See the
/// `trip_plans` rule in firestore.rules.
///
/// The whole plan is stored as one map and the newer `updatedAt` wins, so if
/// two people edit the same trip at the same moment the last save is kept.
class TripCloudRepository {
  TripCloudRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _trips =>
      _firestore.collection('trip_plans');

  Future<List<TripPlan>> getTripsFor(String uid) async {
    final snapshot = await _trips.where('memberUids', arrayContains: uid).get();
    return [for (final doc in snapshot.docs) ?_fromDoc(doc.data())];
  }

  /// Live copy of one trip, for a trip someone else may be editing. Emits
  /// null if the trip is deleted or the user is removed from it.
  Stream<TripPlan?> watchTrip(String id) {
    return _trips
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? _fromDoc(doc.data()!) : null)
        .handleError((Object _) {});
  }

  Future<void> saveTrip(TripPlan plan) {
    final cloudCopy = plan.copyWith(cloudSynced: true);
    return _trips.doc(plan.id).set({
      'ownerUid': plan.ownerUid,
      'memberUids': plan.memberUids,
      'updatedAt': plan.lastChanged.toIso8601String(),
      'plan': cloudCopy.toJson(),
    });
  }

  Future<void> deleteTrip(String id) => _trips.doc(id).delete();

  /// Removes [uid] from a trip someone else owns.
  Future<void> leaveTrip(String id, String uid) {
    return _trips.doc(id).update({
      'memberUids': FieldValue.arrayRemove([uid]),
    });
  }

  TripPlan? _fromDoc(Map<String, dynamic> data) {
    try {
      final plan = TripPlan.fromJson(data['plan'] as Map<String, dynamic>);
      // The top-level fields are what the rules check, so they're the truth.
      return plan.copyWith(
        ownerUid: data['ownerUid'] as String?,
        memberUids: (data['memberUids'] as List<dynamic>?)
            ?.map((u) => u.toString())
            .toList(),
        cloudSynced: true,
      );
    } catch (_) {
      return null; // Skip a malformed doc rather than fail the whole list.
    }
  }
}
