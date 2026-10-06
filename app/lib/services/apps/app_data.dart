import 'dart:convert';

import '../../data/db.dart';
import 'app_spec.dart';

/// A table of bookings for things that can only be booked once at a time (restaurant
/// tables, stylists, rooms…): it links to them and has a date and a time.
class BookingShape {
  BookingShape(this.table, this.resourceField, this.resources, this.dateField, this.timeField, {this.guestsField, this.seatsField, this.statusField});
  final TableSpec table, resources;
  final FieldSpec resourceField, dateField, timeField;
  final FieldSpec? guestsField, seatsField, statusField;

  static BookingShape? of(AppSpec spec, TableSpec t) {
    // What gets booked: a table, stylist, room, doctor… rather than a service or menu item.
    final links = t.fields.where((f) => f.type == 'link' && spec.table(f.link!) != null && !spec.table(f.link!)!.single).toList();
    final link = links.where((f) => _bookable.hasMatch('${f.id} ${f.link}')).firstOrNull ?? links.firstOrNull;
    final date = t.fields.where((f) => f.type == 'date').firstOrNull;
    final time = t.fields.where((f) => f.type == 'time').firstOrNull;
    if (link == null || date == null || time == null) return null;
    final res = spec.table(link.link!)!;
    return BookingShape(t, link, res, date, time,
        guestsField: t.fields.where((f) => f.type == 'number' && RegExp(r'guest|people|party|person|size|covers').hasMatch(f.id)).firstOrNull,
        seatsField: res.fields.where((f) => f.type == 'number' && RegExp(r'seat|capacity|guest|size|people|places').hasMatch(f.id)).firstOrNull,
        statusField: t.fields.where((f) => f.type == 'choice' && f.managerOnly).firstOrNull);
  }

  static final _bookable = RegExp(r'table|room|stylist|barber|doctor|dentist|therap|staff|trainer|coach|court|desk|seat|bay|chair|lane|pitch|vehicle|tutor|teacher|person', caseSensitive: false);

  /// A booking with this status doesn't hold the table.
  bool cancelled(Map<String, Object?> r) => statusField != null && RegExp(r'cancel|no.?show|declin|reject', caseSensitive: false).hasMatch('${r[statusField!.id] ?? ''}');
}

int? _minutes(Object? hhmm) {
  final m = RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch('${hhmm ?? ''}'.trim());
  return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

String _hhmm(int m) => '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

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
    // The same booking or order again within half an hour (asked twice, saved twice): keep one.
    final same = await _recentSame(t, clean);
    if (same != null) return same;
    if (via != null) clean['_via'] = via;
    final shape = BookingShape.of(spec, t);
    if (shape != null) await _holdResource(shape, clean);
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.raw.insert('app_rows', {'app_id': appId, 'tbl': t.id, 'data': jsonEncode(clean), 'created_at': now, 'updated_at': now});
  }

  Future<int?> _recentSame(TableSpec t, Map<String, Object?> clean) async {
    final since = DateTime.now().subtract(const Duration(minutes: 30)).millisecondsSinceEpoch;
    final keys = [for (final f in t.fields) if (!f.managerOnly && f.type != 'link' && clean[f.id] != null) f.id];
    if (keys.length < 2) return null;
    final rows = await db.raw.query('app_rows', where: 'app_id = ? AND tbl = ? AND created_at > ?', whereArgs: [appId, t.id, since]);
    for (final r in rows) {
      final d = (jsonDecode(r['data'] as String) as Map).cast<String, Object?>();
      if (keys.every((k) => '${d[k]}'.toLowerCase() == '${clean[k]}'.toLowerCase())) return r['id'] as int;
    }
    return null;
  }

  // ---------------- bookings ----------------

  /// How long one booking holds a table (minutes): the manager sets it on the website.
  int get bookingMinutes => int.tryParse(spec.site['booking_minutes'] ?? '') ?? 120;

  /// Bookings that hold something on [date] ("YYYY-MM-DD"): which, from, to (minutes), and the record.
  Future<List<({int resource, int from, int to, Map<String, Object?> row})>> busy(BookingShape b, String date) async {
    final out = <({int resource, int from, int to, Map<String, Object?> row})>[];
    for (final r in await list(b.table.id, manager: true)) {
      if ('${r[b.dateField.id] ?? ''}' != date || b.cancelled(r)) continue;
      final from = _minutes(r[b.timeField.id]);
      final res = r[b.resourceField.id];
      if (from == null || res is! int) continue;
      out.add((resource: res, from: from, to: from + bookingMinutes, row: r));
    }
    return out;
  }

  /// What can be booked on [date] at [time] for [guests]: free ones first, smallest that fits first.
  Future<({List<Map<String, Object?>> free, List<Map<String, Object?>> taken})> availability(BookingShape b, String date, String time, {int guests = 0}) async {
    final at = _minutes(time) ?? (throw AppDataError('Give the time as HH:MM.'));
    final hold = await busy(b, date);
    final all = await list(b.resources.id, manager: true);
    bool fits(Map<String, Object?> r) => guests <= 0 || b.seatsField == null || ((r[b.seatsField!.id] as num?) ?? 999) >= guests;
    bool takenAt(Map<String, Object?> r) => hold.any((h) => h.resource == r['id'] && at < h.to && at + bookingMinutes > h.from);
    final free = all.where((r) => fits(r) && !takenAt(r)).toList()
      ..sort((x, y) => (((x[b.seatsField?.id] as num?) ?? 0).compareTo((y[b.seatsField?.id] as num?) ?? 0)));
    return (free: free, taken: all.where(takenAt).toList());
  }

  /// A new booking: its table must be free then; with no table chosen, the best free one is given.
  Future<void> _holdResource(BookingShape b, Map<String, Object?> clean) async {
    final date = clean[b.dateField.id], time = clean[b.timeField.id];
    if (date == null || time == null) return;
    final guests = (clean[b.guestsField?.id] as num?)?.toInt() ?? 0;
    final a = await availability(b, '$date', '$time', guests: guests);
    final what = b.resources.title.toLowerCase();
    String names(List<Map<String, Object?>> rs) => rs.take(8).map((r) => '${r[b.resources.labelField] ?? r['id']}').join(', ');
    final chosen = clean[b.resourceField.id];
    if (chosen == null) {
      if (a.free.isEmpty) throw AppDataError('Sorry, nothing is free at $time on $date${guests > 0 ? ' for $guests' : ''}. Try another time.');
      clean[b.resourceField.id] = a.free.first['id'];
      return;
    }
    if (!a.free.any((r) => r['id'] == chosen)) {
      final r = (await list(b.resources.id, manager: true)).where((x) => x['id'] == chosen).firstOrNull;
      final tooSmall = r != null && !a.taken.any((x) => x['id'] == chosen);
      throw AppDataError('${b.resources.title.replaceAll(RegExp(r's$'), '')} ${r?[b.resources.labelField] ?? chosen} '
          '${tooSmall ? 'is too small for $guests' : 'is already booked at $time on $date'}. '
          '${a.free.isEmpty ? 'Nothing else is free then.' : 'Free $what then: ${names(a.free)}.'}');
    }
  }

  /// The day plan: every resource and its bookings, for the website (no names) or the manager.
  Future<Map<String, Object?>> dayPlan(BookingShape b, String date, {required bool manager}) async {
    final hours = spec.tables.where((t) => t.single).expand((t) => [t]).toList();
    int? open, close;
    for (final t in hours) {
      final times = t.fields.where((f) => f.type == 'time').toList();
      if (times.length < 2) continue;
      final r = await single(t.id, manager: true);
      open = _minutes(r[times[0].id]);
      close = _minutes(r[times[1].id]);
      if (open != null && close != null) break;
    }
    return {
      'minutes': bookingMinutes,
      'open': _hhmm(open ?? 12 * 60),
      'close': _hhmm(close ?? 22 * 60),
      'resources': [
        for (final r in await list(b.resources.id, manager: true))
          {'id': r['id'], 'name': '${r[b.resources.labelField] ?? r['id']}', if (b.seatsField != null) 'seats': r[b.seatsField!.id]},
      ],
      'busy': [
        for (final h in await busy(b, date))
          {
            'resource': h.resource,
            'from': _hhmm(h.from),
            'to': _hhmm(h.to),
            if (manager) 'id': h.row['id'],
            if (manager) 'who': '${h.row[b.table.labelField] ?? ''}',
            if (manager && b.guestsField != null) 'guests': h.row[b.guestsField!.id],
          },
      ],
    };
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
