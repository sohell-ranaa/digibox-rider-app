import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../config/app_constants.dart';
import '../models/location_point.dart';

class StorageService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), AppConstants.dbName);

    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create location_points table
    await db.execute('''
      CREATE TABLE location_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rider_id INTEGER,
        duty_session_id INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        speed REAL,
        bearing REAL,
        altitude REAL,
        recorded_at TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    // Create index for faster queries
    await db.execute('''
      CREATE INDEX idx_is_synced ON location_points(is_synced)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // No upgrades needed currently
    // Removed geofence_events table (feature removed)
  }

  // Save location to local database
  Future<int> saveLocation(LocationPoint location) async {
    final db = await database;
    return await db.insert('location_points', location.toLocalDb());
  }

  // Get all pending (unsynced) locations
  Future<List<LocationPoint>> getPendingLocations() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'location_points',
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'recorded_at ASC',
    );

    return maps.map((map) => LocationPoint.fromLocalDb(map)).toList();
  }

  // Mark location as synced
  Future<void> markAsSynced(int id) async {
    final db = await database;
    await db.update(
      'location_points',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Mark multiple locations as synced
  Future<void> markMultipleAsSynced(List<int> ids) async {
    if (ids.isEmpty) return;

    final db = await database;
    // Use parameterized query to prevent SQL injection
    await db.update(
      'location_points',
      {'is_synced': 1},
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  // Get count of pending locations
  Future<int> getPendingCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM location_points WHERE is_synced = 0')
    );
    return count ?? 0;
  }

  // Get total points for a session
  Future<int> getTotalPointsForSession(int sessionId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM location_points WHERE duty_session_id = ?', [sessionId])
    );
    return count ?? 0;
  }

  // Get locations by date range
  Future<List<LocationPoint>> getLocationsByDateRange(DateTime startDate, DateTime endDate) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'location_points',
      where: 'recorded_at >= ? AND recorded_at <= ?',
      whereArgs: [startDate.toIso8601String(), endDate.toIso8601String()],
      orderBy: 'recorded_at ASC',
    );

    return maps.map((map) => LocationPoint.fromLocalDb(map)).toList();
  }

  // Get locations for specific duty session (for map view)
  Future<List<LocationPoint>> getLocationsBySession(int sessionId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'location_points',
      where: 'duty_session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'recorded_at ASC',
    );

    return maps.map((map) => LocationPoint.fromLocalDb(map)).toList();
  }

  // Get today's locations (for map view - local first!)
  Future<List<LocationPoint>> getTodaysLocations() async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final List<Map<String, dynamic>> maps = await db.query(
      'location_points',
      where: 'recorded_at >= ? AND recorded_at <= ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'recorded_at ASC',
    );

    return maps.map((map) => LocationPoint.fromLocalDb(map)).toList();
  }

  // Get latest N locations (for quick map view)
  Future<List<LocationPoint>> getLatestLocations({int limit = 100}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'location_points',
      orderBy: 'recorded_at DESC',
      limit: limit,
    );

    // Reverse to get chronological order
    return maps.reversed.map((map) => LocationPoint.fromLocalDb(map)).toList();
  }

  // Get location count for session
  Future<int> getLocationCountBySession(int sessionId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM location_points WHERE duty_session_id = ?',
        [sessionId],
      ),
    );
    return count ?? 0;
  }

  // Clear old synced data (keep last 7 days only)
  Future<void> cleanupOldData() async {
    final db = await database;
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();

    await db.delete(
      'location_points',
      where: 'is_synced = 1 AND recorded_at < ?',
      whereArgs: [sevenDaysAgo],
    );
  }

  // Batch mark as synced (for bulk upload)
  Future<void> markBatchAsSynced(List<int> localIds) async {
    if (localIds.isEmpty) return;

    final db = await database;
    final batch = db.batch();

    for (var id in localIds) {
      batch.update(
        'location_points',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    await batch.commit(noResult: true);
  }
}
