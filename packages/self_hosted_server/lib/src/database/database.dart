import 'dart:convert';
import 'dart:io';

/// Simple in-memory database with optional file persistence.
/// Perfect for development and testing.
/// For production, replace with PostgreSQL.
class Database {
  Database._();

  static Database? _instance;

  /// Get the singleton instance of the database.
  static Database get instance => _instance ??= Database._();

  final Map<String, List<Map<String, dynamic>>> _tables = {};
  final Map<String, int> _autoIncrements = {};
  String? _persistPath;

  /// Initialize the database.
  /// If [persistPath] is provided, data will be persisted to that file.
  void initialize([String? persistPath]) {
    _persistPath = persistPath;
    _initializeTables();
    if (_persistPath != null) {
      _loadFromFile();
    }
  }

  void _initializeTables() {
    _tables['users'] = [];
    _tables['organizations'] = [];
    _tables['organization_members'] = [];
    _tables['apps'] = [];
    _tables['channels'] = [];
    _tables['releases'] = [];
    _tables['release_platform_statuses'] = [];
    _tables['release_artifacts'] = [];
    _tables['patches'] = [];
    _tables['patch_artifacts'] = [];
    _tables['channel_patches'] = [];

    for (final table in _tables.keys) {
      _autoIncrements[table] = 1;
    }
  }

  void _loadFromFile() {
    if (_persistPath == null) return;
    final file = File(_persistPath!);
    if (file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final data = jsonDecode(content) as Map<String, dynamic>;
        for (final entry in data.entries) {
          if (entry.key == '_autoIncrements') {
            final autoInc = entry.value as Map<String, dynamic>;
            for (final ai in autoInc.entries) {
              _autoIncrements[ai.key] = ai.value as int;
            }
          } else {
            _tables[entry.key] = (entry.value as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        }
      } catch (e) {
        // If loading fails, start fresh
        _initializeTables();
      }
    }
  }

  void _saveToFile() {
    if (_persistPath == null) return;
    final file = File(_persistPath!);
    final data = Map<String, dynamic>.from(_tables);
    data['_autoIncrements'] = _autoIncrements;
    file.writeAsStringSync(jsonEncode(data));
  }

  /// Insert a row into a table.
  int insert(String table, Map<String, dynamic> data) {
    if (!_tables.containsKey(table)) {
      throw ArgumentError('Table $table does not exist');
    }

    final id = _autoIncrements[table]!;
    _autoIncrements[table] = id + 1;

    final row = Map<String, dynamic>.from(data);
    row['id'] = id;
    row['created_at'] ??= DateTime.now().toIso8601String();
    row['updated_at'] ??= DateTime.now().toIso8601String();

    _tables[table]!.add(row);
    _saveToFile();
    return id;
  }

  /// Insert a row with a custom ID (for string IDs like app_id).
  void insertWithId(String table, Map<String, dynamic> data) {
    if (!_tables.containsKey(table)) {
      throw ArgumentError('Table $table does not exist');
    }

    final row = Map<String, dynamic>.from(data);
    row['created_at'] ??= DateTime.now().toIso8601String();
    row['updated_at'] ??= DateTime.now().toIso8601String();

    _tables[table]!.add(row);
    _saveToFile();
  }

  /// Select rows from a table.
  List<Map<String, dynamic>> select(
    String table, {
    Map<String, dynamic>? where,
  }) {
    if (!_tables.containsKey(table)) {
      throw ArgumentError('Table $table does not exist');
    }

    var rows = _tables[table]!;

    if (where != null) {
      rows = rows.where((row) {
        for (final entry in where.entries) {
          if (row[entry.key] != entry.value) {
            return false;
          }
        }
        return true;
      }).toList();
    }

    return rows.map(Map<String, dynamic>.from).toList();
  }

  /// Select a single row from a table.
  Map<String, dynamic>? selectOne(
    String table, {
    required Map<String, dynamic> where,
  }) {
    final rows = select(table, where: where);
    return rows.isEmpty ? null : rows.first;
  }

  /// Update rows in a table.
  int update(
    String table, {
    required Map<String, dynamic> data,
    required Map<String, dynamic> where,
  }) {
    if (!_tables.containsKey(table)) {
      throw ArgumentError('Table $table does not exist');
    }

    var count = 0;
    for (final row in _tables[table]!) {
      var matches = true;
      for (final entry in where.entries) {
        if (row[entry.key] != entry.value) {
          matches = false;
          break;
        }
      }
      if (matches) {
        for (final entry in data.entries) {
          row[entry.key] = entry.value;
        }
        row['updated_at'] = DateTime.now().toIso8601String();
        count++;
      }
    }

    if (count > 0) {
      _saveToFile();
    }
    return count;
  }

  /// Delete rows from a table.
  int delete(
    String table, {
    required Map<String, dynamic> where,
  }) {
    if (!_tables.containsKey(table)) {
      throw ArgumentError('Table $table does not exist');
    }

    final initialLength = _tables[table]!.length;
    _tables[table]!.removeWhere((row) {
      for (final entry in where.entries) {
        if (row[entry.key] != entry.value) {
          return false;
        }
      }
      return true;
    });

    final count = initialLength - _tables[table]!.length;
    if (count > 0) {
      _saveToFile();
    }
    return count;
  }

  /// Count rows in a table.
  int count(String table, {Map<String, dynamic>? where}) {
    return select(table, where: where).length;
  }

  /// Get the next patch number for a release.
  int getNextPatchNumber(int releaseId) {
    final patches = select('patches', where: {'release_id': releaseId});
    if (patches.isEmpty) return 1;

    final maxNumber =
        patches.map((p) => p['number'] as int).reduce((a, b) => a > b ? a : b);
    return maxNumber + 1;
  }

  /// Close and optionally persist the database.
  void close() {
    _saveToFile();
  }

  /// Clear all data (for testing).
  void clear() {
    _initializeTables();
    _saveToFile();
  }
}
