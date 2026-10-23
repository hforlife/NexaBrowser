import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../models/site_entry.dart';

/// Base SQLite locale : historique et favoris.
///
/// Les téléchargements sont enregistrés côté Android par le moteur natif
/// (ils doivent rester à jour quand l'interface est fermée).
class DatabaseService {
  static const String _fileName = 'nexa_browser.db';

  /// v2 : la table des téléchargements passe côté natif.
  static const int _version = 2;

  static const String tableHistory = 'history';
  static const String tableBookmarks = 'bookmarks';
  static const String _legacyTableDownloads = 'downloads';

  late final Database _db;

  Future<void> open() async {
    final String path = p.join(await getDatabasesPath(), _fileName);
    _db = await openDatabase(path, version: _version, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    final Batch batch = db.batch()
      ..execute('''
        CREATE TABLE $tableHistory (
          id    INTEGER PRIMARY KEY AUTOINCREMENT,
          url   TEXT NOT NULL,
          title TEXT NOT NULL DEFAULT '',
          date  INTEGER NOT NULL
        )''')
      ..execute('CREATE INDEX idx_history_date ON $tableHistory(date DESC)')
      ..execute('''
        CREATE TABLE $tableBookmarks (
          id    INTEGER PRIMARY KEY AUTOINCREMENT,
          url   TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL DEFAULT '',
          date  INTEGER NOT NULL
        )''');
    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v0.1 n'a jamais été publiée : l'ancienne file Dart est simplement supprimée
      await db.execute('DROP TABLE IF EXISTS $_legacyTableDownloads');
    }
  }

  // ------------------------------------------------------------ historique

  Future<void> addHistory(String url, String title) async {
    // Évite les doublons consécutifs (rechargements, redirections)
    final List<Map<String, Object?>> last =
        await _db.query(tableHistory, orderBy: 'date DESC', limit: 1);
    if (last.isNotEmpty && last.first['url'] == url) {
      await _db.update(
        tableHistory,
        {'title': title, 'date': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [last.first['id']],
      );
      return;
    }
    await _db.insert(
      tableHistory,
      SiteEntry(url: url, title: title, date: DateTime.now()).toMap(),
    );
    // Purge des entrées les plus anciennes au-delà de la limite
    await _db.rawDelete(
      'DELETE FROM $tableHistory WHERE id NOT IN '
      '(SELECT id FROM $tableHistory ORDER BY date DESC LIMIT ?)',
      [AppConstants.maxHistoryEntries],
    );
  }

  Future<List<SiteEntry>> history({String? search, int limit = 300}) async {
    final bool filtered = search != null && search.trim().isNotEmpty;
    final List<Map<String, Object?>> rows = await _db.query(
      tableHistory,
      where: filtered ? 'url LIKE ? OR title LIKE ?' : null,
      whereArgs: filtered ? ['%$search%', '%$search%'] : null,
      orderBy: 'date DESC',
      limit: limit,
    );
    return rows.map(SiteEntry.fromMap).toList();
  }

  Future<void> deleteHistory(int id) =>
      _db.delete(tableHistory, where: 'id = ?', whereArgs: [id]);

  Future<void> clearHistory() => _db.delete(tableHistory);

  // -------------------------------------------------------------- favoris

  Future<List<SiteEntry>> bookmarks() async {
    final List<Map<String, Object?>> rows = await _db.query(tableBookmarks, orderBy: 'date DESC');
    return rows.map(SiteEntry.fromMap).toList();
  }

  Future<bool> isBookmarked(String url) async {
    final List<Map<String, Object?>> rows =
        await _db.query(tableBookmarks, where: 'url = ?', whereArgs: [url], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> addBookmark(String url, String title) => _db.insert(
        tableBookmarks,
        SiteEntry(url: url, title: title, date: DateTime.now()).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> removeBookmark(String url) =>
      _db.delete(tableBookmarks, where: 'url = ?', whereArgs: [url]);
}
