// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/apps/apps_manager.dart';
import 'package:localailine/services/mcp/mcp_manager.dart';
import 'package:localailine/services/ollama.dart';

/// "Describe a change" with a real local model.
/// LOCALAILINE_LIVE_MODEL=qwen3:4b-instruct flutter test test/apps_change_live_test.dart
void main() {
  final model = Platform.environment['LOCALAILINE_LIVE_MODEL'];
  test('describe changes to the restaurant', () async {
    final tmp = Directory.systemTemp.createTempSync('chg');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final ollama = Ollama();
    Future<String> ask(List<ChatMessage> m, {bool json = false, String? model0}) async {
      final b = StringBuffer();
      await for (final t in ollama.chat(model!, m, json: json, temperature: 0.2, numCtx: 8192)) {
        b.write(t);
      }
      return b.toString();
    }

    final apps = AppsManager(db, McpManager(db, openBrowser: (_) async {}), ask: (m, {json = false, model}) => ask(m, json: json), visionModel: () async => null, log: (_) async {});
    final id = await apps.createFromTemplate(appTemplates.first, ava: false);
    for (final req in [
      'Make it dark and modern with a red colour',
      'Change the slogan to "Pizza until midnight"',
      'Orders need a phone number',
      'Add allergens to the menu',
      'Add a page about our story',
    ]) {
      final sw = Stopwatch()..start();
      final err = await apps.changeAnything(id, req);
      final s = (await apps.app(id))!.spec;
      print('[$req] ${sw.elapsed.inSeconds}s ${err ?? 'ok'} → style=${s.style} theme=${s.theme} tagline=${s.site['tagline']} '
          'orders=${s.table('orders')!.fields.map((f) => f.id).join(',')} menu=${s.table('menu_items')!.fields.map((f) => f.id).join(',')} pages=${s.pages.map((p) => p.id).join(',')}');
    }
    await apps.stopAll();
  }, skip: model == null ? 'set LOCALAILINE_LIVE_MODEL' : null, timeout: const Timeout(Duration(minutes: 20)));
}
