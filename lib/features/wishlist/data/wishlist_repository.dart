import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_service.dart';
import '../domain/wishlist_entry.dart';

final wishlistRepositoryProvider = Provider<WishlistRepository>((ref) {
  return WishlistRepository(ref.watch(databaseServiceProvider));
});

class WishlistRepository {
  WishlistRepository(this._databaseService);

  final DatabaseService _databaseService;

  Future<List<WishlistEntry>> getAll() async {
    final db = await _databaseService.database;
    final rows = await db.query('wishlist', orderBy: 'added_at DESC');
    return rows.map(WishlistEntry.fromMap).toList();
  }

  Future<bool> isSaved(WishlistType type, String targetId) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'wishlist',
      where: 'target_type = ? AND target_id = ?',
      whereArgs: [type.name, targetId],
    );
    return rows.isNotEmpty;
  }

  Future<void> add(WishlistType type, String targetId) async {
    final db = await _databaseService.database;
    await db.insert(
      'wishlist',
      WishlistEntry(
        type: type,
        targetId: targetId,
        addedAt: DateTime.now(),
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(WishlistType type, String targetId) async {
    final db = await _databaseService.database;
    await db.delete(
      'wishlist',
      where: 'target_type = ? AND target_id = ?',
      whereArgs: [type.name, targetId],
    );
  }

  Future<bool> toggle(WishlistType type, String targetId) async {
    final saved = await isSaved(type, targetId);
    if (saved) {
      await remove(type, targetId);
      return false;
    }
    await add(type, targetId);
    return true;
  }
}
