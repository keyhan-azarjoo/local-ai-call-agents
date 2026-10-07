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
        statusField: statusOf(t));
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

const _numberWords = {'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10', 'twelve': '12', 'dozen': '12', 'half': '6'};
const _filler = {'the', 'a', 'an', 'of', 'and', 'with', 'for', 'my', 'please', 'some', 'box', 'boxes', 'bottle', 'bottles', 'x', 'pack', 'one', 'order', 'standard', 'normal', 'regular', 'just'};

const _accents = {'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae', 'ß': 'ss'};

/// "Tiramisù" → "tiramisu", "Amélie" → "amelie": as it's said, not as it's spelt.
String plain(String s) => s.toLowerCase().split('').map((c) => _accents[c] ?? c).join();

Set<String> _words(String s) => {
      for (var w in plain(s).replaceAll(RegExp(r"[’']"), '').replaceAll('&', ' and ').split(RegExp(r'[^a-z0-9]+')))
        if (w.isNotEmpty && !_filler.contains(w)) (w = _numberWords[w] ?? w).length > 3 && w.endsWith('s') && !w.endsWith('ss') ? w.substring(0, w.length - 1) : w,
    };

/// The one label that clearly matches what was said (most words in common), or null.
int? bestMatch(String said, Map<int, String> labels) {
  final q = _words(said);
  if (q.isEmpty) return null;
  final scored = [
    for (final e in labels.entries)
      (e.key, () {
        final l = _words(e.value);
        final common = q.intersection(l).length;
        // Words in common, then covering more of what was said, then fewer extra words in the name.
        return l.isEmpty || common == 0 ? 0.0 : common / (q.length < l.length ? q.length : l.length) + 0.5 * common / q.length - 0.2 * (l.length - common) / l.length;
      }()),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  if (scored.isEmpty || scored.first.$2 < 0.5) return null;
  if (scored.length > 1 && (scored.first.$2 - scored[1].$2).abs() < 0.05) return null;
  return scored.first.$1;
}

/// The days a caller meant in [text] ("tomorrow", "next Thursday", "Saturday"), as YYYY-MM-DD;
/// several when it's ambiguous ("Wednesday" said on a Wednesday: today or next week). Empty when
/// nothing (or an exact date, which the AI reads itself) was said, or more than one day was named.
Set<String> spokenDates(String text, {DateTime? now}) {
  final s = text.toLowerCase();
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  if (RegExp(r'\b\d{1,2}(st|nd|rd|th)\b|\b(january|february|march|april|june|july|august|september|october|november|december)\b|\bmay \d|\d(st|nd|rd|th)? (of )?may\b|\d{4}-\d{2}|\d{1,2}/\d{1,2}').hasMatch(s)) return {};
  const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  final named = [
    if (RegExp(r'\b(today|tonight)\b').hasMatch(s)) 'today',
    if (RegExp(r'day after tomorrow').hasMatch(s)) 'after' else if (RegExp(r'\btomorrow\b').hasMatch(s)) 'tomorrow',
    for (final d in days)
      if (RegExp('\\b${d}s?\\b').hasMatch(s)) d,
  ];
  if (named.length != 1) return {};
  final n = named.single;
  if (n == 'today') return {ymd(today)};
  // Day by day, not +24 h (that's a day off when the clocks change).
  DateTime plus(int k) => DateTime(today.year, today.month, today.day + k);
  if (n == 'tomorrow') return {ymd(plus(1))};
  if (n == 'after') return {ymd(plus(2))};
  final ahead = (days.indexOf(n) + 1 - today.weekday) % 7;
  // "Thursday" / "this Thursday" / "next Thursday": the coming one, or the one after (people differ).
  return {ymd(plus(ahead)), ymd(plus(ahead + 7))};
}

/// "2026-10-10" → "Saturday 2026-10-10" (small models get weekdays wrong on their own).
String withDay(String ymd) {
  final d = DateTime.tryParse(ymd.length >= 10 ? ymd.substring(0, 10) : ymd);
  if (d == null) return ymd;
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  return '${days[d.weekday - 1]} $ymd';
}

/// "19:30", "7:30pm", "7 pm", "7.30 p.m.", "noon" → "HH:MM" (null if it isn't a time).
String? parseTime(String raw) {
  final s = raw.trim().toLowerCase().replaceAll('.', ':').replaceAll(RegExp(r'\s+'), ' ');
  if (s == 'noon' || s == 'midday') return '12:00';
  if (s == 'midnight') return '00:00';
  final m = RegExp(r'^(\d{1,2})(?::(\d{2}))?(?::\d{2})?\s*(a:?m:?|p:?m:?)?$').firstMatch(s);
  if (m == null) return null;
  var h = int.parse(m[1]!);
  final min = int.parse(m[2] ?? '0');
  final ap = m[3]?.replaceAll(':', '');
  if (m[2] == null && ap == null) return null; // a bare "7": too unclear
  if (ap == 'pm' && h < 12) h += 12;
  if (ap == 'am' && h == 12) h = 0;
  if (h > 23 || min > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

/// "2026-10-10", "10/10/2026" (day first), "today", "tomorrow", "Saturday" (the next one) → "YYYY-MM-DD".
String? parseDate(String raw, {DateTime? now}) {
  final s = raw.trim().toLowerCase();
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (m != null) {
    final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    return d.month == int.parse(m[2]!) ? ymd(d) : null;
  }
  m = RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})$').firstMatch(s);
  if (m != null) {
    final y = int.parse(m[3]!) < 100 ? 2000 + int.parse(m[3]!) : int.parse(m[3]!);
    final d = DateTime(y, int.parse(m[2]!), int.parse(m[1]!));
    return d.month == int.parse(m[2]!) ? ymd(d) : null;
  }
  if (s == 'today') return ymd(today);
  if (s == 'tomorrow') return ymd(DateTime(today.year, today.month, today.day + 1));
  const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  final w = days.indexWhere((d) => s.replaceFirst(RegExp(r'^(this|next|on)\s+'), '') == d);
  if (w >= 0) {
    // Day by day, not +24 h (that's a day off when the clocks change).
    var k = 1;
    while (DateTime(today.year, today.month, today.day + k).weekday != w + 1) {
      k++;
    }
    final d = DateTime(today.year, today.month, today.day + k);
    return ymd(d);
  }
  return null;
}

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
      // As people say it: "croissants" finds "Butter croissant", "tiramisu" finds "Tiramisù".
      final words = _words(q);
      bool has(Map<String, Object?> r) {
        final hay = _words(r.values.map((v) => '$v').join(' '));
        return words.every((w) => hay.any((h) => h == w || h.startsWith(w) || w.startsWith(h) && h.length > 3));
      }

      final all = out.where(has).toList();
      // Several words and nothing has all of them: the best partial matches.
      out = all.isNotEmpty || words.length < 2
          ? all
          : out.where((r) => _words(r.values.map((v) => '$v').join(' ')).intersection(words).isNotEmpty).toList();
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
    if (!manager) await _inStock(t, clean);
    if (via != 'seed') await _open(t, clean);
    if (!manager) await _minimum(t, clean);
    // The order's total, kept with it (the manager may type their own).
    if (!(manager && clean[_totalField(t)?.id] != null)) await _fillTotal(t, clean);
    // The same booking or order again within half an hour (asked twice, saved twice): keep one.
    final same = await _recentSame(t, clean);
    if (same != null) {
      // Same booking, another table ("table 5 instead"): move it, if that one is free.
      final shape = BookingShape.of(spec, t);
      final want = shape == null ? null : clean[shape.resourceField.id];
      final old = await get(t.id, same, manager: true);
      if (shape != null && want != null && old != null && old[shape.resourceField.id] != want) {
        final a = await availability(shape, '${clean[shape.dateField.id]}', '${clean[shape.timeField.id]}',
            guests: (clean[shape.guestsField?.id] as num?)?.toInt() ?? 0, ignore: same);
        if (!a.free.any((r) => r['id'] == want)) throw AppDataError('That ${shape.resources.title.toLowerCase().replaceAll(RegExp(r's$'), '')} is not free then.');
        await update(t.id, same, {shape.resourceField.id: want});
      }
      return same;
    }
    if (via != null) clean['_via'] = via;
    final shape = BookingShape.of(spec, t);
    try {
      if (shape != null) await _holdResource(shape, clean);
      if (shape == null) await _holdStay(t, clean);
    } on AppDataError {
      // Test set-up ("someone has The Loft"): an earlier test record may hold it already — taken either way.
      if (via != 'seed') rethrow;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.raw.insert('app_rows', {'app_id': appId, 'tbl': t.id, 'data': jsonEncode(clean), 'created_at': now, 'updated_at': now});
  }

  /// Customers can't order what is marked out of stock (or book a home no longer available).
  Future<void> _inStock(TableSpec t, Map<String, Object?> clean) async {
    for (final f in t.fields.where((f) => (f.type == 'link' || f.type == 'links') && clean[f.id] != null)) {
      final target = spec.table(f.link!)!;
      final flag = target.fields.where((x) => x.type == 'yesno' && RegExp(r'stock|available|availab', caseSensitive: false).hasMatch('${x.id} ${x.label}')).firstOrNull;
      if (flag == null) continue;
      final ids = [for (final x in (clean[f.id] is List ? clean[f.id] as List : [clean[f.id]])) x is Map ? x['id'] : x];
      for (final r in await list(target.id, manager: true)) {
        if (ids.contains(r['id']) && r[flag.id] == false) {
          throw AppDataError('${r[target.labelField]} is ${RegExp('stock').hasMatch(flag.id) ? 'out of stock' : 'not available'} right now: tell the caller, and offer something else.');
        }
      }
    }
  }

  Future<int?> _recentSame(TableSpec t, Map<String, Object?> clean) async {
    final since = DateTime.now().subtract(const Duration(minutes: 30)).millisecondsSinceEpoch;
    // The details that make it the same booking/order (not notes like "no special requests").
    final keys = [
      for (final f in t.fields)
        if (!f.managerOnly && f.type != 'link' && f.type != 'longtext' && clean[f.id] != null && (f.required || const {'phone', 'email', 'date', 'time', 'datetime', 'links', 'number'}.contains(f.type))) f.id,
    ];
    if (keys.length < 2) return null;
    // Someone's own only: where there is a phone number, it must be the same one.
    if (t.fields.any((f) => f.type == 'phone') && !t.fields.any((f) => f.type == 'phone' && keys.contains(f.id))) return null;
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
  Future<List<({int resource, int from, int to, Map<String, Object?> row})>> busy(BookingShape b, String date, {int? ignore}) async {
    final out = <({int resource, int from, int to, Map<String, Object?> row})>[];
    for (final r in await list(b.table.id, manager: true)) {
      if ('${r[b.dateField.id] ?? ''}' != date || b.cancelled(r) || r['id'] == ignore) continue;
      final from = _minutes(r[b.timeField.id]);
      final res = r[b.resourceField.id];
      if (from == null || res is! int) continue;
      out.add((resource: res, from: from, to: from + bookingMinutes, row: r));
    }
    return out;
  }

  /// What can be booked on [date] at [time] for [guests]: free ones first, smallest that fits first.
  Future<({List<Map<String, Object?>> free, List<Map<String, Object?>> taken})> availability(BookingShape b, String date, String time, {int guests = 0, int? ignore}) async {
    final at = _minutes(time) ?? (throw AppDataError('Give the time as HH:MM.'));
    // Closed that day (a holiday, private hire): nothing is free.
    if (await closedOn(date) != null) return (free: <Map<String, Object?>>[], taken: <Map<String, Object?>>[]);
    final hold = await busy(b, date, ignore: ignore);
    final all = await list(b.resources.id, manager: true);
    bool fits(Map<String, Object?> r) => guests <= 0 || b.seatsField == null || ((r[b.seatsField!.id] as num?) ?? 999) >= guests;
    bool takenAt(Map<String, Object?> r) => hold.any((h) => h.resource == r['id'] && at < h.to && at + bookingMinutes > h.from);
    final free = all.where((r) => fits(r) && !takenAt(r)).toList()
      ..sort((x, y) => (((x[b.seatsField?.id] as num?) ?? 0).compareTo((y[b.seatsField?.id] as num?) ?? 0)));
    return (free: free, taken: all.where(takenAt).toList());
  }

  /// The nearest times on [date] when something is free (for "nothing at 12:00 — 11:00 or 13:00?").
  Future<List<String>> nearestFree(BookingShape b, String date, String time, {int guests = 0, int count = 3}) async {
    final at = _minutes(time);
    if (at == null || await closedOn(date) != null) return const [];
    final plan = await dayPlan(b, date, manager: true);
    final open = _minutes(plan['open']) ?? 9 * 60, close = _minutes(plan['close']) ?? 18 * 60;
    final found = <int>[];
    for (var step = 30; step <= 4 * 60 && found.length < count; step += 30) {
      for (final m in [at - step, at + step]) {
        if (found.length < count && m >= open && m < close && (await availability(b, date, _hhmm(m), guests: guests)).free.isNotEmpty) found.add(m);
      }
    }
    found.sort();
    return [for (final m in found) _hhmm(m)];
  }

  /// A new booking: its table must be free then; with no table chosen, the best free one is given.
  /// When a taken table was swapped for a free one on the last add (for the AI to tell the caller).
  String? swapped;
  bool autoSwap = false;

  Future<void> _holdResource(BookingShape b, Map<String, Object?> clean) async {
    final date = clean[b.dateField.id], time = clean[b.timeField.id];
    if (date == null || time == null) return;
    final guests = (clean[b.guestsField?.id] as num?)?.toInt() ?? 0;
    final a = await availability(b, '$date', '$time', guests: guests);
    final what = b.resources.title.toLowerCase();
    String names(List<Map<String, Object?>> rs) => rs.take(8).map((r) => '${r[b.resources.labelField] ?? r['id']}').join(', ');
    final chosen = clean[b.resourceField.id];
    if (chosen == null) {
      if (a.free.isEmpty) {
        final near = await nearestFree(b, '$date', '$time', guests: guests);
        throw AppDataError('Sorry, nothing is free at $time on $date${guests > 0 ? ' for $guests' : ''}. ${near.isEmpty ? 'Try another day.' : 'Free that day at: ${near.join(', ')}.'}');
      }
      clean[b.resourceField.id] = a.free.first['id'];
      return;
    }
    if (!a.free.any((r) => r['id'] == chosen)) {
      final r = (await list(b.resources.id, manager: true)).where((x) => x['id'] == chosen).firstOrNull;
      final tooSmall = r != null && !a.taken.any((x) => x['id'] == chosen);
      // Restaurant tables (they have seats): any free one that fits will do — the AI picked it, not the guest.
      if (b.seatsField != null && a.free.isNotEmpty && autoSwap) {
        clean[b.resourceField.id] = a.free.first['id'];
        swapped = '${r?[b.resources.labelField] ?? chosen} ${tooSmall ? 'is too small for $guests' : 'was taken'}, so it is ${a.free.first[b.resources.labelField]} instead';
        return;
      }
      throw AppDataError('${b.resources.title.replaceAll(RegExp(r's$'), '')} ${r?[b.resources.labelField] ?? chosen} '
          '${tooSmall ? 'is too small for $guests' : 'is already booked at $time on $date'}. '
          '${a.free.isEmpty ? 'Nothing else is free then.' : 'Free $what then: ${names(a.free)}.'}');
    }
  }

  /// A stay table (a room from check-in to check-out, no times): its two dates, the room and the guests.
  static ({FieldSpec from, FieldSpec to, FieldSpec room, FieldSpec? guests})? stayOf(TableSpec t) {
    final dates = t.fields.where((f) => f.type == 'date').toList();
    final res = t.fields.where((f) => f.type == 'link' && BookingShape._bookable.hasMatch('${f.id} ${f.link}')).firstOrNull;
    if (dates.length < 2 || res == null || t.fields.any((f) => f.type == 'time')) return null;
    return (from: dates[0], to: dates[1], room: res,
        guests: t.fields.where((f) => f.type == 'number' && RegExp(r'guest|people|party|person|size').hasMatch(f.id)).firstOrNull);
  }

  /// Rooms free for every night from [from] to [to] that sleep [guests], and the ones taken then.
  Future<({List<Map<String, Object?>> free, List<Map<String, Object?>> taken})> freeStay(TableSpec t, String from, String to, {int guests = 0, int? ignore}) async {
    final s = stayOf(t)!;
    final status = statusOf(t);
    final rooms = await list(s.room.link!, manager: true);
    final sleeps = spec.table(s.room.link!)!.fields.where((f) => f.type == 'number' && RegExp(r'seat|capacity|guest|size|people|places|sleeps').hasMatch(f.id)).firstOrNull;
    final taken = <Object?>{};
    for (final r in await list(t.id, manager: true)) {
      if (r['id'] == ignore || (status != null && RegExp(r'cancel|no.?show|declin|reject', caseSensitive: false).hasMatch('${r[status.id] ?? ''}'))) continue;
      final a = '${r[s.from.id] ?? ''}', b = '${r[s.to.id] ?? ''}';
      if (a.isNotEmpty && b.isNotEmpty && from.compareTo(b) < 0 && to.compareTo(a) > 0) taken.add(r[s.room.id]);
    }
    bool fits(Map<String, Object?> r) => guests <= 0 || sleeps == null || ((r[sleeps.id] as num?) ?? 999) >= guests;
    return (free: [for (final r in rooms) if (!taken.contains(r['id']) && fits(r)) r], taken: [for (final r in rooms) if (taken.contains(r['id'])) r]);
  }

  /// A stay: the room must be free for those nights.
  Future<void> _holdStay(TableSpec t, Map<String, Object?> clean, {int? ignore}) async {
    final s = stayOf(t);
    if (s == null) return;
    final from = '${clean[s.from.id] ?? ''}', to = '${clean[s.to.id] ?? ''}', want = clean[s.room.id];
    if (from.isEmpty || to.isEmpty || want == null) return;
    if (to.compareTo(from) <= 0) throw AppDataError('${s.to.label} must be after ${s.from.label.toLowerCase()}.');
    final a = await freeStay(t, from, to, guests: (clean[s.guests?.id] as num?)?.toInt() ?? 0, ignore: ignore);
    final hit = a.taken.where((r) => r['id'] == want).firstOrNull;
    if (hit == null) return;
    final label = spec.table(s.room.link!)!.labelField;
    throw AppDataError('${hit[label] ?? want} is already booked for some of those nights ($from to $to). '
        '${a.free.isEmpty ? 'Nothing else is free then.' : 'Free then: ${a.free.map((r) => '${r[label]}').join(', ')}.'}');
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
    final closed = await closedOn(date);
    return {
      'closed': ?closed,
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

  /// A customer changes their own booking or order (a new time, more people…): never onto a
  /// taken table; with the old table busy then, the best free one is given.
  Future<void> change(String table, int id, Map<String, dynamic> values) async {
    final t = _table(table);
    final r = await db.raw.query('app_rows', where: 'app_id = ? AND tbl = ? AND id = ?', whereArgs: [appId, t.id, id]);
    if (r.isEmpty) throw AppDataError('No ${t.title.toLowerCase()} record with id $id.');
    final old = (jsonDecode(r.first['data'] as String) as Map).cast<String, Object?>();
    final clean = await _clean(t, values, manager: false, partial: true)..removeWhere((k, v) => v == null);
    final merged = {...old, ...clean};
    await _open(t, merged);
    final shape = BookingShape.of(spec, t);
    // A stay moved to other nights or another room: never onto a taken one.
    if (shape == null) await _holdStay(t, merged, ignore: id);
    if (shape != null && merged[shape.dateField.id] != null && merged[shape.timeField.id] != null) {
      final res = shape.resourceField.id;
      final a = await availability(shape, '${merged[shape.dateField.id]}', '${merged[shape.timeField.id]}',
          guests: (merged[shape.guestsField?.id] as num?)?.toInt() ?? 0, ignore: id);
      final what = shape.resources.title.toLowerCase();
      String names() => a.free.take(8).map((x) => '${x[shape.resources.labelField] ?? x['id']}').join(', ');
      if (clean[res] != null) {
        if (!a.free.any((x) => x['id'] == clean[res])) throw AppDataError('That one is not free then. ${a.free.isEmpty ? 'Nothing is free then.' : 'Free $what then: ${names()}.'}');
      } else if (!a.free.any((x) => x['id'] == merged[res])) {
        if (a.free.isEmpty) throw AppDataError('Sorry, nothing is free at ${merged[shape.timeField.id]} on ${withDay('${merged[shape.dateField.id]}')}. Try another time.');
        clean[res] = a.free.first['id'];
      }
    }
    // Fields that no longer apply (a table on what is now a delivery) go.
    final out = {...old, ...clean};
    for (final f in t.fields.where((f) => f.when != null)) {
      if (!f.appliesTo(out)) out.remove(f.id);
    }
    await _minimum(t, out);
    await _fillTotal(t, out);
    await db.raw.update('app_rows', {'data': jsonEncode(out), 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
  }

  /// The stylist, doctor, barber… the caller asked for by name in [heard] (their words; the last one named
  /// wins, not one they said no to: "Priya, not Marcus"). Not tables or numbered rooms.
  Future<String?> namedResource(BookingShape b, String heard) async {
    if (b.seatsField != null || heard.trim().isEmpty) return null;
    const titles = {'dr', 'doctor', 'mr', 'mrs', 'ms', 'miss', 'prof', 'the'};
    final labels = [for (final r in await list(b.resources.id, manager: true)) '${r[b.resources.labelField] ?? ''}'];
    List<String> words(String l) => plain(l).split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 3 && !titles.contains(w) && int.tryParse(w) == null).toList();
    // Only words that pick one out ("Hannah", "Reid"), not "Room" in "Room 1" and "Room 2".
    final count = <String, int>{};
    for (final l in labels) {
      for (final w in words(l).toSet()) {
        count[w] = (count[w] ?? 0) + 1;
      }
    }
    final said = plain(heard);
    String? found;
    var at = -1;
    for (final l in labels) {
      for (final w in words(l).where((w) => count[w] == 1)) {
        for (final m in RegExp('\\b${RegExp.escape(w)}\\b').allMatches(said)) {
          if (m.start <= at || RegExp(r'\b(not|than|instead of|this is|i.?m|i am|name is)\s+(dr\.?\s+|doctor\s+)?$').hasMatch(said.substring(0, m.start))) continue;
          at = m.start;
          found = l;
        }
      }
    }
    return found;
  }

  /// What this phone number saved by phone in the last [minutes] (not cancelled): a second save
  /// in the same call is a correction of the first. For bookings, only one on the same day.
  Future<int?> recentByPhone(TableSpec t, String phone, {String? date, String? name, int minutes = 20, int? since}) async {
    final phoneF = t.fields.where((f) => f.type == 'phone').firstOrNull;
    String last9(Object? x) {
      final d = '${x ?? ''}'.replaceAll(RegExp(r'\D'), '');
      return d.length < 9 ? d : d.substring(d.length - 9);
    }
    if (phoneF == null || (last9(phone).length < 9 && name == null)) return null;
    final shape = BookingShape.of(spec, t);
    // Within this call only (when known): a caller ringing back later makes a new booking.
    final window = DateTime.now().subtract(Duration(minutes: minutes)).millisecondsSinceEpoch;
    final from = since != null && since > window ? since - 1000 : window;
    final rows = await db.raw.query('app_rows', where: 'app_id = ? AND tbl = ? AND created_at > ?', whereArgs: [appId, t.id, from], orderBy: 'id DESC');
    for (final r in rows) {
      final d = (jsonDecode(r['data'] as String) as Map).cast<String, Object?>();
      final samePhone = last9(phone).length >= 9 && last9(d[phoneF.id]) == last9(phone);
      // Only ever their own (same number): the same name alone could be someone else's booking.
      if (d['_via'] != 'phone' || !samePhone) continue;
      final status = statusOf(t);
      if (status != null && RegExp(r'cancel', caseSensitive: false).hasMatch('${d[status.id] ?? ''}')) continue;
      // Another day is another booking — unless it was saved minutes ago (they changed the day in this call).
      final fresh = (r['created_at'] as int) > DateTime.now().subtract(const Duration(minutes: 10)).millisecondsSinceEpoch;
      if (shape != null && date != null && d[shape.dateField.id] != date && !fresh) continue;
      return r['id'] as int;
    }
    return null;
  }

  Future<void> update(String table, int id, Map<String, dynamic> values) async {
    final t = _table(table);
    final r = await db.raw.query('app_rows', where: 'app_id = ? AND tbl = ? AND id = ?', whereArgs: [appId, t.id, id]);
    if (r.isEmpty) throw AppDataError('No ${t.title.toLowerCase()} record with id $id.');
    final old = (jsonDecode(r.first['data'] as String) as Map).cast<String, Object?>();
    final clean = await _clean(t, values, manager: true, partial: true);
    final merged = {...old, ...clean};
    // Items or delivery changed: the total follows (unless the manager typed a new one).
    final tf = _totalField(t);
    if (tf != null && (!clean.containsKey(tf.id) || clean[tf.id] == old[tf.id]) && t.fields.any((f) => (f.type == 'links' || f.type == 'choice') && !f.managerOnly && jsonEncode(old[f.id]) != jsonEncode(merged[f.id]))) {
      await _fillTotal(t, merged);
    }
    await db.raw.update('app_rows', {'data': jsonEncode(merged), 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
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
    // Fields that only apply in some cases (an address only for delivery) come last, once the rest is known.
    final ordered = [...t.fields.where((f) => f.when == null), ...t.fields.where((f) => f.when != null)];
    for (final f in ordered) {
      if (f.managerOnly && !manager) continue;
      final has = byKey.containsKey(f.id) || byKey.containsKey(slug(f.label));
      final raw = byKey[f.id] ?? byKey[slug(f.label)];
      final empty = raw == null || (raw is String && raw.trim().isEmpty) || (raw is List && raw.isEmpty);
      if (!partial && !f.appliesTo(out)) continue; // e.g. a table for a delivery order: not kept
      if (empty) {
        if (f.required && !partial) {
          final w = f.when;
          throw AppDataError(w == null ? '${f.label} is required.' : '${f.label} is required for ${w.value.join(' / ')}.');
        }
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
      case 'time':
        return parseTime('$s') ?? (throw AppDataError('${f.label}: give the time as HH:MM (e.g. 19:30), not "$s".'));
      case 'date':
        return parseDate('$s') ?? (throw AppDataError('${f.label}: give the date as YYYY-MM-DD, not "$s".'));
      case 'datetime':
        final m = RegExp(r'^(.*?)[ T,]+(\S+(\s*[ap]\.?m\.?)?)$', caseSensitive: false).firstMatch('$s'.trim());
        // "tomorrow at 5pm", "Saturday 2026-10-10 17:00": the day without "at" or its name.
        final day = (m?.group(1) ?? '$s').replaceFirst(RegExp(r'\s+(at|@)$', caseSensitive: false), '').replaceFirst(RegExp(r'^[a-z]+day\s+(?=\d{4}-)', caseSensitive: false), '');
        final d = parseDate(day), t = m == null ? null : parseTime(m.group(2)!);
        if (d == null || t == null) throw AppDataError('${f.label}: give it as YYYY-MM-DD HH:MM, not "$s".');
        return '$d $t';
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
    final name = plain('${v ?? ''}'.trim());
    String label(Map<String, Object?> r) {
      final l = r[target.labelField];
      return plain(l is num && l == l.roundToDouble() ? '${l.toInt()}' : '${l ?? ''}');
    }

    final bare = name.replaceFirst(RegExp(r'^(table|no\.?|number|#)\s*'), '');
    final hit = rows.where((r) => label(r) == name || label(r) == bare).firstOrNull ??
        rows.where((r) => name.isNotEmpty && label(r).contains(name)).firstOrNull;
    if (hit != null) return hit['id'] as int;
    final asInt = v is int ? v : int.tryParse(name);
    if (asInt != null && rows.any((r) => r['id'] == asInt)) return asInt;
    // As people say it: "women's cut and blow-dry", "a box of six eggs", "the MOT".
    final best = bestMatch(name, {for (final r in rows) r['id'] as int: label(r)});
    if (best != null) return best;
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
      if (f.type == 'date' || f.type == 'datetime') return withDay('$v');
      return '$v';
    }

    // An order's total, from the prices of what's in it (and the delivery fee).
    final prices = await _prices(t);
    final tf = _totalField(t);
    if (rows.isEmpty) return 'No ${t.title.toLowerCase()} yet.';
    final lines = <String>[];
    for (final r in rows) {
      final parts = ['id ${r['id']}'];
      for (final f in t.fields) {
        if (!r.containsKey(f.id) || f == tf) continue;
        final v = show(f, r[f.id]);
        if (v.isNotEmpty) parts.add('${f.label}: $v');
      }
      final tot = await orderTotal(t.id, r, prices: prices);
      if (tot != null) parts.add('Total: ${money(tot.total)}${tot.fee > 0 ? ' (${money(tot.items)} + ${money(tot.fee)} delivery)' : ''}');
      lines.add(parts.join(' · '));
    }
    return lines.join('\n');
  }

  // ---------------- orders: totals, delivery ----------------

  /// What an order can hold, with prices: field → record id → price.
  Future<Map<String, Map<int, num>>> _prices(TableSpec t) async {
    final out = <String, Map<int, num>>{};
    for (final f in t.fields.where((f) => f.type == 'links' && f.qty)) {
      final target = spec.table(f.link!);
      final price = target?.fields.where((x) => x.type == 'money').firstOrNull;
      if (target == null || price == null) continue;
      out[f.id] = {for (final r in await list(target.id, manager: true, limit: 5000)) if (r[price.id] is num) r['id'] as int: r[price.id] as num};
    }
    return out;
  }

  /// A delivery (its "Collection or delivery" choice says Delivery).
  static bool isDelivery(TableSpec t, Map<String, Object?> r) =>
      t.fields.any((f) => f.type == 'choice' && !f.managerOnly && RegExp(r'^deliver', caseSensitive: false).hasMatch('${r[f.id] ?? ''}'));

  num _siteNumber(String k) => num.tryParse((spec.site[k] ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  /// What delivery costs, and the least a delivery order may come to (0 = none); set on the website.
  num get deliveryFee => _siteNumber('delivery_fee');
  num get minOrder => _siteNumber('min_order');

  /// "£12.50" in the app's currency.
  String money(num n) => '${spec.site['currency'] ?? ''}${n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2)}';

  /// An order's total: the prices of what's in it, plus the delivery fee on a delivery.
  /// Null when nothing in it has a price.
  Future<({num items, num fee, num total})?> orderTotal(String table, Map<String, Object?> row, {Map<String, Map<int, num>>? prices}) async {
    final t = _table(table);
    prices ??= await _prices(t);
    num sum = 0;
    var any = false;
    for (final e in prices.entries) {
      for (final x in (row[e.key] is List ? row[e.key] as List : const [])) {
        if (x is Map && e.value[x['id']] != null) {
          sum += e.value[x['id']]! * ((x['qty'] as num?) ?? 1);
          any = true;
        }
      }
    }
    if (!any) return null;
    final fee = isDelivery(t, row) ? deliveryFee : 0;
    return (items: sum, fee: fee, total: sum + fee);
  }

  /// The manager-only "Total" an order keeps (filled in by itself).
  FieldSpec? _totalField(TableSpec t) => t.fields.where((f) => f.type == 'money' && f.managerOnly && RegExp(r'^(order_)?total$').hasMatch(f.id)).firstOrNull;

  Future<void> _fillTotal(TableSpec t, Map<String, Object?> r) async {
    final f = _totalField(t);
    if (f == null) return;
    final tot = await orderTotal(t.id, r);
    if (tot != null) r[f.id] = (tot.total * 100).round() / 100;
  }

  /// A delivery below the minimum order is refused (collection is fine).
  Future<void> _minimum(TableSpec t, Map<String, Object?> r) async {
    if (minOrder <= 0 || !isDelivery(t, r)) return;
    final tot = await orderTotal(t.id, r);
    if (tot != null && tot.items < minOrder) {
      throw AppDataError('The minimum order for delivery is ${money(minOrder)} (this order is ${money(tot.items)}): add something more, or choose collection.');
    }
  }

  // ---------------- closed days ----------------

  /// Why the business is closed on [date] ("YYYY-MM-DD"): the reason, "closed", or null when open.
  Future<String?> closedOn(String date) async {
    final c = closuresOf(spec);
    if (c == null || date.length < 10) return null;
    final day = date.substring(0, 10);
    final dates = c.fields.where((f) => f.type == 'date').toList();
    final why = c.fields.where((f) => (f.type == 'text' || f.type == 'longtext') && !f.managerOnly).firstOrNull;
    for (final r in await list(c.id, manager: true, limit: 5000)) {
      final from = '${r[dates[0].id] ?? ''}';
      if (from.isEmpty) continue;
      final until = dates.length > 1 ? '${r[dates[1].id] ?? ''}' : '';
      final to = until.compareTo(from) > 0 ? until : from;
      if (day.compareTo(from) >= 0 && day.compareTo(to) <= 0) {
        final w = why == null ? '' : '${r[why.id] ?? ''}'.trim();
        return w.isEmpty ? 'closed' : w;
      }
    }
    return null;
  }

  /// What a caller or visitor is told when the day they want is closed.
  static String closedMessage(String date, String why) =>
      'Sorry, we are closed on ${withDay(date)}${why == 'closed' ? '' : ' ($why)'}, so nothing can be booked that day. Ask which other day suits them.';

  /// Bookings (and anything else customers send with a day) can't be for a closed day.
  Future<void> _open(TableSpec t, Map<String, Object?> r) async {
    final c = closuresOf(spec);
    if (c == null || c.id == t.id || !t.access.add) return;
    final days = <String>[];
    final stay = stayOf(t);
    if (stay != null) {
      final from = DateTime.tryParse('${r[stay.from.id] ?? ''}'), to = DateTime.tryParse('${r[stay.to.id] ?? ''}');
      for (var d = from; d != null && to != null && d.isBefore(to) && days.length < 60; d = DateTime(d.year, d.month, d.day + 1)) {
        days.add('${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      }
    } else {
      final f = t.fields.where((f) => (f.type == 'date' || f.type == 'datetime') && !f.managerOnly).firstOrNull;
      final v = '${r[f?.id] ?? ''}';
      if (v.length >= 10) days.add(v.substring(0, 10));
    }
    for (final d in days) {
      final why = await closedOn(d);
      if (why != null) throw AppDataError(closedMessage(d, why));
    }
  }

  // ---------------- the manager's dashboard ----------------

  /// The numbers on the manager's dashboard: today's bookings, open orders, takings, the last
  /// 14 days of each kind of record, and the busiest hours. Manager only (it has the takings).
  Future<Map<String, Object?>> stats({DateTime? now}) async {
    now ??= DateTime.now();
    String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final today = ymd(now);
    final days = [for (var i = 13; i >= 0; i--) ymd(DateTime(now.year, now.month, now.day - i))];
    final ended = RegExp(r'done|complet|collected|delivered|cancel|finish|closed|no.?show|served|redeemed|attended|checked out|viewed|declin|reject', caseSensitive: false);
    final cancelled = RegExp(r'cancel|no.?show|declin|reject', caseSensitive: false);
    var bookingsToday = 0, openOrders = 0, newToday = 0, ordersToday = 0;
    num revenueToday = 0, revenueWeek = 0;
    final hours = List<int>.filled(24, 0);
    final tables = <String, Object?>{};
    for (final t in spec.tables.where((t) => t.access.add && !t.single)) {
      final rows = await list(t.id, manager: true, limit: 100000);
      final st = statusOf(t);
      final dateF = t.fields.where((f) => f.type == 'date' || f.type == 'datetime').firstOrNull;
      final timeF = t.fields.where((f) => f.type == 'time').firstOrNull;
      final prices = await _prices(t);
      final isOrder = prices.isNotEmpty;
      final counts = List<int>.filled(14, 0);
      for (final r in rows) {
        final made = '${r['created_at'] ?? ''}'; // "YYYY-MM-DD HH:MM", this computer's time
        final madeDay = made.length >= 10 ? made.substring(0, 10) : '';
        final i = days.indexOf(madeDay);
        if (i >= 0) counts[i]++;
        if (madeDay == today) newToday++;
        final status = st == null ? '' : '${r[st.id] ?? ''}';
        if (cancelled.hasMatch(status)) continue;
        final on = dateF == null ? '' : '${r[dateF.id] ?? ''}';
        if (!isOrder && on.startsWith(today)) bookingsToday++;
        if (isOrder) {
          if (st != null && !ended.hasMatch(status)) openOrders++;
          if (madeDay == today) ordersToday++;
          final tot = await orderTotal(t.id, r, prices: prices);
          if (tot != null && madeDay == today) revenueToday += tot.total;
          if (tot != null && madeDay.isNotEmpty && madeDay.compareTo(days[7]) >= 0) revenueWeek += tot.total;
        }
        // When it happens: the time booked, else when it came in.
        final at = _minutes(timeF == null ? null : r[timeF.id]) ?? _minutes(made.length > 11 ? made.substring(11) : null);
        if (at != null) hours[at ~/ 60 % 24]++;
      }
      tables[t.id] = {'title': t.title, 'kind': isOrder ? 'orders' : (dateF != null ? 'bookings' : 'requests'), 'total': rows.length, 'counts': counts};
    }
    return {
      'today': today,
      'currency': spec.site['currency'] ?? '',
      'bookings_today': bookingsToday,
      'open_orders': openOrders,
      'orders_today': ordersToday,
      'new_today': newToday,
      'revenue_today': (revenueToday * 100).round() / 100,
      'revenue_7d': (revenueWeek * 100).round() / 100,
      'days': days,
      'tables': tables,
      'hours': hours,
    };
  }
}
