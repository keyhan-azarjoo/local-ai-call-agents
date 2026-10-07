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
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/auth.dart';
import 'package:localailine/state/app_state.dart';
import 'package:localailine/state/scenario_runner.dart';

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
      for (final name in (env['SCEN_FILE'] ?? 'scenarios.json,journeys.json,challenges.json').split(','))
        ...(jsonDecode(File('${Directory.current.path}/assets/scenarios/$name').readAsStringSync()) as List).cast<Map<String, dynamic>>(),
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

    final h = await boot(env['SCEN_MODEL'] ?? 'qwen3:4b-instruct');
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

/// A fresh, private copy of the app (its own database and port) with every ready-made app.
Future<ScenarioRunner> boot(String model) async {
  final dir = Directory.systemTemp.createTempSync('scen');
  final s = AppState(dbPath: '${dir.path}/s.db');
  await s.init();
  await s.startHost(port: 0); // not the running app's port
  final u = await s.auth.createUser(name: 'Sam Owner', username: 'owner', password: 'password-123', role: Role.owner);
  await s.completeSetup(u);
  await s.setLlmModel(model);
  await s.refreshEngine();
  if (!s.llmReady) throw StateError('The model $model is not ready in Ollama.');
  final h = ScenarioRunner(s, isolated: true, callerModel: env['SCEN_CALLER_MODEL']);
  await h.prepareApps([for (final t in appTemplates) t.id]);
  print('Booted: ${appTemplates.length} apps, host ${s.host!.port}, db ${dir.path}');
  return h;
}
