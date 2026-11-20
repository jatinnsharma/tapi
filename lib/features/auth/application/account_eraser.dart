import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../social/data/social_repository.dart';

/// Everything about a user in the cloud that deleting their account must
/// remove (or leave, for things other people own). Each call is safe to
/// repeat: a deletion that stopped half-way is simply run again.
abstract class AccountDataStore {
  /// Trips the user owns or is a member of.
  Future<List<({String id, String ownerUid})>> tripsFor(String uid);

  /// Album records in a trip: all of them, or only [uploaderUid]'s.
  Future<void> deleteAlbumRecords(String tripId, {String? uploaderUid});
  Future<void> deleteTrip(String tripId);
  Future<void> leaveTrip(String tripId, String uid);

  Future<void> deleteToursBy(String uid);
  Future<void> deleteTipsBy(String uid);
  Future<void> deleteChallengesOf(String uid);

  /// Groups (or meetups) the user created or joined.
  Future<List<({String id, bool created})>> groupsOf(String uid);
  Future<void> deleteGroup(String id);
  Future<void> leaveGroup(String id, String uid);
  Future<List<({String id, bool created})>> meetupsOf(String uid);
  Future<void> deleteMeetup(String id);
  Future<void> leaveMeetup(String id, String uid);

  Future<void> deleteAvatar(String uid);

  /// Profile, friendships, feed posts, blocks, mutes, live location and
  /// footprint ([SocialRepository.deleteAllDataFor]). Run last.
  Future<void> deleteSocialData(String uid);
}

/// Removes [uid]'s data from the cloud, in an order the security rules
/// allow: album records before their trip, leaving shared things while
/// still a member, and the profile last. Stops at the first failure (so
/// the sign-in is never deleted with data left behind); running it again
/// finishes the job.
Future<void> eraseAccountData(AccountDataStore store, String uid) async {
  for (final trip in await store.tripsFor(uid)) {
    if (trip.ownerUid == uid) {
      await store.deleteAlbumRecords(trip.id);
      await store.deleteTrip(trip.id);
    } else {
      // Someone else's trip: take out only what's yours, then leave.
      await store.deleteAlbumRecords(trip.id, uploaderUid: uid);
      await store.leaveTrip(trip.id, uid);
    }
  }
  await store.deleteToursBy(uid);
  await store.deleteTipsBy(uid);
  await store.deleteChallengesOf(uid);
  for (final g in await store.groupsOf(uid)) {
    g.created
        ? await store.deleteGroup(g.id)
        : await store.leaveGroup(g.id, uid);
  }
  for (final m in await store.meetupsOf(uid)) {
    m.created
        ? await store.deleteMeetup(m.id)
        : await store.leaveMeetup(m.id, uid);
  }
  await store.deleteAvatar(uid);
  await store.deleteSocialData(uid);
}

/// [AccountDataStore] on Firestore and Firebase Storage.
class FirestoreAccountDataStore implements AccountDataStore {
  FirestoreAccountDataStore(this._db, this._storage, this._social);

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final SocialRepository _social;

  /// Deletes every document [query] finds, in batches.
  Future<void> _deleteAll(Query<Map<String, dynamic>> query) async {
    while (true) {
      final snap = await query.limit(300).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < 300) return;
    }
  }

  @override
  Future<List<({String id, String ownerUid})>> tripsFor(String uid) async {
    final snap = await _db
        .collection('trip_plans')
        .where('memberUids', arrayContains: uid)
        .get();
    return [
      for (final doc in snap.docs)
        (id: doc.id, ownerUid: doc.data()['ownerUid'] as String? ?? ''),
    ];
  }

  @override
  Future<void> deleteAlbumRecords(String tripId, {String? uploaderUid}) {
    Query<Map<String, dynamic>> q = _db
        .collection('trip_plans')
        .doc(tripId)
        .collection('photos');
    if (uploaderUid != null) {
      q = q.where('uploaderUid', isEqualTo: uploaderUid);
    }
    return _deleteAll(q);
  }

  @override
  Future<void> deleteTrip(String tripId) =>
      _db.collection('trip_plans').doc(tripId).delete();

  @override
  Future<void> leaveTrip(String tripId, String uid) =>
      _db.collection('trip_plans').doc(tripId).update({
        'memberUids': FieldValue.arrayRemove([uid]),
      });

  @override
  Future<void> deleteToursBy(String uid) => _deleteAll(
    _db.collection('curated_tours').where('creatorUid', isEqualTo: uid),
  );

  @override
  Future<void> deleteTipsBy(String uid) =>
      _deleteAll(_db.collectionGroup('tips').where('uid', isEqualTo: uid));

  @override
  Future<void> deleteChallengesOf(String uid) async {
    final challenges = _db.collection('friend_challenges');
    await _deleteAll(challenges.where('challengerUid', isEqualTo: uid));
    await _deleteAll(challenges.where('challengedUid', isEqualTo: uid));
  }

  Future<List<({String id, bool created})>> _joinedOrCreated(
    String collection,
    String uid,
  ) async {
    final c = _db.collection(collection);
    final created = await c.where('createdBy', isEqualTo: uid).get();
    final joined = await c.where('memberUids', arrayContains: uid).get();
    final byId = <String, bool>{
      for (final d in joined.docs) d.id: false,
      for (final d in created.docs) d.id: true,
    };
    return [for (final e in byId.entries) (id: e.key, created: e.value)];
  }

  @override
  Future<List<({String id, bool created})>> groupsOf(String uid) =>
      _joinedOrCreated('groups', uid);

  @override
  Future<void> deleteGroup(String id) => _social.deleteGroup(id);

  @override
  Future<void> leaveGroup(String id, String uid) => _social.leaveGroup(id, uid);

  @override
  Future<List<({String id, bool created})>> meetupsOf(String uid) =>
      _joinedOrCreated('group_adventures', uid);

  @override
  Future<void> deleteMeetup(String id) => _social.deleteGroupAdventure(id);

  @override
  Future<void> leaveMeetup(String id, String uid) =>
      _social.leaveGroupAdventure(id, uid);

  @override
  Future<void> deleteAvatar(String uid) async {
    try {
      await _storage.ref().child('avatars').child('$uid.jpg').delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow; // no photo: nothing to do
    }
  }

  @override
  Future<void> deleteSocialData(String uid) => _social.deleteAllDataFor(uid);
}

final accountDataStoreProvider = Provider<AccountDataStore>((ref) {
  return FirestoreAccountDataStore(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
    ref.watch(socialRepositoryProvider),
  );
});
