import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/apps/apps_manager.dart';
import 'package:localailine/services/mcp/mcp_manager.dart';

/// Dev helper: serves every template (ports listed in /tmp/tpl_ports) for a few minutes.
void main() {
  test('serve templates', () async {
    final tmp = Directory.systemTemp.createTempSync('tpl');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final apps = AppsManager(db, McpManager(db, openBrowser: (_) async {}), ask: (m, {json = false, model}) async => '{}', visionModel: () async => null, log: (_) async {});
    final out = StringBuffer();
    for (final t in appTemplates) {
      final id = await apps.createFromTemplate(t, ava: false);
      final a = (await apps.app(id))!;
      out.writeln('${t.id} ${a.port} ${a.pin}');
    }
    File('/tmp/tpl_ports').writeAsStringSync(out.toString());
    await Future.delayed(Duration(seconds: int.parse(Platform.environment['SERVE_SECONDS'] ?? '240')));
    await apps.stopAll();
  }, skip: Platform.environment['SERVE_SECONDS'] == null ? 'dev helper' : null, timeout: const Timeout(Duration(minutes: 30)));
}
