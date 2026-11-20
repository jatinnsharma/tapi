import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../domain/album_photo.dart';

/// The phone's own list of album photos and where each is in uploading.
/// It survives closing the app: photos taken offline upload later.
class AlbumQueueRepository {
  AlbumQueueRepository(this._databaseService);

  final DatabaseService _databaseService;
  final _changes = StreamController<void>.broadcast();

  /// Fires after any change, so open album screens refresh.
  Stream<void> get changes => _changes.stream;

  Future<Database> get _db => _databaseService.database;

  /// Adds a photo, or returns the one already added from the same memory to
  /// the same trip (no duplicates).
  Future<QueuedPhoto> add(QueuedPhoto photo) async {
    final db = await _db;
    if (photo.memoryId != null) {
      final existing = await db.query(
        'album_uploads',
        where: 'trip_id = ? AND memory_id = ?',
        whereArgs: [photo.tripId, photo.memoryId],
        limit: 1,
      );
      if (existing.isNotEmpty) return QueuedPhoto.fromMap(existing.first);
    }
    await db.insert('album_uploads', photo.toMap());
    _changes.add(null);
    return photo;
  }

  Future<void> save(QueuedPhoto photo) async {
    final db = await _db;
    await db.update(
      'album_uploads',
      photo.toMap(),
      where: 'id = ?',
      whereArgs: [photo.id],
    );
    _changes.add(null);
  }

  Future<void> remove(String id) async {
    final db = await _db;
    await db.delete('album_uploads', where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
  }

  Future<QueuedPhoto?> byId(String id) async {
    final db = await _db;
    final rows = await db.query(
      'album_uploads',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : QueuedPhoto.fromMap(rows.first);
  }

  /// Your photos in [tripId], newest first.
  Future<List<QueuedPhoto>> forTrip(String tripId) async {
    final db = await _db;
    final rows = await db.query(
      'album_uploads',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'taken_at DESC',
    );
    return rows.map(QueuedPhoto.fromMap).toList();
  }

  /// Your photos (any trip) that have copies in Google Drive.
  Future<List<QueuedPhoto>> withDriveCopies() async {
    final db = await _db;
    final rows = await db.query(
      'album_uploads',
      where: 'view_file_id IS NOT NULL OR thumb_file_id IS NOT NULL',
    );
    return rows.map(QueuedPhoto.fromMap).toList();
  }

  /// Photos the uploader should try now: waiting (and due), or local ones
  /// that might be uploadable now. "Uploading" ones were interrupted (the
  /// app closed mid-upload) and go again.
  Future<List<QueuedPhoto>> due(DateTime now) async {
    final db = await _db;
    final rows = await db.query(
      'album_uploads',
      where:
          "status IN ('waiting', 'uploading', 'local') "
          'AND (next_try_at IS NULL OR next_try_at <= ?)',
      whereArgs: [now.toIso8601String()],
      orderBy: 'taken_at ASC',
    );
    return rows.map(QueuedPhoto.fromMap).toList();
  }
}

final albumQueueRepositoryProvider = Provider<AlbumQueueRepository>((ref) {
  return AlbumQueueRepository(ref.watch(databaseServiceProvider));
});

/// Your photos in a trip's album, refreshed when the queue changes.
final tripQueueProvider = StreamProvider.autoDispose
    .family<List<QueuedPhoto>, String>((ref, tripId) async* {
      final repository = ref.watch(albumQueueRepositoryProvider);
      yield await repository.forTrip(tripId);
      await for (final _ in repository.changes) {
        yield await repository.forTrip(tripId);
      }
    });
