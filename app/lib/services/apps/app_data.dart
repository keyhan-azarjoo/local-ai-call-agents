import 'dart:convert';

import '../../data/db.dart';
import 'app_spec.dart';

class AppDataError implements Exception {
  AppDataError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The records of one user-built app, kept in the main database (`app_rows`).
/// Each record is a JSON object, so tables can change without migrations.
class AppData {
  AppData(this.db, this.appId, this.spec);
  final Db db;
  final int appId;
  AppSpec spec;

  TableSpec _table(String id) => spec.table(id) ?? (throw AppDataError('There is no table "$id".'));

  Future<List<Map<String, Object?>>> list(String table, {String? search, bool manager = false, int limit = 500}) async {
    final t = _table(table);
    final rows = await db.raw.query('app_rows', where: 'app_id = ? AND tbl = ?', whereArgs: [appId, t.id], orderBy: 'id', limit: t.single ? 1 : limit);
    var out = [for (final r in rows) _out(t, r, manager)];
    final q = search?.trim().toLowerCase() ?? '';
    if (q.isNotEmpty) {
      final words = q.split(RegExp(r'\s+'));
      out = out.where((r) {
        final hay = r.values.map((v) => '$v').join(' ').toLowerCase();
        return words.every(hay.contains);
      }).toList();
    }
    return out;
  }

  Future<Map<String, Object?>?> get(String table, int id, {bool manager = false}) async {
    final t = _table(table);
    final r = await db.raw.query('app_rows', where: 'app_id = ? AND tbl = ? AND id = ?', whereArgs: [appId, t.id, id]);
    return r.isEmpty ? null : _out(t, r.first, manager);
  }

  /// The one record of a "single" table ({} when not set yet).
  Future<Map<String, Object?>> single(String table, {bool manager = false}) async => (await list(table, manager: manager)).firstOrNull ?? {};

  /// [via]: where it came from — 'website', 'phone' (Ava, on a call or in a chat) or 'manager'.
  Future<int> add(String table, Map<String, dynamic> values, {bool manager = false, String? via}) async {
    final t = _table(table);
    if (t.single) return setSingle(table, values, manager: manager);
    final clean = await _clean(t, values, manager: manager, partial: false);
    if (via != null) clean['_via'] = via;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.raw.insert('app_rows', {'app_id': appId, 'tbl': t.id, 'data': jsonEncode(clean), 'created_at': now, 'updated_at': now});
  }

  Future<void> update(String table, int id, Map<String, dynamic> values) async {
    final t = _table(table);
    final r = await db.raw.query('app_rows', where: 'app_id = ? AND tbl = ? AND id = ?', whereArgs: [appId, t.id, id]);
    if (r.isEmpty) throw AppDataError('No ${t.title.toLowerCase()} record with id $id.');
    final old = (jsonDecode(r.first['data'] as String) as Map).cast<String, Object?>();
    final clean = await _clean(t, values, manager: true, partial: true);
    await db.raw.update('app_rows', {'data': jsonEncode({...old, ...clean}), 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> setSingle(String table, Map<String, dynamic> values, {bool manager = true}) async {
    final t = _table(table);
    final r = await db.raw.query('app_rows', where: 'app_id = ? AND tbl = ?', whereArgs: [appId, t.id], limit: 1);
    if (r.isEmpty) {
      final clean = await _clean(t, values, manager: manager, partial: true);
      final now = DateTime.now().millisecondsSinceEpoch;
      return db.raw.insert('app_rows', {'app_id': appId, 'tbl': t.id, 'data': jsonEncode(clean), 'created_at': now, 'updated_at': now});
    }
    final id = r.first['id'] as int;
    await update(table, id, values);
    return id;
  }

  Future<void> delete(String table, int id) async {
    final t = _table(table);
    final n = await db.raw.delete('app_rows', where: 'app_id = ? AND tbl = ? AND id = ?', whereArgs: [appId, t.id, id]);
    if (n == 0) throw AppDataError('No ${t.title.toLowerCase()} record with id $id.');
  }

  Future<int> count(String table) async =>
      ((await db.raw.rawQuery('SELECT COUNT(*) AS n FROM app_rows WHERE app_id = ? AND tbl = ?', [appId, table])).first['n'] as int?) ?? 0;

  Future<void> clearAll() => db.raw.delete('app_rows', where: 'app_id = ?', whereArgs: [appId]);

  Map<String, Object?> _out(TableSpec t, Map<String, Object?> r, bool manager) {
    final d = (jsonDecode(r['data'] as String) as Map).cast<String, Object?>();
    return {
      'id': r['id'],
      for (final f in t.fields)
        if (manager || !f.managerOnly) f.id: d[f.id],
      if (manager) 'created_at': DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int).toIso8601String().substring(0, 16).replaceFirst('T', ' '),
      if (manager && d['_via'] != null) 'via': d['_via'],
    };
  }

  /// Checks and converts values. Customers can't set manager-only fields.
  /// Links may be given by id or by name ("Margherita" → its id), which helps the AI.
  Future<Map<String, Object?>> _clean(TableSpec t, Map<String, dynamic> values, {required bool manager, required bool partial}) async {
    final out = <String, Object?>{};
    final byKey = {for (final e in values.entries) slug(e.key, fallback: e.key): e.value};
    for (final f in t.fields) {
      if (f.managerOnly && !manager) continue;
      final has = byKey.containsKey(f.id) || byKey.containsKey(slug(f.label));
      final raw = byKey[f.id] ?? byKey[slug(f.label)];
      final empty = raw == null || (raw is String && raw.trim().isEmpty) || (raw is List && raw.isEmpty);
      if (empty) {
        if (f.required && !partial) throw AppDataError('${f.label} is required.');
        if (has && partial) out[f.id] = null;
        continue;
      }
      out[f.id] = await _value(f, raw);
    }
    // A new order etc. starts at the first option of manager-only choices (e.g. status: New).
    if (!partial) {
      for (final f in t.fields) {
        if (!out.containsKey(f.id) && f.type == 'choice' && f.managerOnly) out[f.id] = f.options.first;
      }
    }
    return out;
  }

  Future<Object?> _value(FieldSpec f, Object raw) async {
    final s = raw is String ? raw.trim() : raw;
    switch (f.type) {
      case 'number':
      case 'money':
        final n = s is num ? s : num.tryParse('$s'.replaceAll(RegExp(r'[^0-9.\-]'), ''));
        if (n == null) throw AppDataError('${f.label} must be a number.');
        return f.type == 'money' ? (n * 100).round() / 100 : n;
      case 'yesno':
        return s == true || RegExp(r'^(true|yes|1|y|on)$', caseSensitive: false).hasMatch('$s');
      case 'choice':
        final hit = f.options.where((o) => o.toLowerCase() == '$s'.toLowerCase()).firstOrNull;
        if (hit == null) throw AppDataError('${f.label} must be one of: ${f.options.join(', ')}.');
        return hit;
      case 'email':
        if (!'$s'.contains('@')) throw AppDataError('${f.label} must be an email address.');
        return '$s';
      case 'link':
        return _ref(f, s);
      case 'links':
        final items = s is List ? s : '$s'.split(',');
        final out = <Object>[];
        for (final it in items) {
          if (f.qty) {
            final m = it is Map ? it : {'id': it};
            final id = await _ref(f, m['id'] ?? m['name'] ?? m['item'] ?? m[f.link] ?? m.values.first);
            final q = num.tryParse('${m['qty'] ?? m['quantity'] ?? 1}')?.round() ?? 1;
            if (q > 0) out.add({'id': id, 'qty': q});
          } else {
            out.add(await _ref(f, it is Map ? (it['id'] ?? it['name']) : it));
          }
        }
        return out;
      default:
        final v = '$s';
        return v.length > 5000 ? v.substring(0, 5000) : v;
    }
  }

  Future<int> _ref(FieldSpec f, Object? v) async {
    final target = _table(f.link!);
    final rows = await list(target.id, manager: true);
    // By name first ("table 4", "Margherita"), as people and the AI say it; then by id.
    final name = '${v ?? ''}'.trim().toLowerCase();
    String label(Map<String, Object?> r) {
      final l = r[target.labelField];
      return (l is num && l == l.roundToDouble() ? '${l.toInt()}' : '${l ?? ''}').toLowerCase();
    }

    final bare = name.replaceFirst(RegExp(r'^(table|no\.?|number|#)\s*'), '');
    final hit = rows.where((r) => label(r) == name || label(r) == bare).firstOrNull ??
        rows.where((r) => name.isNotEmpty && label(r).contains(name)).firstOrNull;
    if (hit != null) return hit['id'] as int;
    final asInt = v is int ? v : int.tryParse(name);
    if (asInt != null && rows.any((r) => r['id'] == asInt)) return asInt;
    throw AppDataError('${f.label}: "$v" was not found in ${target.title.toLowerCase()}. '
        'Choose one of: ${rows.take(30).map(label).join(', ')}.');
  }

  /// Records as readable lines with link ids turned into names, for the AI.
  Future<String> describe(String table, List<Map<String, Object?>> rows) async {
    final t = _table(table);
    final names = <String, Map<int, String>>{};
    for (final f in t.fields.where((f) => f.link != null)) {
      final target = spec.table(f.link!)!;
      names[f.link!] ??= {for (final r in await list(target.id, manager: true)) r['id'] as int: '${r[target.labelField] ?? r['id']}'};
    }
    String show(FieldSpec f, Object? v) {
      if (v == null) return '';
      if (f.type == 'link') return names[f.link]?[v] ?? '$v';
      if (f.type == 'links' && v is List) {
        return v.map((x) => x is Map ? '${x['qty']} × ${names[f.link]?[x['id']] ?? x['id']}' : (names[f.link]?[x] ?? '$x')).join(', ');
      }
      if (f.type == 'yesno') return v == true ? 'yes' : 'no';
      if (f.type == 'image') return ''; // pictures mean nothing to the AI
      return '$v';
    }

    if (rows.isEmpty) return 'No ${t.title.toLowerCase()} yet.';
    return rows.map((r) {
      final parts = ['id ${r['id']}'];
      for (final f in t.fields) {
        if (!r.containsKey(f.id)) continue;
        final v = show(f, r[f.id]);
        if (v.isNotEmpty) parts.add('${f.label}: $v');
      }
      return parts.join(' · ');
    }).join('\n');
  }
}
