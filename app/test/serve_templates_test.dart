import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine_core/data/db.dart';
import 'package:localailine_apps/app_templates.dart';
import 'package:localailine_apps/apps_manager.dart';
import 'package:localailine_core/services/mcp/mcp_manager.dart';
import 'package:localailine_core/services/ollama.dart';

/// Dev helper: serves every template (ports listed in /tmp/tpl_ports) for a few minutes.
void main() {
  test('serve templates', () async {
    final tmp = Directory.systemTemp.createTempSync('tpl');
    final db = await Db.open(path: '${tmp.path}/t.db');
    // With SERVE_VISION=gemma3:4b, photos are read by that model.
    final vision = Platform.environment['SERVE_VISION'];
    Future<String> ask(List<ChatMessage> m, {bool json = false, String? model}) async {
      final b = StringBuffer();
      await for (final t in Ollama().chat(model ?? vision!, m, json: json, temperature: 0.1, numCtx: 8192)) {
        b.write(t);
      }
      return b.toString();
    }

    final apps = AppsManager(db, McpManager(db, openBrowser: (_) async {}), ask: ask, visionModel: () async => vision, log: (_) async {});
    final out = StringBuffer();
    for (final t in appTemplates.take(int.parse(Platform.environment['SERVE_COUNT'] ?? '10'))) {
      final id = await apps.createFromTemplate(t, ava: false);
      final a = (await apps.app(id))!;
      out.writeln('${t.id} ${a.port} ${a.pin}');
    }
    File('/tmp/tpl_ports').writeAsStringSync(out.toString());
    await Future.delayed(Duration(seconds: int.parse(Platform.environment['SERVE_SECONDS'] ?? '240')));
    await apps.stopAll();
  }, skip: Platform.environment['SERVE_SECONDS'] == null ? 'dev helper' : null, timeout: const Timeout(Duration(minutes: 30)));
}
