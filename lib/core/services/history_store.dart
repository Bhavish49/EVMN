import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class HistoryStore {
  Database? _database;
  bool _databaseUnavailable = false;
  final List<Map<String, Object?>> _memoryEvents = [];

  Future<Database> get database async {
    if (_database != null) return _database!;
    final path = p.join(await getDatabasesPath(), 'evmn_history.db');
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE events (
          event_id INTEGER PRIMARY KEY AUTOINCREMENT,
          message_id TEXT,
          event_type TEXT NOT NULL,
          details TEXT NOT NULL,
          created_at TEXT NOT NULL
        )''');
        await db.execute(
          'CREATE INDEX events_created_at ON events(created_at)',
        );
      },
    );
    return _database!;
  }

  Future<void> add(String type, String details, {String? messageId}) async {
    final event = <String, Object?>{
      'message_id': messageId,
      'event_type': type,
      'details': details,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (_databaseUnavailable) {
        _memoryEvents.insert(0, event);
        return;
      }
      await (await database).insert('events', event);
    } catch (_) {
      _databaseUnavailable = true;
      _memoryEvents.insert(0, event);
    }
  }

  Future<List<Map<String, Object?>>> recent() async {
    try {
      if (_databaseUnavailable) return _memoryEvents.take(100).toList();
      return await (await database).query(
        'events',
        orderBy: 'event_id DESC',
        limit: 100,
      );
    } catch (_) {
      _databaseUnavailable = true;
      return _memoryEvents.take(100).toList();
    }
  }
}
