// ignore_for_file: avoid_print
/// Phone-call scenarios against the real app: every ready-made app is built, a simulated
/// caller (a local model playing a customer) phones the real call endpoint
/// (/v1/chat/completions, exactly as the voice engine does), and afterwards the app's own
/// website (manager API) is checked: was the table booked, the order taken with the address,
/// the right booking cancelled, nobody else's touched…
///
///   python3 test/scenarios/generate.py            # writes scenarios.json + journeys.json
///   SCEN=1 flutter test test/scenarios/runner_live_test.dart
///
/// Env: SCEN_FILE (default scenarios.json), SCEN_ONLY (comma ids or app names), SCEN_FROM/SCEN_TO (1-based range),
/// SCEN_OUT (results file, default out/results.jsonl; finished ids are skipped, so a run can resume),
/// SCEN_MODEL (the assistant's model, default qwen3:4b-instruct), SCEN_CALLER_MODEL (the caller's).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/services/agent_templates.dart';
import 'package:localailine/services/apps/app_data.dart';
import 'package:localailine/services/apps/app_server.dart';
import 'package:localailine/services/apps/app_spec.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/auth.dart';
import 'package:localailine/state/app_state.dart';

final env = Platform.environment;
final here = '${Directory.current.path}/test/scenarios';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // real network: Ollama and the app's own servers
  final support = Directory.systemTemp.createTempSync('scen_support').path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => support);

  test('scenarios', () async {
    var all = [
      for (final name in (env['SCEN_FILE'] ?? 'scenarios.json,journeys.json').split(','))
        ...(jsonDecode(File('$here/$name').readAsStringSync()) as List).cast<Map<String, dynamic>>(),
    ];
    final only = (env['SCEN_ONLY'] ?? '').split(',').where((s) => s.isNotEmpty).toSet();
    if (only.isNotEmpty) all = all.where((s) => only.contains(s['id']) || only.contains(s['app']) || only.contains(s['intent'])).toList();
    final from = int.tryParse(env['SCEN_FROM'] ?? '') ?? 1, to = int.tryParse(env['SCEN_TO'] ?? '') ?? 1 << 30;
    all = [for (final s in all) if ((s['n'] as int) >= from && (s['n'] as int) <= to) s];
    final out = File(env['SCEN_OUT'] ?? '$here/out/results.jsonl')..parent.createSync(recursive: true);
    final done = out.existsSync() ? {for (final l in out.readAsLinesSync()) if (l.trim().isNotEmpty) (jsonDecode(l) as Map)['id']} : <Object?>{};
    all = all.where((s) => !done.contains(s['id'])).toList();
    print('${all.length} scenarios to run (${done.length} already done)');
    if (all.isEmpty) return;

    final h = await Harness.boot(env['SCEN_MODEL'] ?? 'qwen3:4b-instruct');
    h.liveFile = File('${out.parent.path}/live.json');
    final before = done.length;
    final passedBefore = out.existsSync() ? out.readAsLinesSync().where((l) => l.contains('"pass":true')).length : 0;
    var pass = 0, n = 0;
    for (final s in all) {
      n++;
      h.live.clear();
      h.showLive({
        'id': s['id'], 'app': s['app'], 'intent': s['intent'], 'setup': s['setup'], 'style': s['style'], 'goal': s['goal'] ?? '',
        'done': before + n - 1, 'total': before + all.length, 'passed': passedBefore + pass, 'turns': [], 'tools': [],
      });
      final t0 = DateTime.now();
      Map<String, Object?> r;
      try {
        r = await h.run(s);
      } catch (e, st) {
        r = {'id': s['id'], 'pass': false, 'failures': ['harness error: $e'], 'stack': '$st'.split('\n').take(6).join('\n')};
      }
      r['seconds'] = DateTime.now().difference(t0).inSeconds;
      r = {'id': s['id'], 'n': s['n'], 'app': s['app'], 'intent': s['intent'], 'setup': s['setup'], 'style': s['style'], ...r};
      if (r['pass'] == true) pass++;
      out.writeAsStringSync('${jsonEncode(r)}\n', mode: FileMode.append, flush: true);
      print('[$n/${all.length}] ${s['id']} ${s['intent']} ${s['setup']}/${s['style']}: ${r['pass'] == true ? 'PASS' : 'FAIL ${r['failures']}'} (${r['seconds']}s)  — $pass/$n passed');
    }
    await h.close();
  }, timeout: const Timeout(Duration(days: 3)));
}

class Harness {
  Harness._(this.s, this.model);
  final AppState s;
  final String model;
  final appIds = <String, int>{};
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

  static Future<Harness> boot(String model) async {
    final dir = Directory.systemTemp.createTempSync('scen');
    final s = AppState(dbPath: '${dir.path}/s.db');
    await s.init();
    await s.startHost(port: 0); // not the running app's port
    final u = await s.auth.createUser(name: 'Sam Owner', username: 'owner', password: 'password-123', role: Role.owner);
    await s.completeSetup(u);
    await s.setLlmModel(model);
    await s.refreshEngine();
    if (!s.llmReady) throw StateError('The model $model is not ready in Ollama.');
    final h = Harness._(s, model);
    for (final t in appTemplates) {
      final id = await s.apps.createFromTemplate(t);
      h.appIds[t.id] = id;
      h.specs[t.id] = (await s.apps.app(id))!.spec;
      await s.apps.stop(id);
    }
    h.baseAgents = (await s.db.all('agents')).length;
    print('Booted: ${appTemplates.length} apps, host ${s.host!.port}, db ${dir.path}');
    return h;
  }

  Future<void> close() async {
    await s.apps.stopAll();
    await s.host?.stop();
  }

  // ---------------- set-up ----------------

  /// Only [app] runs (its tools are the only ones the assistant has), like switching
  /// the restaurant off and the barber on.
  Future<void> useApp(String app) async {
    if (current == app) {
      await s.apps.start(appIds[app]!, quiet: true); // un-pauses it too
      return;
    }
    for (final e in appIds.entries) {
      if (e.key != app && s.apps.runOf(e.value).name != 'stopped') await s.apps.stop(e.value);
    }
    await s.apps.start(appIds[app]!);
    current = app;
  }

  AppData data(String app) => AppData(s.db, appIds[app]!, specs[app]!);

  /// The tables customers add to (bookings, orders): emptied before each scenario.
  Future<void> clearCustomerRows(String app) async {
    final d = data(app);
    for (final t in d.spec.tables.where((t) => t.access.add && !t.single)) {
      await s.db.raw.delete('app_rows', where: 'app_id = ? AND tbl = ?', whereArgs: [appIds[app], t.id]);
    }
  }

  /// Who answers: Ava alone, a ready-made team, Ava with the owner's own instructions, or custom agents.
  Future<void> setUpAgents(Map<String, dynamic> sc) async {
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

  Future<({List<Map<String, String>> turns, List<String> passedTo, bool hungUp})> call(
      Map<String, dynamic> c, String number, String roomTag, Map<String, dynamic> sc) async {
    final room = 'pstn-in-0-_${number}_$roomTag';
    final port = s.host!.port, key = s.host!.engineKey;
    if (env['SCEN_DEBUG'] != null) print('  call $room');
    final cfg = jsonDecode(await _get('http://127.0.0.1:$port/api/voice-config?room=$room&mode=caller&token=$key')) as Map;
    final greeting = '${cfg['greeting']}';
    final turns = <Map<String, String>>[{'role': 'assistant', 'content': greeting}];
    showLive({'turns': ['AI: $greeting']});
    final passedTo = <String>[];
    var hungUp = false, ended = false, extra = 0;
    final maxTurns = (c['max_turns'] as num?)?.toInt() ?? 10;
    for (var i = 0; i < maxTurns; i++) {
      var said = await callerSays(c, turns, sc, i);
      if (said == null) break;
      ended = said.contains('[END]');
      said = said.replaceAll('[END]', '').trim();
      // Asked something but only said goodbye: a real caller would answer.
      if (said.isEmpty && extra > 0) said = 'Yes, please.';
      if (said.isEmpty) break;
      turns.add({'role': 'user', 'content': said});
      showLive({'turns': [for (final t in turns) '${t['role'] == 'user' ? 'CALLER' : 'AI'}: ${t['content']}']});
      if (env['SCEN_DEBUG'] != null) print('  CALLER: $said');
      final rq = await http.postUrl(Uri.parse('http://127.0.0.1:$port/v1/chat/completions?token=$key'));
      rq.headers.contentType = ContentType.json;
      rq.write(jsonEncode({'model': 'caller:en:$room', 'stream': true, 'messages': turns}));
      final body = await utf8.decodeStream(await rq.close());
      var text = body
          .split('\n')
          .where((l) => l.startsWith('data: {'))
          .map((l) => '${(jsonDecode(l.substring(6)) as Map)['choices'][0]['delta']['content'] ?? ''}')
          .join();
      for (final m in RegExp(r'\[voice:([^\]]*)\]|\[connect:(\d+)\]').allMatches(text)) {
        passedTo.add(m.group(1) ?? 'person#${m.group(2)}');
      }
      // The voice engine hangs up only on a goodbye (see _FAREWELL in localline_voice.py).
      if (text.contains('[hangup]') && _farewell.hasMatch(text)) hungUp = true;
      text = text.replaceAll(RegExp(r'\s*\[(voice|connect):[^\]]*\]\s*'), ' ').replaceAll('[hangup]', '').trim();
      turns.add({'role': 'assistant', 'content': text});
      showLive({'turns': [for (final t in turns) '${t['role'] == 'user' ? 'CALLER' : 'AI'}: ${t['content']}']});
      if (env['SCEN_DEBUG'] != null) print('  AI: $text');
      if (hungUp || passedTo.any((p) => p.startsWith('person#'))) break;
      // The caller said goodbye, but the assistant just asked something: they'd answer it.
      if (ended && !(text.trim().endsWith('?') && extra++ < 2)) break;
    }
    // The voice engine reports the end of the call (no transcript: no summary needed here).
    final end = await http.postUrl(Uri.parse('http://127.0.0.1:$port/api/call-ended?token=$key'));
    end.headers.contentType = ContentType.json;
    end.write(jsonEncode({'room': room, 'transcript': [], 'answered': true, 'number': number}));
    await (await end.close()).drain<void>();
    return (turns: turns, passedTo: passedTo, hungUp: hungUp);
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
        'If asked to confirm details that are right, say yes. If the assistant suggests or reads back a day, time, number of people, item or detail that is NOT in your facts, '
        'say no and give the right one from your facts — never accept a wrong suggestion. '
        'If asked something not in your facts (e.g. allergies, special requests, email) say no / not needed. '
        'When your goal is done (they clearly confirmed it) or clearly cannot be done, say a short goodbye and end with [END]. '
        'If the assistant keeps repeating itself or does not help after several tries, say goodbye and [END]. Output only what you say.';
    final convo = [
      {'role': 'system', 'content': system},
      // Roles flipped: the model plays the caller.
      for (final t in turns) {'role': t['role'] == 'user' ? 'assistant' : 'user', 'content': t['content']},
      if (turns.last['role'] == 'user') {'role': 'user', 'content': '(continue)'},
    ];
    if (i == 0 && caller['name'] != null) {
      convo.add({'role': 'user', 'content': '(You are ${caller['name']}. Say your opening line now.)'});
    }
    final rq = await http.postUrl(Uri.parse('http://127.0.0.1:11434/api/chat'));
    rq.headers.contentType = ContentType.json;
    rq.write(jsonEncode({
      'model': env['SCEN_CALLER_MODEL'] ?? 'qwen3:4b-instruct',
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

  Future<Map<String, Object?>> run(Map<String, dynamic> sc) async {
    final app = sc['app'] as String;
    await useApp(app);
    await clearCustomerRows(app);
    await setUpAgents(sc);
    final n = sc['n'] as int;
    // Each caller in the scenario has their own number (A = the main caller).
    final numbers = {for (final (i, k) in ['A', 'B', 'C', 'D'].indexed) k: '+4477009${(n * 4 + i).toString().padLeft(5, '0')}'};
    numbers['CALLER'] = numbers['A']!;
    final failures = <String>[];
    final calls = <Map<String, Object?>>[];

    // Records already in the app (someone's booking, a full evening…).
    final seeded = <int>[];
    final seedTable = <int, String>{};
    for (final sd in (sc['seed'] as List? ?? []).cast<Map>()) {
      final v = {for (final e in (sd['values'] as Map).entries) '${e.key}': resolve(e.value, numbers)};
      final id = await data(app).add('${sd['table']}', v, manager: true, via: 'seed');
      seedTable[seeded.length] = '${sd['table']}';
      seeded.add(id);
    }

    final steps = (sc['steps'] as List?)?.cast<Map<String, dynamic>>() ??
        [
          {'do': 'call', 'goal': sc['goal'], 'facts': sc['facts'], 'wrong': sc['wrong'], 'style_text': sc['style_text'], 'caller': sc['caller'], 'expect': sc['expect']},
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
      if (what == 'stop_app') {
        await s.apps.stop(appIds['${st['app']}']!);
        current = null;
        continue;
      }
      if (what == 'pause_app') {
        await s.apps.pause(appIds['${st['app']}']!);
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
      final tables = {if (ex['table'] != null) '${ex['table']}', ...seedTable.values};
      for (final t in tables) {
        before[t] = {for (final r in await siteRows(curApp, t)) r['id'] as int};
      }
      final auditFrom = DateTime.now().millisecondsSinceEpoch;
      final used = <String>[];
      AppServer.onToolCall = (app, tool, args, result, error) {
        used.add('$tool(${jsonEncode(args)}) → ${error ? 'ERROR ' : ''}${result.split('\n').first}');
        showLive({'tools': used});
      };
      final t0 = DateTime.now();
      showLive({'goal': st['goal'] ?? '', 'call': steps.take(si + 1).where((x) => (x['do'] ?? 'call') == 'call').length, 'calls': steps.where((x) => (x['do'] ?? 'call') == 'call').length, 'turns': [], 'tools': used});
      final r = await call({...st, 'style_text': st['style_text'] ?? sc['style_text']}, numbers[who]!, '${sc['id']}-$si', {...sc, 'app': curApp});
      final audit = [for (final a in await s.db.raw.query('audit', where: 'at >= ?', whereArgs: [auditFrom])) '${a['what']}'];
      final saidDigits = _digits(r.turns.where((t) => t['role'] == 'user').map((t) => t['content']).join(' '));
      final f = await check(curApp, ex, r.turns, before, seeded, seedTable, {...numbers, 'SAID': saidDigits, 'ID': numbers[who]!}, r.passedTo, audit);
      failures.addAll(f.map((x) => steps.length > 1 ? 'call ${si + 1}: $x' : x));
      calls.add({
        'from': who,
        'seconds': DateTime.now().difference(t0).inSeconds,
        'turns': [for (final t in r.turns) '${t['role'] == 'user' ? 'CALLER' : 'AI'}: ${t['content']}'],
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

  static final _claimed = RegExp(r"\b(you're all set|you are all set|is (now )?(booked|confirmed|reserved|placed)|(have|'ve) (booked|reserved|placed)|booking is confirmed|order is (placed|confirmed|in)|confirmed for)\b", caseSensitive: false);

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
    for (final want in (ex['reply_mentions'] as List? ?? [])) {
      if (!RegExp('$want', caseSensitive: false).hasMatch(aiText.replaceAll('£', ''))) f.add('the assistant never said /$want/');
    }
    for (final no in (ex['not_mention'] as List? ?? [])) {
      if (aiText.toLowerCase().contains('$no'.toLowerCase())) f.add('privacy: the assistant mentioned "$no"');
    }
    if (ex['no_false_confirm'] == true || (ex['new'] == 1 && active.isEmpty)) {
      final claimed = ai.where((t) => _claimed.hasMatch(t) && !RegExp(r"\b(not|isn't|wasn't|couldn't|can't|unable|sorry)\b", caseSensitive: false).hasMatch(t)).toList();
      if (active.isEmpty && claimed.isNotEmpty) f.add('FALSE CONFIRMATION: said "${claimed.first}" but nothing was saved');
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
      if (ai[i].length > 30 && ai[i] == ai[i - 1]) repeats.add(ai[i]);
    }
    if (repeats.isNotEmpty) f.add('repeated itself word for word: "${repeats.first}"');
    if (RegExp(r'\[(transfer|voice|connect):|CALL_TASK|<tool_call>|\{"name"\s*:', caseSensitive: false).hasMatch(aiText)) f.add('spoke markup aloud');
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
