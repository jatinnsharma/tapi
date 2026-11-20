import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../../../core/services/firebase_status.dart';
import '../../auth/application/auth_service.dart';
import '../domain/trip_plan.dart';
import 'trip_cloud_repository.dart';
import '../domain/plan_merge.dart';
import 'trip_base_store.dart';

final savedTripsRepositoryProvider = Provider<SavedTripsRepository>((ref) {
  return SavedTripsRepository(ref.watch(databaseServiceProvider));
});

/// The signed-in user's uid, or null when signed out or Firebase isn't set up
/// (trips then stay on this phone only).
final tripSyncUidProvider = Provider<String?>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return null;
  return ref.watch(authStateProvider).value?.uid;
});

/// Live cloud copy of a shared trip, so edits by a fellow traveller show up
/// while the itinerary is open. Emits nothing useful when signed out.
final cloudTripProvider = StreamProvider.autoDispose.family<TripPlan?, String>((
  ref,
  id,
) {
  if (ref.watch(tripSyncUidProvider) == null) return Stream.value(null);
  return ref.watch(tripCloudRepositoryProvider).watchTrip(id);
});

/// Saved trips. The local database is always the source the screens read, so
/// trips work offline and without an account. When signed in, the list is
/// merged with the cloud on load (newer copy wins) and every change is
/// uploaded in the background; an upload that fails is retried on the next
/// load.
///
/// No screen ever waits on the cloud: Firestore only confirms a write once
/// its server has it, which never happens offline or before the Firestore
/// database is created. So saves return as soon as the phone has the trip,
/// and every cloud call has a time limit.
class SavedTripsNotifier extends AsyncNotifier<List<TripPlan>> {
  static const _pendingDeletesKey = 'trip_plans_pending_deletes_v1';

  /// How long any one cloud call may take before we give up on it for now.
  static const cloudTimeout = Duration(seconds: 10);

  SavedTripsRepository get _local => ref.read(savedTripsRepositoryProvider);
  TripBaseStore get _bases => ref.read(tripBaseStoreProvider);
  TripCloudRepository get _cloud => ref.read(tripCloudRepositoryProvider);
  String? get _uid => ref.read(tripSyncUidProvider);

  @override
  Future<List<TripPlan>> build() async {
    final uid = ref.watch(tripSyncUidProvider);
    final local = await _local.getAllTrips();
    if (uid == null) return local;
    try {
      return await _sync(uid, local);
    } catch (_) {
      return local; // Offline or Firestore not set up: show what we have.
    }
  }

  /// Pulls the latest from the cloud (pull-to-refresh).
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<List<TripPlan>> _sync(String uid, List<TripPlan> local) async {
    await _flushPendingDeletes(uid);
    final remoteById = {
      for (final trip in await _cloud.getTripsFor(uid).timeout(cloudTimeout))
        trip.id: trip,
    };

    final result = <TripPlan>[];
    for (final trip in local) {
      final remote = remoteById.remove(trip.id);
      if (remote == null) {
        if (trip.cloudSynced) {
          // Was in the cloud and isn't now: deleted on another device, or
          // its owner stopped sharing it with this user.
          await _local.deleteTrip(trip.id);
          await _bases.remove(trip.id);
        } else {
          result.add(await _push(_claim(trip, uid)));
        }
        continue;
      }
      final base = await _bases.get(trip.id);
      final editedHere = base == null
          ? trip.lastChanged.isAfter(remote.lastChanged)
          : !sameTripContent(trip, base);
      if (editedHere) {
        // Edited on this phone and not uploaded yet (offline). Merge with
        // the cloud's copy, which may hold a friend's edits since.
        final merged = base == null
            ? trip.copyWith(
                ownerUid: remote.ownerUid,
                memberUids: remote.memberUids,
              )
            : mergePlans(
                base: base,
                local: trip,
                remote: remote,
                savedByOwner: trip.isOwnedBy(uid),
              );
        await _bases.set(remote);
        result.add(await _push(merged));
      } else {
        await _local.saveTrip(remote);
        await _bases.set(remote);
        result.add(remote);
      }
    }
    // Trips from another device, or shared by a friend.
    for (final remote in remoteById.values) {
      await _local.saveTrip(remote);
      await _bases.set(remote);
      result.add(remote);
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// Makes a trip that has never been uploaded the user's own.
  TripPlan _claim(TripPlan trip, String uid) => trip.copyWith(
    ownerUid: trip.ownerUid ?? uid,
    memberUids: trip.memberUids.isEmpty ? [uid] : trip.memberUids,
  );

  /// Saves locally and starts the upload without waiting for it; returns the
  /// local copy. A failed upload leaves the trip local-only until the next
  /// sync.
  Future<TripPlan> _push(TripPlan trip) async {
    await _local.saveTrip(trip);
    unawaited(_upload(trip));
    return trip;
  }

  /// Uploads [trip] merged with any friend's edit since the last cloud copy
  /// this phone saw, then keeps the merged result (their edits included).
  Future<void> _upload(TripPlan trip) async {
    final TripPlan stored;
    try {
      final uid = _uid;
      stored = await _cloud
          .saveMerged(
            trip,
            base: await _bases.get(trip.id),
            savedByOwner: uid != null && trip.isOwnedBy(uid),
          )
          .timeout(cloudTimeout);
    } catch (_) {
      return; // Offline or Firestore not set up yet: retried on next sync.
    }
    try {
      await _bases.set(stored);
      // Keep the stored copy, unless the trip changed again meanwhile.
      final current = await _local.getTrip(trip.id);
      if (current == null || current.lastChanged != trip.lastChanged) return;
      await _local.saveTrip(stored);
      if (ref.mounted && state.hasValue) _replaceInState(stored);
    } catch (_) {}
  }

  void _replaceInState(TripPlan plan) {
    final current = state.value;
    if (current == null) {
      // Still loading (or failed): reload rather than show a partial list.
      ref.invalidateSelf();
      return;
    }
    final updated = [
      plan,
      for (final t in current)
        if (t.id != plan.id) t,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    state = AsyncData(updated);
  }

  /// Saves a new or changed trip and returns the stored copy. Callers set
  /// [TripPlan.updatedAt] when they change a trip; it's stamped here if not.
  Future<TripPlan> save(TripPlan plan) async {
    final stamped = plan.updatedAt == null
        ? plan.copyWith(updatedAt: DateTime.now())
        : plan;
    final uid = _uid;
    final TripPlan stored;
    if (uid == null) {
      await _local.saveTrip(stamped);
      stored = stamped;
    } else {
      stored = await _push(_claim(stamped, uid));
    }
    _replaceInState(stored);
    return stored;
  }

  Future<TripPlan> updatePlan(TripPlan plan) => save(plan);

  /// Stores a newer copy that arrived from the cloud, without re-uploading it.
  Future<void> applyRemote(TripPlan plan) async {
    await _local.saveTrip(plan);
    await _bases.set(plan);
    _replaceInState(plan);
  }

  /// Deletes the trip, or for a trip a friend shared, leaves it (the friend
  /// keeps their copy).
  Future<void> delete(String id) async {
    final plan = await _local.getTrip(id);
    await _local.deleteTrip(id);
    await _bases.remove(id);
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
    } else {
      state = AsyncData([
        for (final t in current)
          if (t.id != id) t,
      ]);
    }

    final uid = _uid;
    if (plan == null || !plan.cloudSynced || uid == null) return;
    // Remember it first, so the next sync can't bring the trip back if the
    // cloud call doesn't get through; cleared once it does.
    final entry = '${plan.isOwnedBy(uid) ? 'delete' : 'leave'}:$id';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pendingDeletesKey, [
      ...?prefs.getStringList(_pendingDeletesKey),
      entry,
    ]);
    unawaited(_flushPendingDeletes(uid).catchError((Object _) {}));
  }

  Future<void> _deleteInCloud(
    String id, {
    required bool leave,
    required String uid,
  }) {
    return leave ? _cloud.leaveTrip(id, uid) : _cloud.deleteTrip(id);
  }

  Future<void> _flushPendingDeletes(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingDeletesKey) ?? [];
    if (pending.isEmpty) return;
    final stillPending = <String>[];
    for (final entry in pending) {
      final split = entry.indexOf(':');
      if (split < 0) continue;
      try {
        await _deleteInCloud(
          entry.substring(split + 1),
          leave: entry.substring(0, split) == 'leave',
          uid: uid,
        ).timeout(cloudTimeout);
      } on Exception catch (e) {
        // Already gone (or no longer ours) counts as done.
        if (!e.toString().contains('not-found') &&
            !e.toString().contains('permission-denied')) {
          stillPending.add(entry);
        }
      }
    }
    await prefs.setStringList(_pendingDeletesKey, stillPending);
  }

  /// Shares an owned trip with [friendUids] (replacing who it was shared
  /// with). Needs a signed-in user and a connection; throws otherwise so the
  /// screen can say so.
  Future<TripPlan> setMembers(TripPlan plan, List<String> friendUids) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Sign in to share trips with friends.');
    }
    if (!plan.isOwnedBy(uid)) {
      throw StateError('Only the person who created this trip can share it.');
    }
    final updated = plan.copyWith(
      ownerUid: uid,
      memberUids: {uid, ...friendUids}.toList(),
      updatedAt: DateTime.now(),
    );
    try {
      await _cloud.saveTrip(updated).timeout(cloudTimeout);
    } on TimeoutException {
      throw StateError(
        'Could not reach the cloud to share this trip. Check your '
        'connection and try again.',
      );
    }
    final stored = updated.copyWith(cloudSynced: true);
    await _local.saveTrip(stored);
    _replaceInState(stored);
    return stored;
  }
}

final tripBaseStoreProvider = Provider<TripBaseStore>((_) => TripBaseStore());

/// Same trip content, ignoring whether it has reached the cloud.
bool sameTripContent(TripPlan a, TripPlan b) =>
    jsonEncode(a.copyWith(cloudSynced: false).toJson()) ==
    jsonEncode(b.copyWith(cloudSynced: false).toJson());

final savedTripsListProvider =
    AsyncNotifierProvider<SavedTripsNotifier, List<TripPlan>>(
      SavedTripsNotifier.new,
    );

class SavedTripsRepository {
  SavedTripsRepository(this._databaseService);

  final DatabaseService _databaseService;

  Future<List<TripPlan>> getAllTrips() async {
    try {
      final db = await _databaseService.database;
      final rows = await db.query('trip_plans', orderBy: 'created_at DESC');
      return rows.map((r) {
        final planJson =
            jsonDecode(r['plan_json'] as String) as Map<String, dynamic>;
        return TripPlan.fromJson(planJson);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<TripPlan?> getTrip(String id) async {
    try {
      final db = await _databaseService.database;
      final rows = await db.query(
        'trip_plans',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final planJson =
          jsonDecode(rows.first['plan_json'] as String) as Map<String, dynamic>;
      return TripPlan.fromJson(planJson);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTrip(TripPlan trip) async {
    final db = await _databaseService.database;
    await db.insert('trip_plans', {
      'id': trip.id,
      'title': trip.title,
      'destination': trip.destination,
      'city_id': trip.cityId,
      'days_count': trip.daysCount,
      'companion': trip.companion.name,
      'trip_type': 'custom',
      'pace': trip.pace.name,
      'budget': trip.budget.name,
      'interests': trip.interests.join(','),
      'start_date': trip.startDate?.toIso8601String(),
      'created_at': trip.createdAt.toIso8601String(),
      'plan_json': jsonEncode(trip.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTrip(String id) async {
    final db = await _databaseService.database;
    await db.delete('trip_plans', where: 'id = ?', whereArgs: [id]);
  }
}
