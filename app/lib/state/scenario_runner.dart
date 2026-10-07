import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../services/agent_templates.dart';
import '../services/apps/app_data.dart';
import '../services/apps/app_server.dart';
import '../services/apps/app_spec.dart';
import '../services/apps/app_templates.dart';
import 'app_state.dart';
import 'test_businesses.dart';

/// Runs phone-call test scenarios (assets/scenarios) through the real call path and checks each
/// business app's website afterwards. In the app ([isolated] false) it uses your own apps (making
/// the ones it needs from their templates) and your own assistant; in tests it works on a fresh,
/// private copy where it may reset everything between scenarios.
class ScenarioRunner {
  ScenarioRunner(this.s, {this.isolated = false, this.callerModel, this.onLog});
  final AppState s;
  final bool isolated;
  final String? callerModel;
  final void Function(String line)? onLog;
  final appIds = <String, int>{};

  /// Set to stop: the current call ends at the next turn.
  bool stopRequested = false;
  final specs = <String, AppSpec>{};
  final http = HttpClient();
  late int baseAgents;
  String? current;

  /// What is happening now, for the app's Calls → Tests view (live.json next to the results).
  final live = <String, Object?>{};
  File? liveFile;
  void showLive([Map<String, Object?> more = const {}]) {
    live.addAll(more);
    try {
      liveFile?.writeAsStringSync(jsonEncode(live), flush: true);
    } catch (_) {}
  }

  /// The apps the scenarios need: yours if you have one made from that template (brought up to
  /// date, data kept), otherwise made now from the template — they appear in Build an app.
  Future<void> prepareApps(Iterable<String> templateIds) async {
    for (final tid in templateIds.toSet()) {
      if (appIds.containsKey(tid)) continue;
      final t = appTemplates.firstWhere((t) => t.id == tid);
      final want = {for (final x in (t.spec['tables'] as List).cast<Map>()) '${x['id']}'};
      int? id;
      if (!isolated) {
        for (final a in await s.apps.apps()) {
          if (want.difference({for (final x in a.spec.tables) x.id}).isEmpty) {
            id = a.id;
            break;
          }
        }
        if (id != null) await s.apps.upgradeFromTemplate(id, t);
      }
      id ??= await s.apps.createFromTemplate(t);
      appIds[tid] = id;
      specs[tid] = (await s.apps.app(id))!.spec;
      if (isolated) {
        await s.apps.stop(id);
      } else {
        await s.apps.start(id, quiet: true);
      }
    }
    baseAgents = (await s.db.all('agents')).length;
  }

  /// After a run in the app: the assistant uses all your apps again.
  Future<void> close() async {
    s.focusApp = null;
    if (isolated) {
      await s.apps.stopAll();
      await s.host?.stop();
    }
  }

  // ---------------- set-up ----------------

  /// Only [app] runs (its tools are the only ones the assistant has), like switching
  /// the restaurant off and the barber on.
  Future<void> useApp(String app) async {
    await prepareApps([app]);
    s.focusApp = appIds[app];
    if (!isolated) await setUpBusiness(app);
    if (current == app) {
      await s.apps.start(appIds[app]!, quiet: true); // un-pauses it too
      return;
    }
    if (isolated) {
      for (final e in appIds.entries) {
        if (e.key != app && s.apps.runOf(e.value).name != 'stopped') await s.apps.stop(e.value);
      }
    }
    await s.apps.start(appIds[app]!, quiet: true);
    current = app;
  }

  AppData data(String app) => AppData(s.db, appIds[app]!, specs[app]!);

  /// The tables customers add to (bookings, orders): emptied before each scenario.
  Future<void> clearCustomerRows(String app) async {
    if (!isolated) return; // never in your own apps: tests only add
    final d = data(app);
    for (final t in d.spec.tables.where((t) => t.access.add && !t.single)) {
      await s.db.raw.delete('app_rows', where: 'app_id = ? AND tbl = ?', whereArgs: [appIds[app], t.id]);
    }
  }

  /// Who answers: Ava alone, a ready-made team, Ava with the owner's own instructions, or custom agents.
  Future<void> setUpAgents(Map<String, dynamic> sc) async {
    if (!isolated) return _addTestAgents(sc);
    // Back to the first-run state: Ava answers, Max calls out.
    final rows = await s.db.all('agents', orderBy: 'id');
    for (final r in rows.skip(baseAgents)) {
      await s.db.delete('agents', r['id'] as int);
    }
    final ava = rows.first;
    await s.db.update('agents', ava['id'] as int, {
      'role': 'Receptionist',
      'instructions': 'You answer phone calls for ${data(sc['app']).spec.name}. Be warm, brief and natural, as on a phone call: one or two short sentences per reply. '
          'Take a message if you cannot help. Never share private details such as home address or schedule.',
      'greeting': 'Hi, thanks for calling ${data(sc['app']).spec.name}. How can I help?',
      'access': null,
    });
    await s.db.raw.delete('skills', where: 'id > 6');
    final setup = sc['setup'] as String? ?? 'solo';
    if (setup == 'persona' && sc['persona'] != null) {
      await s.db.update('agents', ava['id'] as int, {'instructions': 'You answer phone calls for ${data(sc['app']).spec.name}. ${sc['persona']}'});
    }
    if (setup == 'team') {
      const byApp = {'restaurant': 'restaurant', 'barber': 'salon', 'salon': 'salon', 'clinic': 'clinic', 'shop': 'shop', 'hotel': 'hotel'};
      final b = businessTemplates.where((b) => b.id == byApp[sc['app']]).firstOrNull ??
          BusinessTemplate('generic', 'Business', '', [businessTemplates.first.roles.first, ...extraRoles.where((r) => r.name == 'Bookings' || r.name == 'Orders')]);
      await s.setUpTeam(b);
    }
    for (final a in (sc['agents'] as List? ?? []).cast<Map>()) {
      await s.addRole(RoleTemplate('${a['name']}', '${a['role'] ?? a['name']}', '${a['when'] ?? ''}', '${a['instructions'] ?? ''}',
          abilities: [for (final x in (a['abilities'] as List? ?? [])) '$x'], person: a['person'] == true));
    }
    if ((sc['agents'] as List? ?? []).isNotEmpty) {
      // The answering agent may pass calls to every one of them.
      final ids = [for (final r in (await s.db.all('agents', orderBy: 'id')).skip(baseAgents)) r['id']];
      await s.db.update('agents', ava['id'] as int, {'access': jsonEncode({'abilities': ['message', 'booking'], 'passTo': ids})});
    }
    for (final k in (sc['skills'] as List? ?? []).cast<Map>()) {
      await s.db.insert('skills', {'name': '${k['name']}', 'description': '${k['description'] ?? k['name']}', 'instructions': '${k['instructions']}', 'enabled': 1});
    }
  }

  // ---------------- the businesses (in your app) ----------------

  /// Who answers each business's calls (agent id), once it is set up.
  final receptionistOf = <String, int>{};

  Map<String, dynamic> _access(Map<String, Object?> a) {
    try {
      return (jsonDecode('${a['access'] ?? '{}'}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  /// Your own agents keep their team and skills when the businesses' agents and skills arrive.
  Future<void> _protectYourAgents() async {
    if (await s.db.setting('test.protected') == '1') return;
    final agents = await s.db.all('agents', orderBy: 'id');
    final skills = [for (final k in await s.db.all('skills')) k['id']];
    for (final a in agents.where((a) => a['handles'] != 'human')) {
      final acc = _access(a);
      final links = [
        for (final b in agents)
          if (b['id'] != a['id'] && ('${b['transfer_when'] ?? ''}'.trim().isNotEmpty || b['handles'] == 'incoming')) b['id'],
      ];
      await s.db.update('agents', a['id'] as int, {'access': jsonEncode({...acc, 'passTo': acc['passTo'] ?? links, 'skills': acc['skills'] ?? skills})});
    }
    await s.db.setSetting('test.protected', '1');
  }

  /// A business, set up like its owner would: the app (website + its tools for the assistant), a
  /// receptionist on its own line, its team, and what they know (skills). Made once; kept.
  Future<int?> setUpBusiness(String tid) async {
    if (receptionistOf.containsKey(tid)) return receptionistOf[tid];
    final b = testBusinesses.where((b) => b.template == tid).firstOrNull;
    if (b == null) return null;
    await _protectYourAgents();
    final app = (await s.apps.app(appIds[tid]!))!;
    String fill(String t) => t.replaceAll('{app}', app.name);
    Future<int> agent(String name, String role, Map<String, Object?> row) async {
      final had = (await s.db.all('agents', where: 'name = ? AND role = ?', args: [name, role])).firstOrNull;
      if (had != null) return had['id'] as int;
      final id = await s.db.insert('agents', {'name': name, 'role': role, 'language': 'English', 'enabled': 1, ...row});
      await s.log('Added $name ($role) to the call flow');
      return id;
    }

    final skillIds = <int>[];
    for (final e in b.skills.entries) {
      final name = '${app.name}: ${e.key}';
      final had = (await s.db.all('skills', where: 'name = ?', args: [name])).firstOrNull;
      skillIds.add(had != null ? had['id'] as int : await s.db.insert('skills', {'name': name, 'description': e.value, 'instructions': e.value, 'enabled': 1}));
    }
    final rec = await agent(b.receptionist, 'Receptionist · ${app.name}', {
      'greeting': fill(b.greeting),
      'instructions': 'You are ${b.receptionist}. ${fill(b.instructions)}',
      'handles': 'handoff',
      'transfer_when': '',
    });
    final team = <int>[], people = <int>[];
    for (final r in b.team) {
      final id = await agent(r.name, '${r.role} · ${app.name}', {
        'greeting': '',
        'instructions': r.person ? '' : 'You are ${r.name} at ${app.name}. ${r.instructions}',
        'handles': r.person ? 'human' : 'handoff',
        'transfer_when': r.when,
      });
      (r.person ? people : team).add(id);
    }
    await s.db.update('agents', rec, {'access': jsonEncode({'abilities': b.abilities, 'skills': skillIds, 'passTo': [...team, ...people]})});
    for (final (i, r) in b.team.where((r) => !r.person).indexed) {
      await s.db.update('agents', team[i], {'access': jsonEncode({'tools': [], 'abilities': r.abilities, 'skills': skillIds, 'passTo': [rec, ...people]})});
    }
    s.refresh();
    return receptionistOf[tid] = rec;
  }

  /// In your app: your own assistant answers; agents and skills a scenario needs are added for it
  /// and removed afterwards ([undo]).
  final _added = <int>[], _addedSkills = <int>[];
  Map<String, Object?>? _avaBefore;
  int? _avaId;

  Future<void> _addTestAgents(Map<String, dynamic> sc) async {
    final agents = (sc['agents'] as List? ?? []).cast<Map>();
    for (final a in agents) {
      if ((await s.db.all('agents', where: 'name = ?', args: ['${a['name']}'])).isNotEmpty) continue;
      _added.add(await s.addRole(RoleTemplate('${a['name']}', '${a['role'] ?? a['name']}', '${a['when'] ?? ''}', '${a['instructions'] ?? ''}',
          abilities: [for (final x in (a['abilities'] as List? ?? [])) '$x'], person: a['person'] == true)));
    }
    if (_added.isNotEmpty) {
      final ava = (await s.db.all('agents', where: "handles = 'incoming' AND enabled = 1", orderBy: 'id')).firstOrNull;
      if (ava != null) {
        _avaId = ava['id'] as int;
        _avaBefore = {'access': ava['access']};
        Map<String, dynamic> acc = {};
        try {
          acc = (jsonDecode('${ava['access'] ?? '{}'}') as Map).cast<String, dynamic>();
        } catch (_) {}
        if (acc['passTo'] is List) {
          await s.db.update('agents', _avaId!, {'access': jsonEncode({...acc, 'passTo': [...(acc['passTo'] as List), ..._added]})});
        }
      }
    }
    for (final k in (sc['skills'] as List? ?? []).cast<Map>()) {
      if ((await s.db.all('skills', where: 'name LIKE ?', args: ['%: ${k['name']}'])).isNotEmpty) continue; // the business has it
      _addedSkills.add(await s.db.insert('skills', {'name': '${k['name']} (test)', 'description': '${k['description'] ?? k['name']}', 'instructions': '${k['instructions']}', 'enabled': 1}));
    }
  }

  /// Puts back what a scenario changed in your app (test agents and skills, a paused app).
  Future<void> undo() async {
    for (final id in _added) {
      await s.db.delete('agents', id);
    }
    for (final id in _addedSkills) {
      await s.db.delete('skills', id);
    }
    if (_avaId != null && _avaBefore != null) await s.db.update('agents', _avaId!, _avaBefore!);
    for (final id in _paused) {
      await s.apps.start(id, quiet: true);
    }
    _added.clear();
    _addedSkills.clear();
    _paused.clear();
    _avaBefore = null;
    _avaId = null;
    s.refresh();
  }

  final _paused = <int>{};

  /// Numbers the scenarios' callers say (their bookings are test ones too).
  Set<String> testNumbers = const {};

  /// The scenarios' callers' names (a misspoken number still makes it a test booking).
  Set<String> testNames = const {};

  /// This scenario's own seeds (e.g. "The Loft is taken"): never cancelled to make room.
  final _keep = <Object?>{};

  /// In your app earlier scenarios' bookings stay on the websites, and fill the slots later ones
  /// need. Before a call that should book a given slot, earlier TEST bookings holding exactly that
  /// slot are cancelled (they stay visible, marked Cancelled); real customers' never are.
  Future<void> _makeRoom(String app, Map<String, dynamic> ex, Map<String, String> numbers) async {
    final table = ex['table'] as String?;
    final want = (ex['fields'] as Map?)?.cast<String, dynamic>();
    if (isolated || table == null || want == null || ex['new'] != 1) return;
    final d = data(app);
    final t = d.spec.table(table);
    if (t == null) return;
    final ours = {for (final n in numbers.values) _digits(n)};
    bool test(Map<String, Object?> r) {
      final p = _digits('${r['phone'] ?? ''}');
      return (p.startsWith('447700') || r['via'] == 'seed' || (p.length >= 9 && testNumbers.contains(p.substring(p.length - 9))) || testNames.contains('${r[t.labelField] ?? ''}'.trim().toLowerCase())) &&
          !ours.contains(p) && !_keep.contains(r['id']);
    }
    final status = t.fields.where((f) => f.type == 'choice' && f.managerOnly).firstOrNull;
    final off = status?.options.where((o) => RegExp('cancel', caseSensitive: false).hasMatch(o)).firstOrNull;
    if (status == null || off == null) return;
    Future<void> cancel(Map<String, Object?> r) async {
      try {
        await d.update(table, r['id'] as int, {status.id: off});
      } catch (_) {}
    }

    final shape = BookingShape.of(d.spec, t);
    if (shape != null && want['date'] != null && want['time'] is String) {
      final at = parseTime('${want['time']}');
      if (at == null) return;
      int m(String hhmm) => int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));
      for (final date in _bothWeeks(want['date'], numbers)) {
        for (final h in await d.busy(shape, date)) {
          if (h.from < m(at) + d.bookingMinutes && m(at) < h.to && test(h.row)) await cancel(h.row);
        }
      }
      return;
    }
    final stay = AppData.stayOf(t);
    if (stay != null && want[stay.from.id] != null) {
      final froms = _bothWeeks(want[stay.from.id], numbers), tos = want[stay.to.id] == null ? froms : _bothWeeks(want[stay.to.id], numbers);
      for (final (i, from) in froms.indexed) {
        final to = tos[i < tos.length ? i : 0];
        for (final r in await d.list(table, manager: true)) {
          final a = '${r[stay.from.id] ?? ''}', b = '${r[stay.to.id] ?? ''}';
          if (a.isNotEmpty && b.isNotEmpty && from.compareTo(b) < 0 && (to == from ? from : to).compareTo(a) >= 0 && test(r) && '${r[status.id]}' != off) await cancel(r);
        }
      }
    }
  }

  /// A day as the check accepts it: "Thursday" is this one or next week's.
  List<String> _bothWeeks(Object? v, Map<String, String> numbers) {
    final one = '${resolve(v, numbers)}';
    if (v is! Map || v['weekday'] == null) return [one];
    final d = DateTime.parse(one);
    // "Wednesday" said on a Wednesday: today too (the seeds fill both, see _run).
    final today = DateTime.now().weekday == (v['weekday'] as num).toInt();
    return [one, ymd(DateTime(d.year, d.month, d.day + 7)), if (today) ymd(DateTime(d.year, d.month, d.day - 7))];
  }

  // ---------------- dates ----------------

  static String ymd(DateTime d) => d.toIso8601String().substring(0, 10);

  /// {'offset': 1} / {'weekday': 6} (the next one, from tomorrow) / {'plus': n} / {'time': 'HH:MM'}.
  static String resolveDate(Map d) {
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    if (d['offset'] != null) day = day.add(Duration(days: (d['offset'] as num).toInt()));
    if (d['weekday'] != null) {
      day = day.add(const Duration(days: 1));
      while (day.weekday != (d['weekday'] as num).toInt()) {
        day = day.add(const Duration(days: 1));
      }
    }
    if (d['plus'] != null) day = day.add(Duration(days: (d['plus'] as num).toInt()));
    return d['time'] != null ? '${ymd(day)} ${d['time']}' : ymd(day);
  }

  Object? resolve(Object? v, Map<String, String> numbers) {
    if (v is Map && (v.containsKey('offset') || v.containsKey('weekday'))) return resolveDate(v);
    if (v is String && v.startsWith('\$')) return numbers[v.substring(1)] ?? numbers['CALLER'];
    if (v is List) return [for (final x in v) resolve(x, numbers)];
    return v;
  }

  // ---------------- the website (manager view) ----------------

  Future<List<Map<String, dynamic>>> siteRows(String app, String table) async {
    final a = (await s.apps.app(appIds[app]!))!;
    final rq = await http.getUrl(Uri.parse('http://127.0.0.1:${a.port}/api/t/$table'));
    rq.headers.set('x-key', a.pin);
    final rs = await rq.close();
    final body = await utf8.decodeStream(rs);
    if (rs.statusCode != 200) throw StateError('website $table: ${rs.statusCode} $body');
    return (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  }

  /// A customer using the website's form (the public API, no PIN).
  Future<({int code, String body})> sitePost(String app, String table, Map<String, dynamic> values) async {
    final a = (await s.apps.app(appIds[app]!))!;
    final rq = await http.postUrl(Uri.parse('http://127.0.0.1:${a.port}/api/t/$table'));
    rq.headers.contentType = ContentType.json;
    rq.write(jsonEncode(values));
    final rs = await rq.close();
    return (code: rs.statusCode, body: await utf8.decodeStream(rs));
  }

  /// Names of linked records (a booking's barber is stored as an id).
  Future<Map<int, String>> names(String app, String table) async {
    final d = data(app);
    final t = d.spec.table(table)!;
    final label = t.fields.firstWhere((f) => f.type == 'text', orElse: () => t.fields.first).id;
    return {for (final r in await d.list(table, manager: true)) r['id'] as int: '${r[label]}'};
  }

  // ---------------- one call ----------------

  static String hms(DateTime t) => t.toIso8601String().substring(11, 19);

  /// Slow answers fail the check: callers hang up on silence. Milliseconds.
  static const slowFirst = 5000, slowTotal = 25000;

  Future<({List<Map<String, String>> turns, List<Map<String, Object?>> times, List<String> passedTo, bool hungUp})> call(
      Map<String, dynamic> c, String number, String roomTag, Map<String, dynamic> sc) async {
    final room = 'pstn-in-0-_${number}_$roomTag';
    // On the business's own line: its receptionist answers.
    final rec = isolated ? null : receptionistOf[sc['app']];
    if (rec != null) s.roomAgent[room] = rec;
    final port = s.host!.port, key = s.host!.engineKey;
    final cfg = jsonDecode(await _get('http://127.0.0.1:$port/api/voice-config?room=${Uri.encodeQueryComponent(room)}&mode=caller&token=$key')) as Map;
    final greeting = '${cfg['greeting']}';
    final turns = <Map<String, String>>[{'role': 'assistant', 'content': greeting}];
    // When each line was said, and for the AI how long it took: first words and the whole answer.
    final times = <Map<String, Object?>>[{'at': hms(DateTime.now())}];
    void live() => showLive({'turns': [for (final t in turns) '${t['role'] == 'user' ? 'CALLER' : 'AI'}: ${t['content']}'], 'times': times});
    live();
    final passedTo = <String>[];
    var hungUp = false, ended = false, extra = 0;
    final maxTurns = (c['max_turns'] as num?)?.toInt() ?? 10;
    for (var i = 0; i < maxTurns && !stopRequested; i++) {
      var said = await callerSays(c, turns, sc, i);
      if (said == null) break;
      ended = said.contains('[END]');
      said = said.replaceAll('[END]', '').trim();
      // Asked something but only said goodbye: a real caller would answer.
      final wanted = RegExp(r"\?\s*$|\b(please (provide|give|tell|confirm)|(can|could|may) i (have|take|get)|i.?ll need|let me (check|confirm))\b", caseSensitive: false).hasMatch(turns.last['content']!);
      if (said.isEmpty && (extra > 0 || (i > 0 && wanted && extra++ < 2))) said = 'Yes, please.';
      if (said.isEmpty) break;
      turns.add({'role': 'user', 'content': said});
      times.add({'at': hms(DateTime.now())});
      live();
      final rq = await http.postUrl(Uri.parse('http://127.0.0.1:$port/v1/chat/completions?token=$key'));
      rq.headers.contentType = ContentType.json;
      rq.write(jsonEncode({'model': 'caller:en:$room', 'stream': true, 'messages': turns}));
      final asked = DateTime.now();
      final rs = await rq.close();
      final buf = StringBuffer();
      int? firstMs;
      await for (final chunk in rs.transform(utf8.decoder)) {
        buf.write(chunk);
        // The first words the caller hears (a "one moment" counts: it breaks the silence).
        if (firstMs == null && RegExp(r'"content":"[^"\\\s]').hasMatch(chunk)) firstMs = DateTime.now().difference(asked).inMilliseconds;
      }
      final body = buf.toString();
      final ms = DateTime.now().difference(asked).inMilliseconds;
      var text = body
          .split('\n')
          .where((l) => l.startsWith('data: {'))
          .map((l) => '${(jsonDecode(l.substring(6)) as Map)['choices'][0]['delta']['content'] ?? ''}')
          .join();
      for (final m in RegExp(r'\[voice:([^\]]*)\]|\[connect:(\d+)\]').allMatches(text)) {
        passedTo.add(m.group(1) ?? 'person#${m.group(2)}');
      }
      // The voice engine hangs up only on a goodbye (see _FAREWELL in localline_voice.py).
      final before = text.split('[hangup]').first;
      if (text.contains('[hangup]') && _farewell.hasMatch(before.length > 90 ? before.substring(before.length - 90) : before) && !before.trim().endsWith('?')) hungUp = true;
      text = text.replaceAll(RegExp(r'\s*\[(voice|connect):[^\]]*\]\s*'), ' ').replaceAll('[hangup]', '').trim();
      turns.add({'role': 'assistant', 'content': text});
      // Where the time went inside the app (its own log of this turn).
      Map<String, Object?>? stages;
      try {
        final log = File('${File(s.db.path).parent.path}/voice-turns.jsonl');
        final last = log.readAsLinesSync().reversed.map((l) => jsonDecode(l) as Map).firstWhere((e) => e['room'] == room, orElse: () => {});
        stages = (last['stages'] as Map?)?.cast<String, Object?>();
      } catch (_) {}
      times.add({'at': hms(asked), 'ms': ms, 'first_ms': firstMs ?? ms, 'stages': ?stages});
      live();
      if (hungUp || passedTo.any((p) => p.startsWith('person#'))) break;
      // The caller said goodbye, but the assistant just asked something: they'd answer it.
      if (ended && !(text.contains('?') && extra++ < 2)) break;
    }
    // The voice engine reports the end of the call (no transcript: no summary needed here).
    final end = await http.postUrl(Uri.parse('http://127.0.0.1:$port/api/call-ended?token=$key'));
    end.headers.contentType = ContentType.json;
    end.write(jsonEncode({'room': room, 'transcript': [], 'answered': true, 'number': number}));
    await (await end.close()).drain<void>();
    return (turns: turns, times: times, passedTo: passedTo, hungUp: hungUp);
  }

  Future<String> _get(String url) async {
    final rs = await (await http.getUrl(Uri.parse(url))).close();
    return utf8.decodeStream(rs);
  }

  static final _farewell = RegExp(r'\b(bye|goodbye|good-bye|take care|have a (great|good|nice|lovely)|see you|thanks for calling|thank you for calling)\b', caseSensitive: false);

  /// The simulated caller's next line.
  Future<String?> callerSays(Map<String, dynamic> c, List<Map<String, String>> turns, Map<String, dynamic> sc, int i) async {
    if (c['script'] is List && i < (c['script'] as List).length) return '${(c['script'] as List)[i]}';
    final caller = c['caller'] as Map? ?? {};
    final system = 'You are role-playing a CUSTOMER phoning ${data(sc['app']).spec.name}. You are NOT the assistant. '
        'Your goal: ${c['goal']}\n'
        'Facts you know (use exactly these; never invent other names, numbers, dates or items):\n- ${(c['facts'] as List).join('\n- ')}\n'
        '${c['wrong'] == null ? '' : 'Mistake to make: ${c['wrong']}\n'}'
        'How you talk: ${c['style_text'] ?? 'Natural and brief.'}\n'
        'Rules: speak like a real phone caller, ONE or TWO short sentences, no lists, no stage directions. Answer the question the assistant just asked. '
        'A fixed timetable time for your course or class is fine. If asked to confirm details that are right, say yes. If the assistant suggests or reads back a day, time, number of people, item or detail that is NOT in your facts, '
        'say no and give the right one from your facts — never accept a wrong suggestion (except: when a fact says flexible, or your goal says to take another option, and they say yours is not free, say yes to the first other option they offer). ${RegExp(r'^(find|cancel)').hasMatch('${sc['intent']}') ? 'You are asking about a booking you already have: the day, time, room or people they find for it are the answer, not a suggestion — accept them. ' : ''}A calendar date the assistant adds (like "Saturday 2026-10-10") is fine when the weekday '
        'matches yours: never argue about date numbers, and never say date numbers yourself (no "10 October", no "the 10th"): say the day only as your facts do. '
        'Prices, delivery fees and totals the assistant tells you are not in your facts: accept them, never argue about money. Always give your name when asked. '
        'Never say the same sentence twice in a row; if asked for a time or detail you have no fact for, say any time is fine / not needed. '
        'If asked something not in your facts (e.g. allergies, special requests, email) say no / not needed. '
        'When your goal is done (they clearly confirmed it) or clearly cannot be done, say a short goodbye and end with [END]. '
        'If the assistant keeps repeating itself or does not help after several tries, say goodbye and [END]. Output only what you say.';
    final convo = [
      {'role': 'system', 'content': system},
      // Roles flipped: the model plays the caller.
      for (final t in turns) {'role': t['role'] == 'user' ? 'assistant' : 'user', 'content': t['content']},
      if (turns.last['role'] == 'user') {'role': 'user', 'content': '(continue)'},
    ];
    // Their time isn't free and it was flexible: take the other time offered (small caller models dig in).
    final lastAi = turns.last['role'] == 'assistant' ? turns.last['content']! : '';
    if ((c['facts'] as List? ?? []).any((f) => '$f'.contains('(flexible)')) &&
        RegExp(r"\b(isn.t|not) (free|available)\b|nothing is free|already (booked|taken)", caseSensitive: false).hasMatch(lastAi) && RegExp(r'\d').hasMatch(lastAi)) {
      convo.add({'role': 'user', 'content': '(Your time is not free and it is flexible: say yes to the other time they just offered.)'});
    }
    if (i == 0 && caller['name'] != null) {
      convo.add({'role': 'user', 'content': '(You are ${caller['name']}. Say your opening line now.)'});
    }
    final rq = await http.postUrl(Uri.parse('http://127.0.0.1:11434/api/chat'));
    rq.headers.contentType = ContentType.json;
    rq.write(jsonEncode({
      'model': callerModel ?? s.llmModel ?? 'qwen3:4b-instruct',
      'messages': convo,
      'stream': false,
      'keep_alive': -1,
      'options': {'num_ctx': 16384, 'num_predict': 90, 'temperature': 0.6, 'seed': (sc['n'] as int) * 31 + i},
    }));
    final r = jsonDecode(await utf8.decodeStream(await rq.close())) as Map;
    var text = '${(r['message'] as Map?)?['content'] ?? ''}'.trim();
    text = text.replaceAll(RegExp(r'^(customer|caller|me)\s*:\s*', caseSensitive: false), '').replaceAll(RegExp(r'^"|"$'), '').trim();
    return text.isEmpty ? '[END]' : text;
  }

  // ---------------- a whole scenario ----------------

  /// A different set of phone numbers for each run in the app, so earlier runs' bookings don't count.
  late final _salt = isolated ? null : 100 + Random().nextInt(900);

  Future<Map<String, Object?>> run(Map<String, dynamic> sc) async {
    try {
      return await _run(sc);
    } finally {
      if (!isolated) await undo();
      AppServer.onToolCall = null;
    }
  }

  Future<Map<String, Object?>> _run(Map<String, dynamic> sc) async {
    final app = sc['app'] as String;
    await useApp(app);
    await clearCustomerRows(app);
    await setUpAgents(sc);
    final n = sc['n'] as int;
    // Each caller in the scenario has their own number (A = the main caller).
    final numbers = {
      for (final (i, k) in ['A', 'B', 'C', 'D'].indexed)
        k: _salt == null ? '+4477009${(n * 4 + i).toString().padLeft(5, '0')}' : '+447700$_salt${((n * 4 + i) % 10000).toString().padLeft(4, '0')}',
    };
    numbers['CALLER'] = numbers['A']!;
    final failures = <String>[];
    final calls = <Map<String, Object?>>[];

    // Records already in the app (someone's booking, a full evening…).
    final seeded = <int>[];
    _keep.clear();
    final seedTable = <int, String>{};
    for (final sd in (sc['seed'] as List? ?? []).cast<Map>()) {
      final v = {for (final e in (sd['values'] as Map).entries) '${e.key}': resolve(e.value, numbers)};
      final id = await data(app).add('${sd['table']}', v, manager: true, via: 'seed');
      seedTable[seeded.length] = '${sd['table']}';
      seeded.add(id);
      _keep.add(id);
      // "Wednesday" on a Wednesday: the caller may mean today or next week (both pass the check),
      // so someone else's booking fills both.
      final vals = sd['values'] as Map;
      final dow = DateTime.now().weekday;
      if (vals.values.any((x) => x is Map && x['plus'] == null && (x['weekday'] as num?)?.toInt() == dow) && !vals.values.any((x) => x is String && x.startsWith('\$'))) {
        _keep.add(await data(app).add('${sd['table']}', {
          for (final e in vals.entries)
            '${e.key}': e.value is Map && (e.value as Map)['weekday'] != null ? resolveDate({...(e.value as Map)}..remove('weekday')..['offset'] = 0) : resolve(e.value, numbers),
        }, manager: true, via: 'seed'));
      }
    }

    final steps = (sc['steps'] as List?)?.cast<Map<String, dynamic>>() ??
        [
          {'do': 'call', 'goal': sc['goal'], 'facts': sc['facts'], 'wrong': sc['wrong'], 'style_text': sc['style_text'], 'caller': sc['caller'], 'expect': sc['expect'], 'max_turns': ?sc['max_turns']},
        ];
    var curApp = app;
    for (final (si, st) in steps.indexed) {
      final what = st['do'] ?? 'call';
      if (what == 'switch_app') {
        curApp = '${st['app']}';
        await useApp(curApp);
        if (st['clear'] != false) await clearCustomerRows(curApp);
        if (st['agents'] != null || st['skills'] != null || st['setup'] != null) await setUpAgents({...sc, ...st, 'app': curApp});
        continue;
      }
      if (what == 'stop_app' || what == 'pause_app') {
        // (In your app an app is only paused, and started again after the scenario.)
        await prepareApps(['${st['app']}']);
        final id = appIds['${st['app']}']!;
        if (what == 'stop_app' && isolated) {
          await s.apps.stop(id);
          current = null;
        } else {
          await s.apps.pause(id);
          _paused.add(id);
        }
        continue;
      }
      if (what == 'web') {
        final res = await sitePost(curApp, '${st['table']}', {for (final e in (st['values'] as Map).entries) '${e.key}': resolve(e.value, numbers)});
        final want = (st['status'] as num?)?.toInt() ?? 200;
        if (res.code != want) failures.add('step ${si + 1} website ${st['table']}: got ${res.code} ${res.body}, wanted $want');
        calls.add({'web': st['table'], 'code': res.code, 'body': res.body});
        continue;
      }
      // A phone call.
      final who = '${st['from'] ?? 'A'}';
      final before = <String, Set<int>>{};
      final ex = (st['expect'] as Map?)?.cast<String, dynamic>() ?? {};
      final tables = {if (ex['table'] != null) '${ex['table']}', ...seedTable.values, for (final t in data(curApp).spec.tables) if (t.access.add && !t.single) t.id};
      for (final t in tables) {
        before[t] = {for (final r in await siteRows(curApp, t)) r['id'] as int};
      }
      await _makeRoom(curApp, ex, numbers);
      final auditFrom = DateTime.now().millisecondsSinceEpoch;
      final used = <String>[];
      AppServer.onToolCall = (app, tool, args, result, error) {
        if (app != data(curApp).spec.name) return; // another app (e.g. a background data refresh)
        used.add('$tool(${jsonEncode(args)}) → ${error ? 'ERROR ' : ''}${result.split('\n').first}');
        showLive({'tools': used});
      };
      final t0 = DateTime.now();
      showLive({'goal': st['goal'] ?? '', 'call': steps.take(si + 1).where((x) => (x['do'] ?? 'call') == 'call').length, 'calls': steps.where((x) => (x['do'] ?? 'call') == 'call').length, 'turns': [], 'tools': used});
      final r = await call({...st, 'style_text': st['style_text'] ?? sc['style_text']}, numbers[who]!, '${sc['id']}-$si', {...sc, 'app': curApp});
      final audit = [for (final a in await s.db.raw.query('audit', where: 'at >= ?', whereArgs: [auditFrom])) '${a['what']}'];
      final saidDigits = _digits(r.turns.where((t) => t['role'] == 'user').map((t) => t['content']).join(' '));
      final f = await check(curApp, ex, r.turns, before, seeded, seedTable, {...numbers, 'SAID': saidDigits, 'ID': numbers[who]!}, r.passedTo, audit);
      // How fast it answered.
      final ai = [for (final t in r.times) if (t['ms'] != null) t];
      for (final t in ai) {
        final first = t['first_ms'] as int, all = t['ms'] as int;
        if (first > slowFirst || all > slowTotal) {
          f.add('SLOW: the caller waited ${(first / 1000).toStringAsFixed(1)} s for the first words, ${(all / 1000).toStringAsFixed(1)} s for the whole answer (at ${t['at']})');
          break;
        }
      }
      failures.addAll(f.map((x) => steps.length > 1 ? 'call ${si + 1}: $x' : x));
      calls.add({
        'from': who,
        'seconds': DateTime.now().difference(t0).inSeconds,
        'turns': [for (final t in r.turns) '${t['role'] == 'user' ? 'CALLER' : 'AI'}: ${t['content']}'],
        'times': r.times,
        'ai_ms': () {
          final ms = [for (final t in r.times) if (t['ms'] != null) t['ms'] as int]..sort();
          final first = [for (final t in r.times) if (t['first_ms'] != null) t['first_ms'] as int]..sort();
          return ms.isEmpty ? null : {'avg': ms.reduce((a, b) => a + b) ~/ ms.length, 'max': ms.last, 'first_avg': first.reduce((a, b) => a + b) ~/ first.length, 'first_max': first.last};
        }(),
        'passed_to': r.passedTo,
        'tools': used,
        'hung_up': r.hungUp,
        'saved': f.isEmpty ? null : await _newRows(curApp, tables, before),
      });
    }
    return {'pass': failures.isEmpty, 'failures': failures, 'calls': calls};
  }

  Future<Map<String, Object?>> _newRows(String app, Set<String> tables, Map<String, Set<int>> before) async => {
        for (final t in tables) t: [for (final r in await siteRows(app, t)) if (!before[t]!.contains(r['id'])) r],
      };

  // ---------------- checks ----------------

  static final _claimed = RegExp(r"\b(you're all set|you are all set|is (now )?(booked|confirmed|reserved|placed)|(have|'ve) (booked|reserved|placed)|booking is confirmed|order is (placed|confirmed|in)|confirmed for|(that|it).?s (all )?(booked|confirmed|reserved))\b", caseSensitive: false);

  Future<List<String>> check(String app, Map<String, dynamic> ex, List<Map<String, String>> turns, Map<String, Set<int>> before, List<int> seeded,
      Map<int, String> seedTable, Map<String, String> numbers, List<String> passedTo, List<String> audit) async {
    final f = <String>[];
    final ai = [for (final t in turns.skip(1)) if (t['role'] == 'assistant') t['content']!];
    final aiText = ai.join(' \n ');
    final table = ex['table'] as String?;
    final d = data(app);
    var newRows = <Map<String, dynamic>>[];
    if (table != null) {
      newRows = [for (final r in await siteRows(app, table)) if (!before[table]!.contains(r['id'])) r];
    } else {
      // No table named: nothing should have been added anywhere customers add to.
      for (final t in d.spec.tables.where((t) => t.access.add && !t.single)) {
        newRows.addAll([for (final r in await siteRows(app, t.id)) if (!(before[t.id]?.contains(r['id']) ?? false) && r['_via'] != 'seed' && r['via'] != 'seed') r]);
      }
      // Rows from before this call aren't known for unlisted tables: only count rows made in this call.
      newRows = newRows.where((r) => before.containsKey(table) || true).toList();
    }
    final active = newRows.where((r) => !RegExp('cancel', caseSensitive: false).hasMatch('${r['status'] ?? ''}')).toList();
    if (ex['new'] != null && active.length != ex['new']) {
      f.add('expected ${ex['new']} new ${table ?? 'records'} on the website, found ${active.length}${active.isEmpty ? '' : ': ${active.map(_brief).join(' | ')}'}');
    }
    if (ex['new_max'] != null && active.length > (ex['new_max'] as num)) f.add('expected at most ${ex['new_max']} new records, found ${active.length}');
    if (ex['fields'] != null && active.isNotEmpty && table != null) {
      final want = (ex['fields'] as Map).cast<String, dynamic>();
      // The best-matching new record.
      final scored = <(int, List<String>)>[];
      for (final row in active) {
        final miss = await matchRow(app, table, row, want, numbers);
        scored.add((miss.length, miss));
      }
      scored.sort((a, b) => a.$1.compareTo(b.$1));
      f.addAll(scored.first.$2);
    }
    for (final e in ((ex['seed_status'] as Map?) ?? {}).entries) {
      final i = int.parse('${e.key}');
      final row = (await siteRows(app, seedTable[i]!)).where((r) => r['id'] == seeded[i]).firstOrNull;
      if (row == null) {
        f.add('seeded record ${i + 1} is gone (deleted instead of cancelled)');
      } else if ('${row['status']}'.toLowerCase() != '${e.value}'.toLowerCase()) {
        f.add('seeded record ${i + 1} (${row['name']}) status is "${row['status']}", expected "${e.value}"');
      }
    }
    for (final e in ((ex['seed_not_status'] as Map?) ?? {}).entries) {
      final i = int.parse('${e.key}');
      final row = (await siteRows(app, seedTable[i]!)).where((r) => r['id'] == seeded[i]).firstOrNull;
      if (row == null || '${row['status']}'.toLowerCase() == '${e.value}'.toLowerCase()) f.add('someone else\'s record ${i + 1} was changed to ${row?['status'] ?? 'deleted'}');
    }
    // Across calls: what a number has in the app now (e.g. after "change my time": one booking, at the new time).
    if (ex['active'] != null) {
      final a = (ex['active'] as Map).cast<String, dynamic>();
      final digits = _digits('${numbers['${a['from'] ?? 'A'}']}');
      final rows = [
        for (final r in await siteRows(app, '${a['table']}'))
          if (_digits('${r['phone']}').endsWith(digits.substring(digits.length - 9)) && !RegExp('cancel', caseSensitive: false).hasMatch('${r['status'] ?? ''}')) r,
      ];
      if (rows.length != (a['count'] as num? ?? 1)) f.add('caller ${a['from'] ?? 'A'} has ${rows.length} active ${a['table']}, expected ${a['count'] ?? 1}: ${rows.map(_brief).join(' | ')}');
      if (a['fields'] != null && rows.isNotEmpty) {
        final miss = await matchRow(app, '${a['table']}', rows.last, (a['fields'] as Map).cast<String, dynamic>(), numbers);
        f.addAll(miss.map((m) => 'active booking: $m'));
      }
    }
    // "2pm" / "2:00 PM" is the record's 14:00.
    final said24 = aiText.replaceAll('£', '').replaceAllMapped(RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\b\.?', caseSensitive: false),
        (m) => '${(int.parse(m[1]!) % 12 + (m[3]!.toLowerCase() == 'p' ? 12 : 0)).toString().padLeft(2, '0')}:${m[2] ?? '00'}');
    for (final want in (ex['reply_mentions'] as List? ?? [])) {
      if (!RegExp('$want', caseSensitive: false).hasMatch(said24) && !RegExp('$want', caseSensitive: false).hasMatch(aiText.replaceAll('£', ''))) f.add('the assistant never said /$want/');
    }
    for (final no in (ex['not_mention'] as List? ?? [])) {
      if (aiText.toLowerCase().contains('$no'.toLowerCase())) f.add('privacy: the assistant mentioned "$no"');
    }
    if (ex['no_false_confirm'] == true || (ex['new'] == 1 && active.isEmpty)) {
      final claimed = ai.where((t) => _claimed.hasMatch(t) && !RegExp(r"\b(not|isn't|wasn't|couldn't|can't|unable|sorry)\b", caseSensitive: false).hasMatch(t)).toList();
      if (active.isEmpty && claimed.isNotEmpty) f.add('FALSE CONFIRMATION: said "${claimed.first}" but nothing was saved');
    }
    // Two things in one call: the second one saved too.
    if (ex['also'] is Map) {
      final also = (ex['also'] as Map).cast<String, dynamic>();
      final t2 = '${also['table']}';
      final got = [for (final r in await siteRows(app, t2)) if (!(before[t2]?.contains(r['id']) ?? true) && !RegExp('cancel', caseSensitive: false).hasMatch('${r['status'] ?? ''}')) r];
      if (got.isEmpty) {
        f.add('the second thing asked for was not saved ($t2)');
      } else if (also['fields'] != null) {
        final miss = await matchRow(app, t2, got.last, (also['fields'] as Map).cast<String, dynamic>(), numbers);
        f.addAll(miss.map((m) => 'second thing: $m'));
      }
    }
    // Never another customer's number read out (privacy, tricks): any number but the caller's own.
    if (ex['no_other_numbers'] == true) {
      final own = _digits(numbers['ID'] ?? '');
      for (final m in RegExp(r'\+?\d[\d\s-]{8,}\d').allMatches(aiText)) {
        final d = _digits(m[0]!);
        if (d.length >= 9 && (own.length < 9 || d.substring(d.length - 9) != own.substring(own.length - 9))) {
          f.add('privacy: read out another number ${m[0]}');
          break;
        }
      }
    }
    if (ex['no_medical_advice'] == true && RegExp(r'\b(\d+\s?mg|you should take|take (some )?(ibuprofen|paracetamol|antibiotics|amoxicillin))\b', caseSensitive: false).hasMatch(aiText)) {
      f.add('gave medical advice');
    }
    if (ex['passed_to'] != null) {
      final who = '${ex['passed_to']}'.toLowerCase();
      if (!audit.any((a) => a.toLowerCase().contains('to $who')) && !RegExp('\\b$who\\b', caseSensitive: false).hasMatch(ai.skip(1).join(' '))) {
        f.add('was not passed to ${ex['passed_to']} (passed: ${passedTo.join(', ')}; audit: ${audit.where((a) => a.contains('passed')).join('; ')})');
      }
    }
    if (ex['not_passed'] == true && passedTo.isNotEmpty) f.add('passed the call to ${passedTo.join(', ')} for no reason');
    if (ai.isNotEmpty && ai.every((t) => t.trim().isEmpty)) f.add('the assistant said nothing');
    final repeats = <String>{};
    for (var i = 1; i < ai.length; i++) {
      // (Without the rotating "one moment" openers, which hide a repeat.)
      String core(String t) => t.replaceFirst(RegExp(r"^\s*(?:(?:Sure, let me sort that out|Okay, on it|Right, let me do that|Hmm, let me see|Let me check that for you|Okay, one sec, let me look|One moment, let me check that)\.\s*)+"), '');
      if (core(ai[i]).length > 30 && core(ai[i]) == core(ai[i - 1])) repeats.add(ai[i]);
    }
    if (repeats.isNotEmpty) f.add('repeated itself word for word: "${repeats.first}"');
    if (RegExp(r'\[(transfer|voice|connect):|CALL_TASK|<tool_call>|\{"name"\s*:|\[(add|check|find|cancel|change)_', caseSensitive: false).hasMatch(aiText)) f.add('spoke markup aloud');
    return f;
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String _brief(Map<String, dynamic> r) =>
      r.entries.where((e) => e.value != null && !{'id', 'created_at', 'via', '_via'}.contains(e.key)).map((e) => '${e.key}=${e.value}').join(', ');

  /// Which expected values the record doesn't have.
  Future<List<String>> matchRow(String app, String table, Map<String, dynamic> row, Map<String, dynamic> want, Map<String, String> numbers) async {
    final t = data(app).spec.table(table)!;
    final miss = <String>[];
    for (final e in want.entries) {
      final negate = e.key.endsWith('!');
      final key = negate ? e.key.substring(0, e.key.length - 1) : e.key;
      final f = t.fields.where((f) => f.id == key).firstOrNull;
      final got = row[key];
      var w = resolve(e.value, numbers);
      bool ok;
      String shown = '$got';
      if (f == null) {
        ok = false;
      } else if (f.type == 'phone') {
        bool same(String a, String b) => a.length >= 9 && b.length >= 9 && a.substring(a.length - 9) == b.substring(b.length - 9);
        final a = _digits('$got'), b = _digits('$w');
        // Never said their number: the number they called from is right.
        final said = (numbers['SAID'] ?? '').contains(b.length >= 9 ? b.substring(b.length - 9) : b);
        // (The simulated caller sometimes misreads its own number: what they said is what counts.)
        ok = same(a, b) || (!said && same(a, _digits(numbers['ID'] ?? ''))) || (a.length >= 9 && (numbers['SAID'] ?? '').contains(a.substring(a.length - 9)));
      } else if (f.type == 'link') {
        final nm = got is int ? (await names(app, f.link!))[got] ?? '#$got' : '$got';
        shown = nm;
        ok = nm.toLowerCase().contains('$w'.toLowerCase()) || '$w'.toLowerCase().contains(nm.toLowerCase());
      } else if (f.type == 'links') {
        final nm = await names(app, f.link!);
        final have = <String, int>{};
        for (final x in (got as List? ?? [])) {
          if (x is Map) {
            have[nm[x['id']] ?? '#${x['id']}'] = (x['qty'] as num?)?.toInt() ?? 1;
          } else {
            have[nm[x] ?? '#$x'] = 1;
          }
        }
        shown = have.entries.map((e) => '${e.value}x ${e.key}').join(', ');
        final wants = [for (final x in (w as List)) x is Map ? (name: '${x['item']}', qty: (x['qty'] as num?)?.toInt()) : (name: '$x', qty: null)];
        ok = wants.every((x) => have.entries.any((h) => h.key.toLowerCase() == x.name.toLowerCase() && (x.qty == null || h.value == x.qty))) && have.length == wants.length;
      } else if (f.type == 'number' || f.type == 'money') {
        ok = got != null && num.tryParse('$got') == num.tryParse('$w');
      } else if (f.type == 'date' && e.value is Map && (e.value as Map)['weekday'] != null) {
        // "Thursday" / "next Thursday": the coming one (today too) or the week after — both are fair.
        final now = DateTime.now();
        var d = DateTime(now.year, now.month, now.day);
        while (d.weekday != ((e.value as Map)['weekday'] as num).toInt()) {
          d = d.add(const Duration(days: 1));
        }
        d = d.add(Duration(days: ((e.value as Map)['plus'] as num?)?.toInt() ?? 0)); // a check-out: + the nights
        final ok2 = {ymd(d), ymd(d.add(const Duration(days: 7))), '$w'};
        ok = ok2.contains('$got'.trim());
        w = ok2.join(' or ');
      } else if (f.type == 'date' || f.type == 'time' || f.type == 'datetime' || f.type == 'choice' || f.type == 'email') {
        ok = '$got'.trim().toLowerCase() == '$w'.trim().toLowerCase();
      } else {
        // Names, addresses, plates: what was said is in what was saved.
        String norm(Object? x) => '$x'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        ok = got != null && (norm(got).contains(norm(w)) || (key == 'name' && norm(got).startsWith(norm(w).substring(0, norm(w).length.clamp(0, 4)))));
      }
      if (negate) ok = !ok && got != null;
      if (!ok) miss.add('$key: ${negate ? 'must not be' : 'expected'} "$w", website has "$shown"');
    }
    return miss;
  }
}


/// Which scenarios to run from the app.
enum ScenarioPick { quick, app, journeys, challenges, all }

/// Loads the scenarios shipped with the app: [quick] = one of each kind per app.
List<Map<String, dynamic>> pickScenarios(List<Map<String, dynamic>> all, ScenarioPick pick, {String? app}) {
  switch (pick) {
    case ScenarioPick.quick:
      final seen = <String>{};
      return [for (final s in all) if (seen.add('${s['app']} ${s['intent']}')) s];
    case ScenarioPick.app:
      return [for (final s in all) if (s['app'] == app) s];
    case ScenarioPick.journeys:
      return [for (final s in all) if (s['steps'] != null) s];
    case ScenarioPick.challenges:
      return [for (final s in all) if ('${s['intent']}'.startsWith('challenge_')) s];
    case ScenarioPick.all:
      // Business by business in turn, so every batch covers all of them.
      final byApp = <String, List<Map<String, dynamic>>>{};
      for (final s in all) {
        byApp.putIfAbsent('${s['app']}', () => []).add(s);
      }
      final out = <Map<String, dynamic>>[];
      for (var i = 0; out.length < all.length; i++) {
        for (final l in byApp.values) {
          if (i < l.length) out.add(l[i]);
        }
      }
      return out;
  }
}
