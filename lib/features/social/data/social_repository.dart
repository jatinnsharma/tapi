import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/activity_entry.dart';
import '../domain/explorer_profile.dart';
import '../domain/footprint.dart';
import '../domain/friend_challenge.dart';
import '../domain/friendship.dart';
import '../domain/group.dart';
import '../domain/group_adventure.dart';
import '../domain/group_message.dart';
import '../domain/group_safety_status.dart';
import '../domain/live_location.dart';
import '../domain/report.dart';

import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  return SocialRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseStorageProvider),
  );
});

/// Social backend: an "explorers" directory (one doc per signed-up user), a
/// mutual friend request/accept flow stored as a single `friendships` doc
/// per pair (keyed by the two uids sorted together), and an `activity` feed.
/// Friend requests need no Cloud Functions: a Firestore rule lets either
/// party create a pending request naming themselves as `requestedBy`, but
/// only the *other* party can flip it to accepted — so consent is enforced
/// by the rule, not trusted client code. The activity feed's read rule
/// similarly checks friendship status server-side rather than trusting the
/// client's `whereIn` filter. See the rules in PENDING_TASKS.md.
class SocialRepository {
  SocialRepository(this._firestore, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _explorers =>
      _firestore.collection('explorers');

  CollectionReference<Map<String, dynamic>> get _friendships =>
      _firestore.collection('friendships');

  CollectionReference<Map<String, dynamic>> get _activity =>
      _firestore.collection('activity');

  CollectionReference<Map<String, dynamic>> get _liveLocations =>
      _firestore.collection('live_locations');

  CollectionReference<Map<String, dynamic>> get _groupAdventures =>
      _firestore.collection('group_adventures');

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('groups');

  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('reports');

  CollectionReference<Map<String, dynamic>> get _footprints =>
      _firestore.collection('footprints');

  /// Exploration footprint (route history + visited places), one doc per
  /// user. Who may read it is decided server-side by the doc's own
  /// `visibility` field (see the `footprints` rule in PENDING_TASKS.md), so
  /// [getFootprint] throws a permission-denied [FirebaseException] when the
  /// owner hasn't shared it with the caller.
  Future<void> saveFootprint(Footprint footprint) {
    return _footprints.doc(footprint.uid).set(footprint.toMap());
  }

  Future<Footprint?> getFootprint(String uid) async {
    final doc = await _footprints.doc(uid).get();
    final data = doc.data();
    return data == null ? null : Footprint.fromMap(data);
  }

  /// Account deletion: removes everything this user owns that the security
  /// rules let them delete — friendships, feed posts, live location, map
  /// footprint, block and mute lists, and finally their profile. Group chat
  /// messages are immutable by design and stay (with the name they were sent
  /// under); groups and group adventures they created should be deleted
  /// from those screens first.
  Future<void> deleteAllDataFor(String uid) async {
    for (final friendship in await getFriendshipsFor(uid)) {
      await _friendships.doc(friendship.id).delete();
    }
    final posts = await _activity.where('uid', isEqualTo: uid).get();
    for (final post in posts.docs) {
      await post.reference.delete();
    }
    for (final sub in [_blockedBy(uid), _mutedBy(uid)]) {
      for (final doc in (await sub.get()).docs) {
        await doc.reference.delete();
      }
    }
    await _liveLocations.doc(uid).delete();
    await _footprints.doc(uid).delete();
    await _explorers.doc(uid).delete();
  }

  /// Creates or edits a profile. XP is deliberately not written here: the
  /// security rules only let it change through [setTotalXp] (rate-limited,
  /// with the server's clock), so a new profile starts at 0 and an existing
  /// one keeps what it has.
  Future<void> upsertProfile(ExplorerProfile profile) async {
    final doc = _explorers.doc(profile.uid);
    final data = profile.toMap()..remove('totalXp');
    if (!(await doc.get()).exists) data['totalXp'] = 0;
    await doc.set(data, SetOptions(merge: true));
  }

  Future<String> uploadAvatar(String uid, File imageFile) async {
    final ref = _storage.ref().child('avatars').child('$uid.jpg');
    await ref.putFile(imageFile);
    final url = await ref.getDownloadURL();
    await _explorers.doc(uid).update({'photoUrl': url});
    return url;
  }

  Future<ExplorerProfile?> getProfile(String uid) async {
    final doc = await _explorers.doc(uid).get();
    final data = doc.data();
    return data == null ? null : ExplorerProfile.fromMap(data);
  }

  /// The explorers with the most XP, highest first (for the global ranking).
  Future<List<ExplorerProfile>> getTopExplorersByXp({int limit = 50}) async {
    final snapshot = await _explorers
        .orderBy('totalXp', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => ExplorerProfile.fromMap(doc.data()))
        .toList();
  }

  /// The explorers with the most weekly XP, highest first.
  Future<List<ExplorerProfile>> getTopExplorersByWeeklyXp({
    int limit = 50,
  }) async {
    final snapshot = await _explorers
        .orderBy('weeklyXp', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => ExplorerProfile.fromMap(doc.data()))
        .toList();
  }

  /// How many explorers have more XP than [xp]: a global rank is this + 1.
  /// A server-side count, so it works for any number of explorers.
  Future<int> countExplorersWithMoreXp(int xp) async {
    final result = await _explorers
        .where('totalXp', isGreaterThan: xp)
        .count()
        .get();
    return result.count ?? 0;
  }

  Future<int> countExplorersWithMoreWeeklyXp(int weeklyXp) async {
    final result = await _explorers
        .where('weeklyXp', isGreaterThan: weeklyXp)
        .count()
        .get();
    return result.count ?? 0;
  }

  /// Updates the XP mirror on the user's own profile (see
  /// `ExplorerProfile.totalXp`), leaving every other field alone.
  Future<void> setTotalXp(
    String uid,
    int totalXp, {
    int? weeklyXp,
    String? weeklyKey,
  }) {
    // The server's clock, as the security rules require: they limit how fast
    // XP can grow between two of these writes.
    final data = <String, dynamic>{
      'totalXp': totalXp,
      'xpUpdatedAt': FieldValue.serverTimestamp(),
    };
    if (weeklyXp != null) data['weeklyXp'] = weeklyXp;
    if (weeklyKey != null) data['weeklyKey'] = weeklyKey;
    return _explorers.doc(uid).update(data);
  }

  Future<List<ExplorerProfile>> getAllExplorers({
    required String excludingUid,
  }) async {
    final snapshot = await _explorers.limit(100).get();
    return snapshot.docs
        .map((doc) => ExplorerProfile.fromMap(doc.data()))
        .where((profile) => profile.uid != excludingUid)
        .toList();
  }

  Future<List<Friendship>> getFriendshipsFor(String uid) async {
    final snapshot = await _friendships
        .where(
          Filter.or(
            Filter('uidA', isEqualTo: uid),
            Filter('uidB', isEqualTo: uid),
          ),
        )
        .get();
    return snapshot.docs
        .map((doc) => Friendship.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<void> sendFriendRequest(String myUid, String otherUid) {
    final id = Friendship.idFor(myUid, otherUid);
    return _friendships
        .doc(id)
        .set(
          Friendship(
            id: id,
            uidA: myUid,
            uidB: otherUid,
            status: FriendshipStatus.pending,
            requestedBy: myUid,
            createdAt: DateTime.now(),
          ).toMap(),
        );
  }

  Future<void> acceptFriendRequest(String myUid, String otherUid) {
    final id = Friendship.idFor(myUid, otherUid);
    return _friendships.doc(id).update({
      'status': FriendshipStatus.accepted.name,
    });
  }

  /// Cancels an outgoing request, declines an incoming one, or unfriends an
  /// accepted one — all the same operation: delete the shared doc.
  Future<void> removeFriendship(String myUid, String otherUid) {
    final id = Friendship.idFor(myUid, otherUid);
    return _friendships.doc(id).delete();
  }

  Future<void> postActivity(ActivityEntry entry) {
    return _activity.add(entry.toMap());
  }

  /// Feed of the signed-in user's own activity plus their accepted friends'
  /// — enforced server-side (see the Firestore rule in PENDING_TASKS.md),
  /// not just filtered on the client. `whereIn` caps at 30 values, which is
  /// generous for this app's current friend-count scale.
  Future<List<ActivityEntry>> getFeedFor(
    String myUid,
    List<String> friendUids,
  ) async {
    final uids = [myUid, ...friendUids].take(30).toList();
    final snapshot = await _activity
        .where('uid', whereIn: uids)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();
    return snapshot.docs
        .map((doc) => ActivityEntry.fromMap(doc.id, doc.data()))
        .toList();
  }

  /// Opt-in live location sharing: one doc per user, overwritten on every
  /// update. `sharing: false` (rather than deleting the doc) lets the owner
  /// stop sharing without needing a separate "am I even sharing" read — the
  /// security rule checks this flag before allowing a friend to read it.
  Future<void> updateLiveLocation(LiveLocation location) {
    return _liveLocations.doc(location.uid).set(location.toMap());
  }

  Future<void> stopLiveLocationSharing(String uid) {
    return _liveLocations.doc(uid).update({'sharing': false});
  }

  Future<List<LiveLocation>> getFriendsLiveLocations(
    List<String> friendUids,
  ) async {
    if (friendUids.isEmpty) return [];
    final snapshot = await _liveLocations
        .where(FieldPath.documentId, whereIn: friendUids.take(30).toList())
        .get();
    return snapshot.docs
        .map((doc) => LiveLocation.fromMap(doc.data()))
        .where((location) => location.sharing)
        .toList();
  }

  /// Live positions of everyone currently sharing from a session tied to
  /// this Group Adventure — not limited to friends. The query's `where`
  /// clause matches the group-membership branch of the `live_locations`
  /// read rule directly, so it's provable the same way the other list
  /// queries in this class are (see PENDING_TASKS.md).
  Future<List<LiveLocation>> getGroupLiveLocations(
    String groupAdventureId,
  ) async {
    final snapshot = await _liveLocations
        .where('groupAdventureId', isEqualTo: groupAdventureId)
        .where('sharing', isEqualTo: true)
        .get();
    return snapshot.docs
        .map((doc) => LiveLocation.fromMap(doc.data()))
        .toList();
  }

  /// Group Adventures (spec §40). Only `public`/`private` visibility is
  /// modeled (no `friends` level): a `friends`-scoped *listing* would need a
  /// `get()` friendship lookup per candidate document, which doesn't compose
  /// well with Firestore's per-query rule verification. Public adventures
  /// are discoverable by anyone; private ones only by their creator/members
  /// (e.g. shared via a direct link in a fuller product). Each query below
  /// is written so its `where` clause alone proves the matching read rule
  /// branch — no document-dependent lookups needed to authorize a list.
  Future<void> createGroupAdventure(GroupAdventure adventure) {
    return _groupAdventures.doc(adventure.id).set(adventure.toMap());
  }

  Future<List<GroupAdventure>> getPublicGroupAdventures() async {
    final snapshot = await _groupAdventures
        .where('visibility', isEqualTo: GroupAdventureVisibility.public.name)
        .orderBy('date')
        .limit(50)
        .get();
    return snapshot.docs
        .map((doc) => GroupAdventure.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<List<GroupAdventure>> getMyGroupAdventures(String uid) async {
    final created = await _groupAdventures
        .where('createdBy', isEqualTo: uid)
        .get();
    final joined = await _groupAdventures
        .where('memberUids', arrayContains: uid)
        .get();
    final byId = <String, GroupAdventure>{
      for (final doc in created.docs)
        doc.id: GroupAdventure.fromMap(doc.id, doc.data()),
      for (final doc in joined.docs)
        doc.id: GroupAdventure.fromMap(doc.id, doc.data()),
    };
    return byId.values.toList();
  }

  Future<void> joinGroupAdventure(String adventureId, String uid) {
    return _groupAdventures.doc(adventureId).update({
      'memberUids': FieldValue.arrayUnion([uid]),
    });
  }

  Future<void> leaveGroupAdventure(String adventureId, String uid) {
    return _groupAdventures.doc(adventureId).update({
      'memberUids': FieldValue.arrayRemove([uid]),
    });
  }

  Future<void> deleteGroupAdventure(String adventureId) {
    return _groupAdventures.doc(adventureId).delete();
  }

  /// Blocking (spec §38): a one-directional record under the blocker's own
  /// subcollection — no consent needed, unlike friending. Blocking also
  /// severs any existing friendship. Mutual invisibility (you also don't see
  /// someone who has blocked you) comes from [getUidsWhoBlockedMe], a
  /// `collectionGroup` query the blocked-party rule explicitly allows for
  /// just their own uid — so checking "did they block me" doesn't require
  /// reading anyone else's block list.
  CollectionReference<Map<String, dynamic>> _blockedBy(String uid) =>
      _explorers.doc(uid).collection('blocked');

  Future<void> blockUser(String myUid, String targetUid) async {
    await _blockedBy(myUid).doc(targetUid).set({
      'blockedUid': targetUid,
      'blockedAt': DateTime.now().toIso8601String(),
    });
    await removeFriendship(myUid, targetUid);
  }

  Future<void> unblockUser(String myUid, String targetUid) {
    return _blockedBy(myUid).doc(targetUid).delete();
  }

  Future<Set<String>> getBlockedUids(String myUid) async {
    final snapshot = await _blockedBy(myUid).get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  /// Uids of people who have blocked [myUid] — found via a collection-group
  /// query across everyone's `blocked` subcollections, which the Firestore
  /// rule only permits to return docs where `blockedUid == myUid`, so this
  /// can't be used to enumerate anyone else's block list.
  Future<Set<String>> getUidsWhoBlockedMe(String myUid) async {
    final snapshot = await _firestore
        .collectionGroup('blocked')
        .where('blockedUid', isEqualTo: myUid)
        .get();
    return snapshot.docs
        .map((doc) => doc.reference.parent.parent?.id)
        .whereType<String>()
        .toSet();
  }

  Future<void> reportUser({
    required String reportedUid,
    required String reportedBy,
    required String reason,
  }) {
    return _reports.add(
      UserReport(
        reportedUid: reportedUid,
        reportedBy: reportedBy,
        reason: reason,
        createdAt: DateTime.now(),
      ).toMap(),
    );
  }

  /// Muting: unlike blocking, this is a purely private preference with no
  /// effect on the other person (no severed friendship, no mutual
  /// invisibility, they're never told). It only has to hide their posts from
  /// *your* feed, so — unlike `blocked` — nobody else ever needs to read
  /// this collection; the rule is owner-only in both directions.
  CollectionReference<Map<String, dynamic>> _mutedBy(String uid) =>
      _explorers.doc(uid).collection('muted');

  Future<void> muteUser(String myUid, String targetUid) {
    return _mutedBy(myUid)
        .doc(targetUid)
        .set({'mutedAt': DateTime.now().toIso8601String()});
  }

  Future<void> unmuteUser(String myUid, String targetUid) {
    return _mutedBy(myUid).doc(targetUid).delete();
  }

  Future<Set<String>> getMutedUids(String myUid) async {
    final snapshot = await _mutedBy(myUid).get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  /// Chat, scoped to either a one-off Group Adventure or a persistent Group
  /// — both reuse their parent doc's `memberUids`/`createdBy` for access
  /// control (see the matching Firestore rules in PENDING_TASKS.md, each a
  /// single `get()` on the parent doc per request, not per message), so one
  /// generic implementation covers both rather than duplicating it.
  Future<void> sendChatMessage({
    required ChatParent parent,
    required String parentId,
    required GroupMessage message,
  }) {
    return _firestore
        .collection(parent.collectionName)
        .doc(parentId)
        .collection('messages')
        .add(message.toMap());
  }

  Stream<List<GroupMessage>> streamChatMessages({
    required ChatParent parent,
    required String parentId,
  }) {
    return _firestore
        .collection(parent.collectionName)
        .doc(parentId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupMessage.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Persistent Groups (spec §41) — unlike a Group Adventure, not tied to a
  /// single scheduled event. Same create/join/leave/delete shape and the
  /// same reasoning for skipping `friends`-scoped visibility.
  Future<void> createGroup(Group group) {
    return _groups.doc(group.id).set(group.toMap());
  }

  Future<Group?> getGroup(String groupId) async {
    final doc = await _groups.doc(groupId).get();
    final data = doc.data();
    return data == null ? null : Group.fromMap(doc.id, data);
  }

  Future<List<Group>> getPublicGroups() async {
    final snapshot = await _groups
        .where('visibility', isEqualTo: GroupVisibility.public.name)
        .limit(50)
        .get();
    return snapshot.docs
        .map((doc) => Group.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<List<Group>> getMyGroups(String uid) async {
    final created = await _groups.where('createdBy', isEqualTo: uid).get();
    final joined = await _groups.where('memberUids', arrayContains: uid).get();
    final byId = <String, Group>{
      for (final doc in created.docs) doc.id: Group.fromMap(doc.id, doc.data()),
      for (final doc in joined.docs) doc.id: Group.fromMap(doc.id, doc.data()),
    };
    return byId.values.toList();
  }

  Future<void> updateGroupSafetyStatus(
    ChatParent parent,
    String parentId,
    GroupSafetyStatus status,
  ) {
    return _firestore
        .collection(parent.collectionName)
        .doc(parentId)
        .collection('safety_statuses')
        .doc(status.uid)
        .set(status.toMap());
  }

  Stream<List<GroupSafetyStatus>> streamGroupSafetyStatuses(
    ChatParent parent,
    String parentId,
  ) {
    return _firestore
        .collection(parent.collectionName)
        .doc(parentId)
        .collection('safety_statuses')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupSafetyStatus.fromMap(doc.data()))
              .toList(),
        );
  }

  Future<void> joinGroup(String groupId, String uid) {
    return _groups.doc(groupId).update({
      'memberUids': FieldValue.arrayUnion([uid]),
    });
  }

  Future<void> leaveGroup(String groupId, String uid) {
    return _groups.doc(groupId).update({
      'memberUids': FieldValue.arrayRemove([uid]),
    });
  }

  Future<void> deleteGroup(String groupId) {
    return _groups.doc(groupId).delete();
  }

  /// Sum of every member's (including the creator's) synced `totalXp` — see
  /// `ExplorerProfile.totalXp` for why this is a denormalized copy rather
  /// than a live local read.
  Future<int> getGroupTotalXp(Group group) async {
    var total = 0;
    for (final uid in [group.createdBy, ...group.memberUids]) {
      final profile = await getProfile(uid);
      total += profile?.totalXp ?? 0;
    }
    return total;
  }

  CollectionReference<Map<String, dynamic>> get _friendChallenges =>
      _firestore.collection('friend_challenges');

  Future<void> createFriendChallenge(FriendChallenge challenge) {
    return _friendChallenges.doc(challenge.id).set(challenge.toMap());
  }

  Future<void> updateFriendChallenge(
    String challengeId,
    Map<String, dynamic> data,
  ) {
    return _friendChallenges.doc(challengeId).update(data);
  }

  Stream<List<FriendChallenge>> streamFriendChallenges(String uid) {
    return _friendChallenges
        .where('challengerUid', isEqualTo: uid)
        .snapshots()
        .asyncMap((snapA) async {
          final snapB = await _friendChallenges
              .where('challengedUid', isEqualTo: uid)
              .get();
          final all = <FriendChallenge>[];
          for (final doc in [...snapA.docs, ...snapB.docs]) {
            all.add(FriendChallenge.fromMap(doc.data(), doc.id));
          }
          all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return all;
        });
  }
}

enum ChatParent { groupAdventure, group }

extension on ChatParent {
  String get collectionName {
    switch (this) {
      case ChatParent.groupAdventure:
        return 'group_adventures';
      case ChatParent.group:
        return 'groups';
    }
  }
}
