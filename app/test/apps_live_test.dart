// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:localailine_core/data/db.dart';
import 'package:localailine_apps/apps_manager.dart';
import 'package:localailine_core/services/mcp/mcp_manager.dart';
import 'package:localailine_core/services/ollama.dart';

/// Builds the restaurant app with a real local model, start to finish.
/// Run with: LOCALAILINE_LIVE_MODEL=qwen3:4b-instruct flutter test test/apps_live_test.dart
void main() {
  final model = Platform.environment['LOCALAILINE_LIVE_MODEL'];
  test('restaurant, built by a local model', () async {
    final tmp = Directory.systemTemp.createTempSync('apps_live');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final ollama = Ollama();
    final mcp = McpManager(db, openBrowser: (_) async {});
    Future<String> ask(List<ChatMessage> m, {bool json = false, String? model0}) async {
      final b = StringBuffer();
      await for (final t in ollama.chat(model!, m, json: json, temperature: 0.2, numCtx: 8192)) {
        b.write(t);
      }
      return b.toString();
    }

    final apps = AppsManager(db, mcp, ask: (m, {json = false, model}) => ask(m, json: json), visionModel: () async => null, log: (_) async {});
    final j = apps.newJob()
      ..request = 'I have a restaurant. I want a system for customers to search the menu, order food and select a table. '
          'The manager must be able to set the tables, the opening and closing time, and the list of food and prices.';
    final sw = Stopwatch()..start();
    await apps.askQuestions(j);
    print('questions (${sw.elapsed.inSeconds}s): ${j.questions} ${j.error ?? ''}');
    await apps.makePlan(j);
    print('plan (${sw.elapsed.inSeconds}s): ${j.error ?? ''}\n${j.plan?.outline()}');
    expect(j.plan, isNotNull);
    await apps.build(j);
    for (final s in j.steps) {
      print('${s.state.name.padRight(8)} ${s.title}: ${s.note}');
    }
    print('built in ${sw.elapsed.inSeconds}s');
    final a = (await apps.app(j.appId!))!;
    print(const JsonEncoder.withIndent(' ').convert(a.spec.toJson()));
    final home = await http.get(Uri.parse('http://127.0.0.1:${a.port}/api/_spec'));
    expect(home.statusCode, 200);
    for (final t in a.spec.tables) {
      print('${t.id}: ${(await http.get(Uri.parse('http://127.0.0.1:${a.port}/api/t/${t.id}'), headers: {'X-Key': a.pin})).body}');
    }
    // Ava's view of it.
    for (final srv in await mcp.servers()) {
      print('MCP ${srv.name} (${srv.scope}): ${srv.tools.map((t) => t.name).join(', ')}');
    }
    final orders = a.spec.tables.where((t) => t.access.add).firstOrNull;
    if (orders != null) {
      print('ORDERS: ${jsonEncode(orders.toJson())}');
      final srv = (await mcp.servers()).firstWhere((s) => s.scope == 'all');
      final menu = a.spec.tables.firstWhere((t) => t.id.contains('menu'));
      final first = (jsonDecode((await http.get(Uri.parse('http://127.0.0.1:${a.port}/api/t/${menu.id}'))).body) as List).first;
      final args = <String, dynamic>{
        for (final f in orders.fields.where((f) => !f.managerOnly))
          f.id: switch (f.type) {
            'links' => f.qty ? [{'item': first[menu.labelField], 'qty': 2}] : [first[menu.labelField]],
            'link' => '1',
            'date' => '2026-10-07',
            'time' => '19:00',
            'datetime' => '2026-10-07 19:00',
            'number' || 'money' => 2,
            'choice' => f.options.first,
            'yesno' => true,
            'email' => 'a@b.c',
            _ => 'Ann',
          },
      };
      final r = await mcp.call(srv.id, 'add_${orders.id}', args);
      print('ADD ORDER ${jsonEncode(args)} -> ${r.text}');
    }
    // Keep it running for a look: LOCALAILINE_LIVE_KEEP=1
    if (Platform.environment['LOCALAILINE_LIVE_KEEP'] == '1') {
      File('/tmp/app_port').writeAsStringSync('${a.port} ${a.pin}');
      await Future.delayed(const Duration(minutes: 4));
    }
    await apps.stopAll();
  }, skip: model == null ? 'set LOCALAILINE_LIVE_MODEL' : null, timeout: const Timeout(Duration(minutes: 20)));
}
