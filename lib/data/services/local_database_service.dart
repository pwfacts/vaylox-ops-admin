import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  static Database? _database;

  factory LocalDatabaseService() => _instance;

  LocalDatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final docsDir = await getDatabasesPath();
    final path = p.join(docsDir, 'jds_offline.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE offline_attendance_queue (
        id TEXT PRIMARY KEY,
        guard_id TEXT NOT NULL,
        attendance_data TEXT NOT NULL,
        device_id TEXT NOT NULL,
        offline_created_at TEXT NOT NULL,
        sync_status TEXT DEFAULT 'PENDING',
        sync_error TEXT,
        synced_at TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  Future<void> insertAttendance(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('offline_attendance_queue', {
      'id': const Uuid().v4(),
      'guard_id': data['guard_id'],
      'attendance_data': jsonEncode(data),
      'device_id': data['device_id'] ?? 'unknown',
      'offline_created_at': DateTime.now().toIso8601String(),
      'sync_status': 'PENDING',
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSync() async {
    final db = await database;
    return await db.query(
      'offline_attendance_queue',
      where: 'sync_status = ?',
      whereArgs: ['PENDING'],
    );
  }

  Future<void> updateSyncStatus(String id, String status, {String? error}) async {
    final db = await database;
    await db.update(
      'offline_attendance_queue',
      {
        'sync_status': status,
        'sync_error': error,
        'synced_at': status == 'SYNCED' ? DateTime.now().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
