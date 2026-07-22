import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import '../models/gps_fix.dart';

/// Durable outbox for GPS fixes.
///
/// The previous build buffered fixes in memory: kill the app in a coverage
/// blackspot and the trip's positions were gone. The spec's whole premise is
/// that the phone loses signal mid-route, so the buffer has to outlive the
/// process.
///
/// This is an outbox, not a cache — rows are deleted only once the backend has
/// acknowledged them. A fix is therefore sent at least once and possibly twice
/// (crash after the 202, before the delete). That is the right trade: the
/// backend keys each fix by its Redis stream id and re-indexes idempotently,
/// so a duplicate is free, whereas a lost fix is a hole in the route.
class GpsQueue {
  GpsQueue._(this._db);

  final Database _db;

  static const String _table = 'gps_outbox';

  /// Hard ceiling on stored fixes. At 1 fix/5 s a full day is ~17k rows, so
  /// this holds well over a day of total blackout. Beyond it the *oldest* go
  /// first: for live tracking a recent position is worth more than an old one.
  static const int maxRows = 20000;

  static Future<GpsQueue> open() async {
    final path = p.join(await getDatabasesPath(), 'unitrack_gps.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            trip_id  TEXT,
            lat      REAL    NOT NULL,
            lng      REAL    NOT NULL,
            ts       TEXT    NOT NULL,
            speed    REAL,
            heading  REAL,
            accuracy REAL
          )
        ''');
      },
    );
    return GpsQueue._(db);
  }

  Future<void> close() => _db.close();

  /// Appends one fix. Called from the location stream, so it stays a single
  /// insert rather than a transaction.
  Future<void> add(GpsFix fix, {String? tripId}) async {
    await _db.insert(_table, {
      'trip_id': tripId,
      'lat': fix.lat,
      'lng': fix.lng,
      'ts': fix.ts.toUtc().toIso8601String(),
      'speed': fix.speed,
      'heading': fix.heading,
      'accuracy': fix.accuracy,
    });
    await _enforceCeiling();
  }

  /// Oldest fixes first — the backend wants a trip's path in order, and sending
  /// newest-first would make a partial upload look like the bus drove backwards.
  Future<List<QueuedFix>> peek([int limit = AppConfig.maxBatchSize]) async {
    final rows = await _db.query(_table, orderBy: 'id ASC', limit: limit);
    return rows.map(QueuedFix.fromRow).toList();
  }

  /// Deletes an acknowledged batch. Ranged delete rather than an `IN (...)`
  /// list: ids are monotonic and `peek` returns a contiguous prefix, so this is
  /// one indexed range scan instead of a 50-term predicate.
  Future<void> ackThrough(int lastId) async {
    await _db.delete(_table, where: 'id <= ?', whereArgs: [lastId]);
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $_table')) ?? 0;

  /// Clears the outbox. Used when a trip ends, so a stale queue cannot leak
  /// into the next trip and attribute one route's positions to another.
  Future<void> clear() async => _db.delete(_table);

  Future<void> _enforceCeiling() async {
    final total = await count();
    if (total <= maxRows) return;
    final excess = total - maxRows;
    await _db.rawDelete(
      'DELETE FROM $_table WHERE id IN '
      '(SELECT id FROM $_table ORDER BY id ASC LIMIT ?)',
      [excess],
    );
  }
}

class QueuedFix {
  const QueuedFix({required this.id, required this.tripId, required this.fix});

  final int id;
  final String? tripId;
  final GpsFix fix;

  factory QueuedFix.fromRow(Map<String, Object?> row) => QueuedFix(
    id: row['id']! as int,
    tripId: row['trip_id'] as String?,
    fix: GpsFix(
      lat: row['lat']! as double,
      lng: row['lng']! as double,
      ts: DateTime.parse(row['ts']! as String),
      speed: row['speed'] as double?,
      heading: row['heading'] as double?,
      accuracy: row['accuracy'] as double?,
    ),
  );
}
