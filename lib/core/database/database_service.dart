import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

class DatabaseService {
  static const _dbName = 'real_world_exploration.db';
  static const _dbVersion = 9;

  Database? _db;
  Future<Database>? _opening;

  /// Everyone who asks while the database is still opening waits for the same
  /// open, instead of each starting their own (slow, and they can lock).
  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    return _opening ??= _open().then(
      (db) => _db = db,
      onError: (Object e, StackTrace s) {
        _opening = null; // let the next call try again
        throw e;
      },
    );
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE locations ADD COLUMN neighborhood TEXT NOT NULL DEFAULT 'Central'",
      );
      await db.execute(
        "ALTER TABLE locations ADD COLUMN district TEXT NOT NULL DEFAULT 'New Delhi'",
      );
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE locations ADD COLUMN image_url TEXT");
    }
    if (oldVersion < 4) {
      await db.execute('''
        DELETE FROM locations WHERE id IN (
          'loc-secret-waterfall', 'loc-old-fort-ruins', 'loc-sunrise-peak', 
          'loc-pine-forest-trail', 'loc-city-skyline-view', 'loc-gateway-of-india', 
          'loc-old-clock-tower', 'loc-rock-pool', 'loc-upper-falls-viewpoint', 
          'loc-trail-water-point', 'loc-trail-rest-point', 'loc-riverside-cafe', 
          'loc-amber-fort', 'loc-hawa-mahal', 'loc-nahargarh-viewpoint', 
          'loc-jaipur-bazaar', 'loc-jal-mahal', 'loc-rock-garden', 'loc-sukhna-lake', 
          'loc-rose-garden', 'loc-fateh-burj', 'loc-mohali-stadium', 'loc-nada-sahib', 
          'loc-cactus-garden'
        )
      ''');
    }
    if (oldVersion < 5) {
      // Shared memories: the id of the online copy and who can see it.
      await db.execute('ALTER TABLE memories ADD COLUMN shared_id TEXT');
      await db.execute('ALTER TABLE memories ADD COLUMN visibility TEXT');
    }
    if (oldVersion < 6) {
      // Journey and trek, separately. Trips from before this were on foot
      // only, so all of their distance and time was trek.
      for (final column in const [
        'trek_meters REAL NOT NULL DEFAULT 0',
        'trek_seconds INTEGER NOT NULL DEFAULT 0',
        'journey_meters REAL NOT NULL DEFAULT 0',
        'journey_seconds INTEGER NOT NULL DEFAULT 0',
      ]) {
        await db.execute('ALTER TABLE adventures ADD COLUMN $column');
      }
      await db.execute(
        'UPDATE adventures SET trek_meters = distance_meters, '
        'trek_seconds = duration_seconds',
      );
    }
    if (oldVersion < 7) {
      // Step counts (older trips have none).
      await db.execute(
        'ALTER TABLE adventures ADD COLUMN steps INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE adventures ADD COLUMN trek_steps INTEGER NOT NULL '
        'DEFAULT 0',
      );
    }
    if (oldVersion < 8) {
      // Mystery location hint.
      final hasLocations = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='locations'",
      )).isNotEmpty;
      if (hasLocations) {
        await db.execute('ALTER TABLE locations ADD COLUMN mystery_hint TEXT');
      }
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE trip_plans (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          destination TEXT NOT NULL,
          city_id TEXT,
          days_count INTEGER NOT NULL,
          companion TEXT,
          trip_type TEXT,
          pace TEXT,
          budget TEXT,
          interests TEXT,
          start_date TEXT,
          created_at TEXT NOT NULL,
          plan_json TEXT NOT NULL
        )
      ''');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE user_profile (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        level INTEGER NOT NULL DEFAULT 1,
        xp INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE adventures (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        status TEXT NOT NULL,
        distance_meters REAL NOT NULL DEFAULT 0,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        xp_earned INTEGER NOT NULL DEFAULT 0,
        group_adventure_id TEXT,
        trek_meters REAL NOT NULL DEFAULT 0,
        trek_seconds INTEGER NOT NULL DEFAULT 0,
        journey_meters REAL NOT NULL DEFAULT 0,
        journey_seconds INTEGER NOT NULL DEFAULT 0,
        steps INTEGER NOT NULL DEFAULT 0,
        trek_steps INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE route_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        adventure_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        timestamp TEXT NOT NULL,
        altitude REAL,
        speed REAL,
        FOREIGN KEY (adventure_id) REFERENCES adventures (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_route_points_adventure ON route_points (adventure_id)',
    );

    await db.execute('''
      CREATE TABLE checkpoints (
        id TEXT PRIMARY KEY,
        adventure_id TEXT NOT NULL,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        radius_meters REAL NOT NULL DEFAULT 30,
        xp_reward INTEGER NOT NULL DEFAULT 50,
        reached_at TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (adventure_id) REFERENCES adventures (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_checkpoints_adventure ON checkpoints (adventure_id)',
    );

    await db.execute('''
      CREATE TABLE xp_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount INTEGER NOT NULL,
        reason TEXT NOT NULL,
        adventure_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE locations (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        difficulty TEXT,
        xp_reward INTEGER NOT NULL DEFAULT 50,
        discovered_at TEXT,
        neighborhood TEXT NOT NULL DEFAULT 'Central',
        city TEXT NOT NULL DEFAULT 'Delhi',
        district TEXT NOT NULL DEFAULT 'New Delhi',
        region TEXT NOT NULL DEFAULT 'Delhi',
        country TEXT NOT NULL DEFAULT 'India',
        image_url TEXT,
        mystery_hint TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_locations_category ON locations (category)',
    );

    await db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        adventure_id TEXT,
        latitude REAL,
        longitude REAL,
        caption TEXT,
        duration_seconds INTEGER,
        shared_id TEXT,
        visibility TEXT,
        FOREIGN KEY (adventure_id) REFERENCES adventures (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_memories_adventure ON memories (adventure_id)',
    );

    await db.execute('''
      CREATE TABLE wishlist (
        target_type TEXT NOT NULL,
        target_id TEXT NOT NULL,
        added_at TEXT NOT NULL,
        PRIMARY KEY (target_type, target_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE trip_plans (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        destination TEXT NOT NULL,
        city_id TEXT,
        days_count INTEGER NOT NULL,
        companion TEXT,
        trip_type TEXT,
        pace TEXT,
        budget TEXT,
        interests TEXT,
        start_date TEXT,
        created_at TEXT NOT NULL,
        plan_json TEXT NOT NULL
      )
    ''');
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
