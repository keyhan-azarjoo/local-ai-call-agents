import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Local database. One SQLite file in the app's support folder.
/// Schema changes go in [_migrations]; never edit an old step.
class Db {
  Db._(this.raw, this.path);

  final Database raw;
  final String path;

  static Future<Db> open({String? path}) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final file = path ?? p.join((await dataDir()).path, 'localailine.db');
    final db = await factory.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: _migrations.length,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, v) async {
          for (final m in _migrations) {
            await _run(d, m);
          }
        },
        onUpgrade: (d, from, to) async {
          for (final m in _migrations.sublist(from)) {
            await _run(d, m);
          }
        },
      ),
    );
    return Db._(db, file);
  }

  static Future<Directory> dataDir() async {
    final d = await getApplicationSupportDirectory();
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<void> _run(Database d, String sql) async {
    for (final stmt in sql.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      await d.execute(stmt);
    }
  }

  static const _migrations = <String>[
    '''
    CREATE TABLE users(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      username TEXT NOT NULL UNIQUE,
      role TEXT NOT NULL,
      pw_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      last_active INTEGER
    );
    CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE agents(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      role TEXT NOT NULL,
      greeting TEXT NOT NULL,
      instructions TEXT NOT NULL,
      language TEXT NOT NULL DEFAULT 'English',
      voice TEXT,
      model TEXT,
      handles TEXT NOT NULL DEFAULT 'incoming',
      enabled INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE calls(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      direction TEXT NOT NULL,
      name TEXT,
      number TEXT,
      line TEXT,
      started_at INTEGER NOT NULL,
      duration_s INTEGER NOT NULL DEFAULT 0,
      outcome TEXT NOT NULL,
      summary TEXT,
      transcript TEXT
    );
    CREATE TABLE call_tasks(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      to_name TEXT,
      number TEXT NOT NULL,
      goal TEXT NOT NULL,
      line_id INTEGER,
      agent_id INTEGER,
      status TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      result TEXT
    );
    CREATE TABLE lines(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      provider TEXT NOT NULL,
      label TEXT NOT NULL,
      number TEXT,
      config TEXT NOT NULL,
      status TEXT NOT NULL
    );
    CREATE TABLE contacts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      number TEXT NOT NULL,
      rule TEXT NOT NULL
    );
    CREATE TABLE skills(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      description TEXT NOT NULL,
      enabled INTEGER NOT NULL
    );
    CREATE TABLE mcp_servers(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      kind TEXT NOT NULL,
      target TEXT NOT NULL,
      scope TEXT NOT NULL,
      enabled INTEGER NOT NULL
    );
    CREATE TABLE knowledge(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      path TEXT NOT NULL,
      scope TEXT NOT NULL,
      status TEXT NOT NULL
    );
    CREATE TABLE automations(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      trigger TEXT NOT NULL,
      steps TEXT NOT NULL,
      enabled INTEGER NOT NULL
    );
    CREATE TABLE audit(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      at INTEGER NOT NULL,
      who TEXT NOT NULL,
      what TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE chats(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER,
      title TEXT NOT NULL,
      model TEXT,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE chat_messages(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      at INTEGER NOT NULL
    )
    ''',
    '''
    ALTER TABLE mcp_servers ADD COLUMN auth_mode TEXT NOT NULL DEFAULT 'auto';
    ALTER TABLE mcp_servers ADD COLUMN secret TEXT;
    ALTER TABLE mcp_servers ADD COLUMN status TEXT;
    ALTER TABLE mcp_servers ADD COLUMN tools TEXT;
    ALTER TABLE mcp_servers ADD COLUMN error TEXT
    ''',
    '''
    CREATE TABLE devices(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      platform TEXT NOT NULL,
      token_hash TEXT NOT NULL UNIQUE,
      created_at INTEGER NOT NULL,
      last_seen INTEGER,
      ring INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    ALTER TABLE knowledge ADD COLUMN kind TEXT NOT NULL DEFAULT 'file';
    ALTER TABLE knowledge ADD COLUMN files INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE knowledge ADD COLUMN chunks INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE knowledge ADD COLUMN indexed_at INTEGER;
    ALTER TABLE knowledge ADD COLUMN error TEXT;
    ALTER TABLE skills ADD COLUMN instructions TEXT;
    ALTER TABLE skills ADD COLUMN source_id INTEGER;
    CREATE TABLE kn_files(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_id INTEGER NOT NULL,
      path TEXT NOT NULL,
      size INTEGER NOT NULL,
      mtime INTEGER NOT NULL,
      chunks INTEGER NOT NULL DEFAULT 0,
      error TEXT,
      UNIQUE(source_id, path)
    );
    CREATE TABLE kn_chunks(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_id INTEGER NOT NULL,
      source_id INTEGER NOT NULL,
      ord INTEGER NOT NULL,
      heading TEXT,
      page INTEGER,
      text TEXT NOT NULL,
      vec BLOB
    );
    CREATE INDEX kn_chunks_file ON kn_chunks(file_id);
    CREATE VIRTUAL TABLE kn_fts USING fts5(text, heading, tokenize = 'unicode61 remove_diacritics 2')
    ''',
    '''
    CREATE TABLE tool_vecs(text TEXT PRIMARY KEY, vec BLOB NOT NULL)
    ''',
    '''
    CREATE TABLE apps(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      request TEXT NOT NULL,
      spec TEXT NOT NULL,
      port INTEGER NOT NULL,
      pin TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'stopped',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE app_rows(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      app_id INTEGER NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
      tbl TEXT NOT NULL,
      data TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE INDEX app_rows_tbl ON app_rows(app_id, tbl)
    ''',
    // Call flow: each agent says when calls should be passed to it, and what it may use.
    '''
    ALTER TABLE agents ADD COLUMN transfer_when TEXT;
    ALTER TABLE agents ADD COLUMN access TEXT
    ''',
    // What callers asked for, taken by agents: messages, bookings, orders.
    '''
    CREATE TABLE requests(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      name TEXT,
      phone TEXT,
      summary TEXT NOT NULL,
      details TEXT,
      agent TEXT,
      status TEXT NOT NULL DEFAULT 'new',
      created_at INTEGER NOT NULL
    )
    ''',
    // Calls can be recorded (both sides, a WAV on this computer).
    'ALTER TABLE calls ADD COLUMN recording TEXT',
  ];

  // ---------- settings ----------
  Future<String?> setting(String key) async {
    final r = await raw.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) =>
      raw.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  // ---------- generic ----------
  Future<List<Map<String, Object?>>> all(String table, {String? orderBy, String? where, List<Object?>? args}) =>
      raw.query(table, orderBy: orderBy ?? 'id DESC', where: where, whereArgs: args);

  Future<int> insert(String table, Map<String, Object?> row) => raw.insert(table, row);

  Future<void> update(String table, int id, Map<String, Object?> row) =>
      raw.update(table, row, where: 'id = ?', whereArgs: [id]);

  Future<void> delete(String table, int id) => raw.delete(table, where: 'id = ?', whereArgs: [id]);

  Future<int> count(String table, {String? where, List<Object?>? args}) async {
    final r = await raw.rawQuery(
        'SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}', args);
    return (r.first['n'] as int?) ?? 0;
  }

  Future<void> audit(String who, String what) =>
      raw.insert('audit', {'at': DateTime.now().millisecondsSinceEpoch, 'who': who, 'what': what});

  /// First-run defaults: one receptionist, one outbound caller, starter skills.
  Future<void> seedDefaults(String ownerName) async {
    if (await count('agents') > 0) return;
    final first = ownerName.split(' ').first;
    await insert('agents', {
      'name': 'Ava',
      'role': 'Receptionist',
      'greeting': "Hi, you've reached $first's line. I'm Ava, $first's assistant. How can I help?",
      'instructions':
          'You answer phone calls for $first. Be warm, brief and natural, as on a phone call: one or two short sentences per reply. '
              'Take a message if you cannot help. Never share private details such as home address or schedule.',
      'language': 'English',
      'handles': 'incoming',
      'enabled': 1,
    });
    await insert('agents', {
      'name': 'Max',
      'role': 'Outbound caller',
      'greeting': "Hi, I'm $first's AI assistant, calling on $first's behalf.",
      'instructions':
          'You make phone calls for $first to achieve a specific goal. Always say you are an AI assistant. '
              'Be polite and concise. Only share details you were allowed to share. Report the outcome clearly.',
      'language': 'English',
      'handles': 'outgoing',
      'enabled': 1,
    });
    const skills = [
      ['Take a message', 'Collects name, number and reason; notifies you.', 1],
      ['Answer questions', 'Answers from Knowledge; says so when it doesn’t know.', 1],
      ['Book appointments', 'Uses your calendar to offer and book times.', 0],
      ['Transfer to me', 'Rings your paired phone and connects the caller.', 1],
      ['Screen unknown callers', 'Asks who is calling and why before deciding.', 1],
      ['Spam deflector', 'Ends sales calls politely in under 20 seconds.', 1],
    ];
    for (final s in skills) {
      await insert('skills', {'name': s[0], 'description': s[1], 'enabled': s[2]});
    }
    await insert('automations', {
      'name': 'Morning briefing',
      'trigger': 'Every day at 08:00',
      'steps': jsonEncode(['Summarise yesterday’s calls', 'Send summary to my devices']),
      'enabled': 0,
    });
    await insert('automations', {
      'name': 'Call back missed messages',
      'trigger': 'After a call ends with “Message taken”',
      'steps': jsonEncode([
        'Wait 2 hours',
        'If I have not called back, Max calls them',
        'Repeat until reached (max 3 times)',
      ]),
      'enabled': 0,
    });
  }
}
