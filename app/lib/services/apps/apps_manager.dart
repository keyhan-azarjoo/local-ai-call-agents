import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/db.dart';
import '../mcp/mcp_manager.dart';
import 'app_builder.dart';
import 'app_data.dart';
import 'app_server.dart';
import 'app_spec.dart';
import 'app_styles.dart';
import 'app_templates.dart';

enum AppRun { stopped, running, paused }

/// A user-built app as stored in the `apps` table.
class BuiltApp {
  BuiltApp(this.row);
  final Map<String, Object?> row;
  int get id => row['id'] as int;
  String get name => row['name'] as String;
  String get request => row['request'] as String;
  int get port => row['port'] as int;
  String get pin => row['pin'] as String;
  AppSpec get spec => AppSpec.fromJson((jsonDecode(row['spec'] as String) as Map).cast<String, dynamic>());
  AppRun get savedRun => AppRun.values.firstWhere((r) => r.name == row['status'], orElse: () => AppRun.stopped);
}

enum BuildState { waiting, working, done, simple, skipped, failed }

class BuildStep {
  BuildStep(this.title, this.run);
  final String title;
  final Future<String?> Function() run;
  BuildState state = BuildState.waiting;
  String? note;
}

/// One "create an app" conversation, kept while you move around the app.
class BuildJob {
  String stage = 'describe'; // describe → questions → plan → build → done
  String request = '';
  final pictures = <(String, PictureNotes?)>[]; // base64, what the AI saw
  List<String> questions = [];
  final answers = <String, String>{};
  Features features = const Features();
  bool exampleData = true;
  AppSpec? plan;
  final steps = <BuildStep>[];
  int? appId;
  String? busy; // what the AI is doing now
  String? error;
  bool cancelled = false;
  Future<void> Function()? save;

  /// The website's look (see [siteStyles]); null = suggested from the request.
  String? style;

  /// The business's own name, used for the app and its texts.
  String businessName = '';

  List<PictureNotes> get notes => [for (final p in pictures) ?p.$2];
}

/// Runs the apps built in LocalAILine and builds new ones with the AI.
class AppsManager extends ChangeNotifier {
  AppsManager(this.db, this.mcp, {required this.ask, required this.visionModel, required this.log, this.forgetServer});
  final Db db;
  final McpManager mcp;
  final AskModel ask;
  final Future<String?> Function() visionModel;
  final Future<void> Function(String) log;

  /// Removes what Ava saved from a tool server (its searchable copy of the data).
  final Future<void> Function(String serverName)? forgetServer;
  final _servers = <int, AppServer>{};

  /// What the AI is changing in an app right now (app id → message).
  final editing = <int, String>{};
  BuildJob? job;

  AppBuilder get builder => AppBuilder(ask);

  Future<List<BuiltApp>> apps() async => (await db.all('apps', orderBy: 'id DESC')).map(BuiltApp.new).toList();

  Future<BuiltApp?> app(int id) async {
    final r = await db.all('apps', where: 'id = ?', args: [id]);
    return r.isEmpty ? null : BuiltApp(r.first);
  }

  AppRun runOf(int id) {
    final s = _servers[id];
    return s == null || !s.running ? AppRun.stopped : (s.paused ? AppRun.paused : AppRun.running);
  }

  /// Apps that were running when LocalAILine closed start again.
  Future<void> restore() async {
    for (final a in await apps()) {
      if (a.savedRun == AppRun.stopped) continue;
      try {
        await start(a.id, quiet: true);
        if (a.savedRun == AppRun.paused) await pause(a.id);
      } catch (_) {}
    }
  }

  Future<int> _freePort() async {
    final used = {for (final a in await apps()) a.port};
    for (var p = 8790; p < 8990; p++) {
      if (used.contains(p)) continue;
      try {
        final s = await ServerSocket.bind(InternetAddress.anyIPv4, p);
        await s.close();
        return p;
      } catch (_) {}
    }
    throw BuildError('No free port for the app.');
  }

  /// Pictures uploaded to an app.
  String filesDir(int id) => '${File(db.path).parent.path}/apps/$id/files';

  Future<void> _status(int id, AppRun r) async {
    await db.update('apps', id, {'status': r.name});
    notifyListeners();
  }

  Future<void> start(int id, {bool quiet = false}) async {
    final a = await app(id);
    if (a == null) return;
    var srv = _servers[id];
    if (srv == null || !srv.running) {
      srv = AppServer(data: AppData(db, id, a.spec), pin: a.pin, toolKey: await toolKey(id), filesDir: filesDir(id), onSpecChanged: (spec) => saveSpec(id, spec, fromSite: true),
          readPicture: (table, b64) => rowsFromPicture(id, table, b64));
      try {
        await srv.start(a.port);
      } on SocketException {
        // The port was taken by something else meanwhile: move to a free one.
        final port = await _freePort();
        await db.update('apps', id, {'port': port});
        await srv.start(port);
      }
      _servers[id] = srv;
      await _keyAva(id);
    }
    srv.paused = false;
    await _status(id, AppRun.running);
    await _setAvaEnabled(id, true);
    if (!quiet) await log('Started app ${a.name}');
  }

  /// Website shows "paused"; Ava's tools say so too. Stays reachable to resume at once.
  Future<void> pause(int id) async {
    final srv = _servers[id];
    if (srv == null) return;
    srv.paused = true;
    await _status(id, AppRun.paused);
    await log('Paused app ${(await app(id))?.name}');
  }

  Future<void> stop(int id) async {
    await _servers.remove(id)?.stop();
    await _setAvaEnabled(id, false);
    await _status(id, AppRun.stopped);
    await log('Stopped app ${(await app(id))?.name}');
  }

  /// Deletes an app completely: stops it, and removes its data, pictures,
  /// Ava's tools for it and anything Ava saved from it.
  Future<void> delete(int id) async {
    final name = (await app(id))?.name;
    if (job?.appId == id) job = null;
    await _servers.remove(id)?.stop();
    for (final r in await _avaRows(id)) {
      await mcp.disconnect(r.id);
      await db.delete('mcp_servers', r.id);
      await forgetServer?.call(r.name);
    }
    await db.raw.delete('app_rows', where: 'app_id = ?', whereArgs: [id]);
    await db.delete('apps', id);
    final files = Directory(filesDir(id)).parent;
    if (files.existsSync()) files.deleteSync(recursive: true);
    await log('Deleted app $name');
    notifyListeners();
  }

  Future<void> stopAll() async {
    for (final s in _servers.values) {
      await s.stop();
    }
    _servers.clear();
  }

  /// Saves a changed app and uses it at once (website, data rules, Ava's tools).
  Future<void> saveSpec(int id, AppSpec spec, {bool fromSite = false}) async {
    await db.update('apps', id, {'spec': jsonEncode(spec.toJson()), 'name': spec.name, 'updated_at': DateTime.now().millisecondsSinceEpoch});
    _servers[id]?.data.spec = spec;
    if (fromSite) await log('Changed the website of ${spec.name}');
    for (final r in await _avaRows(id)) {
      await db.update('mcp_servers', r.id, {'name': r.secret['role'] == 'manager' ? '${spec.name} (manager)' : spec.name});
      if (runOf(id) != AppRun.stopped) await mcp.connect(r.id);
    }
    notifyListeners();
  }

  Future<String> newPin(int id) async {
    final pin = _pin();
    await db.update('apps', id, {'pin': pin});
    _servers[id]?.pin = pin;
    for (final r in await _avaRows(id)) {
      if (r.secret['role'] == 'manager') await db.update('mcp_servers', r.id, {'secret': jsonEncode({...r.secret, 'value': pin})});
    }
    await _keyAva(id);
    notifyListeners();
    return pin;
  }

  /// The app's tool key: only this computer's assistant has it (see [AppServer.toolKey]).
  Future<String> toolKey(int id) async {
    final k = await db.setting('app.$id.toolkey');
    if (k != null && k.length >= 32) return k;
    final key = base64Url.encode(List<int>.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
    await db.setSetting('app.$id.toolkey', key);
    return key;
  }

  /// Ava's two connections to the app carry the tool key (and the manager's the PIN too).
  Future<void> _keyAva(int id) async {
    final key = await toolKey(id);
    final a = await app(id);
    for (final r in await _avaRows(id)) {
      final headers = {'X-Tool-Key': key, if (r.secret['role'] == 'manager') 'X-Key': a?.pin ?? ''};
      if ('${r.secret['headers']}' == '$headers' && r.authMode.name == 'token') continue;
      await db.update('mcp_servers', r.id, {'auth_mode': 'token', 'secret': jsonEncode({...r.secret, 'headers': headers})});
      if (runOf(id) != AppRun.stopped) await mcp.connect(r.id);
    }
  }

  static String _pin() => List.generate(6, (_) => Random.secure().nextInt(10)).join();

  // ---------------- Ava (MCP) ----------------

  Future<List<McpServer>> _avaRows(int id) async => [for (final s in await mcp.servers()) if (s.secret['app'] == id) s];

  Future<bool> avaConnected(int id) async => (await _avaRows(id)).isNotEmpty;

  /// The app's two tool servers for Ava: customers' and the manager's.
  Future<List<McpServer>> avaServers(int id) => _avaRows(id);

  /// Lets Ava use the app in chats and on calls: customers' actions for everyone
  /// (callers can order or book without you approving), the manager's only for you.
  Future<void> connectAva(int id) async {
    final a = await app(id);
    if (a == null || (await _avaRows(id)).isNotEmpty) return;
    final base = 'http://127.0.0.1:${a.port}';
    for (final (role, url, scope, auth, secret) in [
      ('customers', '$base/mcp', 'all', 'token', <String, Object?>{'app': id, 'role': 'customers', 'headers': {'X-Tool-Key': await toolKey(id)}}),
      ('manager', '$base/mcp/manager', 'me', 'token', <String, Object?>{'app': id, 'role': 'manager', 'header': 'X-Key', 'value': a.pin, 'headers': {'X-Tool-Key': await toolKey(id), 'X-Key': a.pin}}),
    ]) {
      final rid = await db.insert('mcp_servers', {
        'name': role == 'manager' ? '${a.name} (manager)' : a.name,
        'kind': 'http',
        'target': url,
        'scope': scope,
        'auth_mode': auth,
        'secret': jsonEncode(secret),
        'enabled': runOf(id) == AppRun.stopped ? 0 : 1,
      });
      if (runOf(id) != AppRun.stopped) await mcp.connect(rid);
    }
    await log('Connected app ${a.name} to Ava');
    notifyListeners();
  }

  Future<void> disconnectAva(int id) async {
    for (final r in await _avaRows(id)) {
      await mcp.disconnect(r.id);
      await db.delete('mcp_servers', r.id);
    }
    await log('Disconnected app ${(await app(id))?.name} from Ava');
    notifyListeners();
  }

  Future<void> _setAvaEnabled(int id, bool on) async {
    for (final r in await _avaRows(id)) {
      await db.update('mcp_servers', r.id, {'enabled': on ? 1 : 0});
      if (on) {
        await mcp.connect(r.id);
      } else {
        await mcp.disconnect(r.id);
      }
    }
  }

  // ---------------- ready-made apps ----------------

  /// Makes an app from a template, with its example data, and starts it.
  /// [name], [phone] and [address] replace the template's made-up ones.
  /// Brings an app made from an older version of [t] up to date: tables get the template's new
  /// fields (e.g. collection or delivery on orders) and its rules; extra fields and all data stay.
  Future<bool> upgradeFromTemplate(int id, AppTemplate t) async {
    final a = await app(id);
    if (a == null) return false;
    final raw = a.spec.toJson();
    final tables = [for (final x in (raw['tables'] as List)) (x as Map).cast<String, dynamic>()];
    var changed = false;
    for (final tt in (t.spec['tables'] as List).cast<Map>()) {
      final mine = tables.where((x) => x['id'] == tt['id']).firstOrNull;
      if (mine == null) continue;
      final theirs = [for (final f in (tt['fields'] as List)) (f as Map).cast<String, dynamic>()];
      final kept = [for (final f in (mine['fields'] as List).cast<Map>()) if (!theirs.any((x) => x['id'] == f['id'])) f];
      final next = [...theirs, ...kept];
      if (jsonEncode(next) != jsonEncode(mine['fields'])) {
        // Keep the app's own labels (it may be in another language or reworded).
        for (final f in next) {
          final old = (mine['fields'] as List).cast<Map>().where((x) => x['id'] == f['id']).firstOrNull;
          if (old?['label'] != null) f['label'] = old!['label'];
        }
        mine['fields'] = next;
        changed = true;
      }
    }
    if (!changed) return false;
    await saveSpec(id, AppSpec.fromJson({...raw, 'tables': tables}));
    await log('Updated ${a.name} to the latest ${t.name} template (data kept)');
    return true;
  }

  Future<int> createFromTemplate(AppTemplate t, {bool ava = true, String name = '', String phone = '', String address = ''}) async {
    final pics = <String, String?>{};
    final dir = Directory('${File(db.path).parent.path}/apps/_new_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    // Sample photos, saved into the app (skipped without internet: tidy placeholders instead).
    Future<Object?> photo(Object? v, {bool big = false}) async {
      if (v is! String || !v.startsWith('unsplash:')) return v;
      if (pics.containsKey(v)) return pics[v];
      try {
        final r = await http
            .get(Uri.parse('https://images.unsplash.com/photo-${v.substring(9)}?w=${big ? 2000 : 900}&q=78&fm=jpg&fit=crop'))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200 || r.bodyBytes.length < 2000) return pics[v] = null;
        final name = '${v.substring(9).replaceAll(RegExp(r'[^a-z0-9]'), '')}${big ? 'h' : ''}.jpg';
        await File('${dir.path}/$name').writeAsBytes(r.bodyBytes);
        return pics[v] = '/files/$name';
      } catch (_) {
        return pics[v] = null;
      }
    }

    final site = Map<String, Object?>.of((t.spec['site'] as Map?)?.cast<String, Object?>() ?? {});
    site['hero'] = await photo(site['hero'], big: true);
    final rows = <String, List<Map<String, Object?>>>{};
    await Future.wait([
      for (final e in t.rows.entries)
        () async {
          rows[e.key] = [
            for (final r in e.value) {for (final f in r.entries) f.key: await photo(f.value)},
          ];
        }(),
    ]);
    if (phone.trim().isNotEmpty) site['phone'] = phone.trim();
    if (address.trim().isNotEmpty) site['address'] = address.trim();
    var raw = <String, dynamic>{...t.spec, 'site': site, 'features': {'website': true, 'ava': ava}};
    // Their own name everywhere the sample name was (title, texts, footer).
    final sample = t.spec['name'] as String;
    if (name.trim().isNotEmpty && name.trim() != sample) {
      raw = jsonDecode(jsonEncode(raw).replaceAll(sample, name.trim().replaceAll('"', "'"))) as Map<String, dynamic>;
    }
    final spec = AppSpec.fromJson(raw);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('apps', {
      'name': spec.name,
      'request': t.blurb,
      'spec': jsonEncode(spec.toJson()),
      'port': await _freePort(),
      'pin': _pin(),
      'status': 'stopped',
      'created_at': now,
      'updated_at': now,
    });
    final files = Directory(filesDir(id));
    files.parent.createSync(recursive: true);
    if (files.existsSync()) files.deleteSync(recursive: true);
    dir.renameSync(files.path);
    final data = AppData(db, id, spec);
    // In template order: tables others link to come first.
    for (final key in t.rows.keys) {
      for (final r in rows[key]!) {
        try {
          await data.add(key, {for (final f in r.entries) if (f.value != null) f.key: f.value}, manager: true);
        } on AppDataError catch (_) {}
      }
    }
    await log('Created app ${spec.name} from the ${t.name} template');
    await start(id);
    if (ava) await connectAva(id);
    return id;
  }

  // ---------------- building ----------------

  BuildJob newJob() {
    job = BuildJob();
    notifyListeners();
    return job!;
  }

  void cancelJob() {
    job?.cancelled = true;
    job = null;
    notifyListeners();
  }

  /// Runs [work] with a "busy" message, catching what goes wrong.
  Future<bool> _busy(BuildJob j, String what, Future<void> Function() work) async {
    j
      ..busy = what
      ..error = null;
    notifyListeners();
    try {
      await work();
      return true;
    } catch (e) {
      j.error = '$e';
      return false;
    } finally {
      j.busy = null;
      notifyListeners();
    }
  }

  void removePicture(BuildJob j, int i) {
    j.pictures.removeAt(i);
    notifyListeners();
  }

  /// Reads a picture with a model that can see. Returns an error message, or null.
  Future<String?> addPicture(BuildJob j, String base64) async {
    final model = await visionModel();
    if (model == null) return 'novision';
    j.pictures.add((base64, null));
    final i = j.pictures.length - 1;
    await _busy(j, 'Looking at your picture…', () async {
      final notes = await builder.readPicture(base64, model: model);
      if (i < j.pictures.length) j.pictures[i] = (base64, notes);
    });
    return j.error;
  }

  Future<void> askQuestions(BuildJob j) async {
    if (await _busy(j, 'Reading what you want…', () async => j.questions = await builder.questions(j.businessName.isEmpty ? j.request : '${j.request}\n(The business is called ${j.businessName}.)', j.notes))) {
      j.stage = 'questions'; // also where the options are, even with no questions
      notifyListeners();
    }
  }

  Future<void> makePlan(BuildJob j) async {
    if (await _busy(j, 'Making a plan…', () async => j.plan = await builder.plan(j.request, j.answers, j.features, j.notes, style: j.style ?? suggestStyle(j.request), name: j.businessName))) {
      j.stage = 'plan';
      notifyListeners();
    }
  }

  Future<void> changePlan(BuildJob j, String change) async {
    await _busy(j, 'Changing the plan…', () async => j.plan = await builder.changePlan(j.plan!, change));
  }

  void editPlan(BuildJob j, AppSpec plan) {
    j.plan = plan.repaired();
    notifyListeners();
  }

  /// Builds the approved plan one small step at a time, then starts the app.
  Future<void> build(BuildJob j) async {
    var spec = j.plan!;
    final now = DateTime.now().millisecondsSinceEpoch;
    j.appId ??= await db.insert('apps', {
      'name': spec.name,
      'request': j.request,
      'spec': jsonEncode(spec.toJson()),
      'port': await _freePort(),
      'pin': _pin(),
      'status': 'stopped',
      'created_at': now,
      'updated_at': now,
    });
    final id = j.appId!;
    Future<void> save() => db.update('apps', id, {'spec': jsonEncode(spec.toJson()), 'name': spec.name, 'updated_at': DateTime.now().millisecondsSinceEpoch});

    j.steps.clear();
    for (final t in spec.tables) {
      j.steps.add(BuildStep('Design “${t.title}”', () async {
        try {
          final fields = await builder.tableFields(spec, t.id, j.notes);
          spec = spec.copyWith(tables: [for (final x in spec.tables) x.id == t.id ? x.copyWith(fields: fields) : x]);
          return '${fields.length} fields: ${fields.map((f) => f.label).join(', ')}';
        } on BuildError {
          final simple = [FieldSpec(id: 'name', label: 'Name', type: 'text', required: true), FieldSpec(id: 'details', label: 'Details', type: 'longtext')];
          spec = spec.copyWith(tables: [for (final x in spec.tables) x.id == t.id ? x.copyWith(fields: simple) : x]);
          throw const _Simple('The AI struggled here, so it got a simple version (name and details). Change it later with “Change”.');
        }
      }));
    }
    j.steps.add(BuildStep('Check the tables fit together', () async {
      final before = spec.tables.map((t) => t.toJson()).toString();
      spec = spec.repaired();
      return before == spec.tables.map((t) => t.toJson()).toString() ? 'All good.' : 'Fixed a few links between tables.';
    }));
    for (final p in spec.pages) {
      j.steps.add(BuildStep('Design page “${p.title}”', () async {
        try {
          final blocks = await builder.pageBlocks(spec, p.id);
          spec = spec.copyWith(pages: [for (final x in spec.pages) x.id == p.id ? x.copyWith(blocks: blocks) : x]);
          return '${blocks.length} parts: ${blocks.map((b) => b.describe(spec)).join(', ')}';
        } on BuildError {
          spec = spec.copyWith(pages: [for (final x in spec.pages) x.id == p.id ? x.copyWith(blocks: _simpleBlocks(spec, x)) : x]);
          throw const _Simple('The AI struggled here, so the page got a simple layout.');
        }
      }));
    }
    if (j.exampleData) {
      // Tables others link to first, so links can use their names.
      final order = [...spec.tables]..sort((a, b) => a.fields.where((f) => f.link != null).length.compareTo(b.fields.where((f) => f.link != null).length));
      for (final t in order.where((t) => !(t.access.add && !t.access.see))) {
        j.steps.add(BuildStep('Add example ${t.title.toLowerCase()}', () async {
          final data = AppData(db, id, spec);
          if (await data.count(t.id) > 0) return 'Already has data.';
          final names = <String, List<String>>{};
          for (final f in spec.table(t.id)!.fields.where((f) => f.link != null)) {
            final target = spec.table(f.link!)!;
            names[f.link!] = [for (final r in await data.list(target.id, manager: true)) '${r[target.labelField]}'];
          }
          List<Map<String, dynamic>> rows;
          try {
            rows = await builder.exampleRows(spec, t.id, j.notes, names);
          } on BuildError {
            throw const _Skip('Skipped: add your own in the manager page.');
          }
          var ok = 0;
          final links = {for (final f in spec.table(t.id)!.fields) if (f.link != null) f.id};
          for (final r in rows) {
            try {
              await data.add(t.id, r, manager: true);
              ok++;
            } on AppDataError catch (_) {
              // Usually a link to something that doesn't exist: keep the record without links.
              try {
                await data.add(t.id, Map.of(r)..removeWhere((k, _) => links.contains(slug(k))), manager: true);
                ok++;
              } on AppDataError catch (_) {}
            }
          }
          if (ok == 0) throw const _Skip('Skipped: add your own in the manager page.');
          return 'Added $ok.';
        }));
      }
    }
    j.steps.add(BuildStep('Start the app', () async {
      await save();
      await start(id);
      return 'Running on port ${(await app(id))!.port}.';
    }));
    if (spec.features.ava) {
      j.steps.add(BuildStep('Connect it to Ava (chat and phone calls)', () async {
        await connectAva(id);
        return 'Ava can now use it.';
      }));
    }
    j
      ..stage = 'build'
      ..save = save;
    notifyListeners();
    await _runSteps(j);
  }

  Future<void> retryFrom(BuildJob j) async {
    for (final s in j.steps.where((s) => s.state == BuildState.failed)) {
      s.state = BuildState.waiting;
    }
    await _runSteps(j);
  }

  Future<void> _runSteps(BuildJob j) async {
    for (final s in j.steps) {
      if (j.cancelled) return;
      if (s.state != BuildState.waiting) continue;
      s.state = BuildState.working;
      notifyListeners();
      try {
        s.note = await s.run();
        s.state = BuildState.done;
      } on _Simple catch (e) {
        s.note = e.message;
        s.state = BuildState.simple;
      } on _Skip catch (e) {
        s.note = e.message;
        s.state = BuildState.skipped;
      } catch (e) {
        s.note = '$e';
        s.state = BuildState.failed;
        notifyListeners();
        return;
      }
      await j.save!();
      notifyListeners();
    }
    j.stage = 'done';
    await log('Built app ${(await app(j.appId!))?.name}');
    notifyListeners();
  }

  List<Block> _simpleBlocks(AppSpec spec, PageSpec p) => [
        Block({'type': 'text', 'text': '# ${p.title}\n${p.purpose}'}),
        for (final t in spec.tables.where((t) => t.access.see).take(2)) Block({'type': t.single ? 'info' : 'list', 'table': t.id, 'search': true}),
        for (final t in spec.tables.where((t) => t.access.add && !t.single).take(1)) Block({'type': 'form', 'table': t.id, 'title': t.title}),
      ];

  // ---------------- changing a built app ----------------

  /// Runs an AI change on an app, showing [what] while it works. Returns an error or null.
  Future<String?> change(int id, String what, Future<AppSpec> Function(AppSpec spec) work) async {
    final a = await app(id);
    if (a == null) return 'The app is gone.';
    editing[id] = what;
    notifyListeners();
    try {
      final next = await work(a.spec);
      await saveSpec(id, next);
      await log('Changed app ${a.name}: $what');
      return null;
    } catch (e) {
      return '$e';
    } finally {
      editing.remove(id);
      notifyListeners();
    }
  }

  Future<String?> changeTable(int id, String tableId, String request) => change(id, 'Changing ${titleOf(tableId).toLowerCase()}…', (spec) async {
        final fields = await builder.changeTable(spec, tableId, request);
        return spec.copyWith(tables: [for (final t in spec.tables) t.id == tableId ? t.copyWith(fields: fields) : t]).repaired();
      });

  Future<String?> changePage(int id, String pageId, String request) => change(id, 'Changing the page…', (spec) async {
        final blocks = await builder.changePage(spec, pageId, request);
        return spec.copyWith(pages: [for (final p in spec.pages) p.id == pageId ? p.copyWith(blocks: blocks) : p]);
      });

  Future<String?> addPart(int id, String request) => change(id, 'Adding “$request”…', (spec) => builder.addPart(spec, request));

  Future<String?> changeLook(int id, String request, {String? pictureBase64}) => change(id, 'Changing the look…', (spec) async {
        var req = request;
        if (pictureBase64 != null) {
          final model = await visionModel();
          if (model == null) throw BuildError('No AI that can see pictures is downloaded.');
          final n = await builder.readPicture(pictureBase64, model: model);
          req = '${request.isEmpty ? 'Look like the picture' : request}. The picture: ${n.summary}';
        }
        return builder.changeLook(spec, req);
      });

  /// One sentence about any part of the app ("make it darker", "add a gallery",
  /// "add photos to the menu"): the AI picks the part, then changes only that part.
  Future<String?> changeAnything(int id, String request) => change(id, 'Working on “$request”…', (spec) async {
        final r = await builder.route(spec, request);
        return switch (r.kind) {
          'look' => builder.changeLook(spec, request),
          'site' => builder.changeSite(spec, request),
          'table' => () async {
              final fields = await builder.changeTable(spec, r.target!, request);
              return spec.copyWith(tables: [for (final t in spec.tables) t.id == r.target ? t.copyWith(fields: fields) : t]).repaired();
            }(),
          'page' => () async {
              final blocks = await builder.changePage(spec, r.target!, request);
              return spec.copyWith(pages: [for (final p in spec.pages) p.id == r.target ? p.copyWith(blocks: blocks) : p]);
            }(),
          _ => builder.addPart(spec, request),
        };
      });

  /// Records read from a photo of a menu, price list… (not saved yet).
  /// Throws [NoVision] when no downloaded AI can see pictures.
  Future<List<Map<String, dynamic>>> rowsFromPicture(int id, String table, String base64) async {
    final model = await visionModel();
    if (model == null) throw NoVision();
    final a = (await app(id))!;
    editing[id] = 'Reading your picture…';
    notifyListeners();
    try {
      return await builder.rowsFromPicture(a.spec, table, base64, model: model);
    } finally {
      editing.remove(id);
      notifyListeners();
    }
  }

  /// Saves the records the user kept. Returns how many were added.
  Future<int> addRows(int id, String table, List<Map<String, dynamic>> rows) async {
    final a = (await app(id))!;
    final data = AppData(db, id, a.spec);
    var n = 0;
    for (final r in rows) {
      try {
        await data.add(table, r, manager: true);
        n++;
      } on AppDataError catch (_) {}
    }
    await log('Added $n ${a.spec.table(table)?.title.toLowerCase()} to ${a.name} from a photo');
    notifyListeners();
    return n;
  }

  /// A new style picked by hand (no AI needed).
  Future<void> setStyle(int id, String style, {String? accent}) async {
    final s = (await app(id))!.spec;
    await saveSpec(id, s.copyWith(site: {...s.site, 'style': style}, theme: accent ?? ''));
  }

  Future<void> removePart(int id, {String? table, String? page}) async {
    final a = await app(id);
    if (a == null) return;
    final s = a.spec;
    await saveSpec(
        id,
        s.copyWith(tables: [for (final t in s.tables) if (t.id != table) t], pages: [for (final p in s.pages) if (p.id != page) p]).repaired());
    if (table != null) await db.raw.delete('app_rows', where: 'app_id = ? AND tbl = ?', whereArgs: [id, table]);
  }

  /// Who can do what with a table, set by hand.
  Future<void> setAccess(int id, String table, Access access) async {
    final s = (await app(id))!.spec;
    await saveSpec(id, s.copyWith(tables: [for (final t in s.tables) t.id == table ? t.copyWith(access: access) : t]).repaired());
  }
}

class NoVision implements Exception {
  @override
  String toString() => 'None of your downloaded AI models can read pictures. In LocalAILine, add a picture once to download one (Gemma 3).';
}

class _Simple implements Exception {
  const _Simple(this.message);
  final String message;
}

class _Skip implements Exception {
  const _Skip(this.message);
  final String message;
}
