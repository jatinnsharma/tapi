import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_service.dart';
import '../domain/memory_model.dart';

final memoryRepositoryProvider = Provider<MemoryRepository>((ref) {
  return MemoryRepository(ref.watch(databaseServiceProvider));
});

class MemoryRepository {
  MemoryRepository(this._databaseService);

  final DatabaseService _databaseService;

  Future<void> saveMemory(Memory memory) async {
    final db = await _databaseService.database;
    await db.insert('memories', memory.toMap());
  }

  Future<List<Memory>> getByAdventure(String adventureId) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'memories',
      where: 'adventure_id = ?',
      whereArgs: [adventureId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(Memory.fromMap).toList();
  }

  Future<List<Memory>> getAll({int limit = 50}) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'memories',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(Memory.fromMap).toList();
  }

  /// Memories made between [from] and [to], with a day's slack either side
  /// (times may be stored in local time or UTC): callers group by local day.
  Future<List<Memory>> getBetween(DateTime from, DateTime to) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'memories',
      where: 'timestamp >= ? AND timestamp < ?',
      whereArgs: [
        from.subtract(const Duration(days: 1)).toIso8601String(),
        to.add(const Duration(days: 1)).toIso8601String(),
      ],
      orderBy: 'timestamp ASC',
    );
    return rows.map(Memory.fromMap).toList();
  }

  /// Saves new sharing details (or clears them) and/or a caption.
  Future<void> updateMemory(Memory memory) async {
    final db = await _databaseService.database;
    await db.update(
      'memories',
      memory.toMap(),
      where: 'id = ?',
      whereArgs: [memory.id],
    );
  }

  Future<void> deleteMemory(String id) async {
    final db = await _databaseService.database;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }
}
