import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_service.dart';
import '../domain/adventure_session.dart';
import '../domain/checkpoint.dart';
import '../domain/directions.dart';
import '../domain/route_point.dart';

final adventureRepositoryProvider = Provider<AdventureRepository>((ref) {
  return AdventureRepository(ref.watch(databaseServiceProvider));
});

/// Places the user has reached on a trip; the map colours them. Refreshed
/// by the tracking service whenever a trip reaches a place.
final visitedPlaceIdsProvider = FutureProvider<Set<String>>((ref) {
  return ref.watch(adventureRepositoryProvider).getVisitedPlaceIds();
});

class AdventureRepository {
  AdventureRepository(this._databaseService);

  final DatabaseService _databaseService;

  Future<void> createAdventure(AdventureSession session) async {
    final db = await _databaseService.database;
    await db.insert('adventures', session.toMap());
  }

  /// Saves a new trip and its checkpoints together: if the checkpoints can't
  /// be saved, the trip isn't either, so no half-made trip is left behind.
  Future<void> createAdventureWithCheckpoints(
    AdventureSession session,
    List<Checkpoint> checkpoints,
  ) async {
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      await txn.insert('adventures', session.toMap());
      for (final checkpoint in checkpoints) {
        await txn.insert('checkpoints', checkpoint.toMap());
      }
    });
  }

  /// Deletes trips that were started but never recorded anything: still
  /// "active", no route points, no distance, no XP, and older than
  /// [olderThan]. These are left by starts that failed part-way. Returns how
  /// many were removed.
  Future<int> removeEmptyAbandonedTrips({
    Duration olderThan = const Duration(minutes: 5),
  }) async {
    final db = await _databaseService.database;
    final cutoff = DateTime.now().subtract(olderThan).toIso8601String();
    return db.delete(
      'adventures',
      where:
          "status = 'active' AND distance_meters = 0 AND xp_earned = 0 "
          'AND started_at < ? '
          'AND NOT EXISTS (SELECT 1 FROM route_points '
          'WHERE route_points.adventure_id = adventures.id)',
      whereArgs: [cutoff],
    );
  }

  Future<void> updateAdventure(AdventureSession session) async {
    final db = await _databaseService.database;
    await db.update(
      'adventures',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> insertCheckpoints(List<Checkpoint> checkpoints) async {
    final db = await _databaseService.database;
    final batch = db.batch();
    for (final checkpoint in checkpoints) {
      batch.insert('checkpoints', checkpoint.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> markCheckpointReached(Checkpoint checkpoint) async {
    final db = await _databaseService.database;
    await db.update(
      'checkpoints',
      {'reached_at': checkpoint.reachedAt?.toIso8601String()},
      where: 'id = ?',
      whereArgs: [checkpoint.id],
    );
  }

  Future<List<Checkpoint>> getCheckpoints(String adventureId) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'checkpoints',
      where: 'adventure_id = ?',
      whereArgs: [adventureId],
      orderBy: 'order_index ASC',
    );
    return rows.map(Checkpoint.fromMap).toList();
  }

  Future<void> addRoutePoint(RoutePoint point) async {
    final db = await _databaseService.database;
    await db.insert('route_points', point.toMap());
  }

  Future<List<RoutePoint>> getRoutePoints(String adventureId) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'route_points',
      where: 'adventure_id = ?',
      whereArgs: [adventureId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(RoutePoint.fromMap).toList();
  }

  Future<void> recordXp({
    required int amount,
    required String reason,
    String? adventureId,
  }) async {
    final db = await _databaseService.database;
    await db.insert('xp_transactions', {
      'amount': amount,
      'reason': reason,
      'adventure_id': adventureId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Whether an XP payment with exactly this [reason] was recorded since
  /// [since]. Used to pay a place's XP only once in a while.
  Future<bool> hasXpReasonSince(String reason, DateTime since) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'xp_transactions',
      columns: ['id'],
      where: 'reason = ? AND created_at >= ?',
      whereArgs: [reason, since.toIso8601String()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// XP earned on trips (not achievement claims) since [since]: the daily
  /// cap counts this.
  Future<int> tripXpSince(DateTime since) async {
    final db = await _databaseService.database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM xp_transactions '
      'WHERE adventure_id IS NOT NULL AND created_at >= ?',
      [since.toIso8601String()],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<List<AdventureSession>> getRecentAdventures({int limit = 10}) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'adventures',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(AdventureSession.fromMap).toList();
  }

  Future<AdventureSession?> getAdventureById(String id) async {
    final db = await _databaseService.database;
    final rows = await db.query('adventures', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return AdventureSession.fromMap(rows.first);
  }

  /// Trips started between [from] and [to], with a day's slack either side
  /// (times may be stored in local time or UTC): callers group by local day.
  Future<List<AdventureSession>> getAdventuresBetween(
    DateTime from,
    DateTime to,
  ) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'adventures',
      where: "started_at >= ? AND started_at < ? AND status != 'discarded'",
      whereArgs: [
        from.subtract(const Duration(days: 1)).toIso8601String(),
        to.add(const Duration(days: 1)).toIso8601String(),
      ],
      orderBy: 'started_at ASC',
    );
    return rows.map(AdventureSession.fromMap).toList();
  }

  Future<List<AdventureSession>> getAdventuresByTitle(String title) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'adventures',
      where: 'title = ?',
      whereArgs: [title],
      orderBy: 'started_at DESC',
    );
    return rows.map(AdventureSession.fromMap).toList();
  }

  Future<List<AdventureSession>> getCompletedAdventures() async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'adventures',
      where: 'status = ?',
      whereArgs: [AdventureStatus.completed.name],
      orderBy: 'started_at DESC',
    );
    return rows.map(AdventureSession.fromMap).toList();
  }

  Future<int> getTotalXp() async {
    final db = await _databaseService.database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM xp_transactions',
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> getWeeklyXp([DateTime? sinceMonday]) async {
    final monday = sinceMonday ?? currentWeekMonday();
    final db = await _databaseService.database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM xp_transactions WHERE created_at >= ?',
      [monday.toIso8601String()],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  static DateTime currentWeekMonday([DateTime? now]) {
    final d = now ?? DateTime.now();
    final daysFromMonday = (d.weekday - DateTime.monday) % 7;
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).subtract(Duration(days: daysFromMonday));
  }

  static String currentWeekKey([DateTime? now]) {
    final m = currentWeekMonday(now);
    return '${m.year}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
  }

  Future<int> getTotalReachedCheckpoints() async {
    final db = await _databaseService.database;
    final result = await db.rawQuery(
      // Distinct places on completed trips only: a place visited five times
      // counts once, and a trip that failed the checks counts for nothing.
      'SELECT COUNT(DISTINCT c.name) AS total FROM checkpoints c '
      'JOIN adventures a ON a.id = c.adventure_id '
      "WHERE c.reached_at IS NOT NULL AND a.status = 'completed'",
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Ids of the places the user has reached on a trip (arrival confirmed by
  /// the live photo). Trips in progress count; trips that failed the checks
  /// or were thrown away don't.
  Future<Set<String>> getVisitedPlaceIds() async {
    final db = await _databaseService.database;
    final rows = await db.rawQuery(
      'SELECT c.id FROM checkpoints c '
      'JOIN adventures a ON a.id = c.adventure_id '
      'WHERE c.reached_at IS NOT NULL AND a.status NOT IN (?, ?)',
      [AdventureStatus.discarded.name, AdventureStatus.unverified.name],
    );
    return {
      for (final row in rows) ?placeIdFromCheckpointId(row['id'] as String),
    };
  }

  /// The place id inside a destination checkpoint id
  /// (`dest-<placeId>@<tripId>`), or null for other checkpoints.
  static String? placeIdFromCheckpointId(String checkpointId) {
    if (!checkpointId.startsWith(Destination.checkpointIdPrefix)) return null;
    final rest = checkpointId.substring(Destination.checkpointIdPrefix.length);
    final at = rest.lastIndexOf('@');
    final placeId = at < 0 ? rest : rest.substring(0, at);
    return placeId.isEmpty ? null : placeId;
  }

  Future<List<List<RoutePoint>>> getAllCompletedRoutePaths() async {
    final db = await _databaseService.database;
    final adventures = await db.query(
      'adventures',
      where: 'status = ?',
      whereArgs: [AdventureStatus.completed.name],
    );

    final List<List<RoutePoint>> allPaths = [];
    for (final adv in adventures) {
      final id = adv['id'] as String;
      final rows = await db.query(
        'route_points',
        where: 'adventure_id = ?',
        whereArgs: [id],
        orderBy: 'timestamp ASC',
      );
      if (rows.isNotEmpty) {
        allPaths.add(rows.map(RoutePoint.fromMap).toList());
      }
    }
    return allPaths;
  }

  Future<void> deleteAdventure(String id) async {
    final db = await _databaseService.database;
    await db.delete('adventures', where: 'id = ?', whereArgs: [id]);
  }
}
