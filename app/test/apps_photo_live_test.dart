// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localailine/data/db.dart';
import 'package:localailine/services/apps/app_templates.dart';
import 'package:localailine/services/apps/apps_manager.dart';
import 'package:localailine/services/mcp/mcp_manager.dart';
import 'package:localailine/services/ollama.dart';

/// Reads a menu photo with a real vision model.
/// LOCALAILINE_VISION_MODEL=gemma3:4b LOCALAILINE_PHOTO=/tmp/cdp/menu_photo.jpg flutter test test/apps_photo_live_test.dart
void main() {
  final model = Platform.environment['LOCALAILINE_VISION_MODEL'], photo = Platform.environment['LOCALAILINE_PHOTO'];
  test('menu from a photo', () async {
    final tmp = Directory.systemTemp.createTempSync('photo');
    final db = await Db.open(path: '${tmp.path}/t.db');
    final ollama = Ollama();
    Future<String> ask(List<ChatMessage> m, {bool json = false, String? model0}) async {
      final b = StringBuffer();
      await for (final t in ollama.chat(model0 ?? model!, m, json: json, temperature: 0.1, numCtx: 8192)) {
        b.write(t);
      }
      return b.toString();
    }

    final apps = AppsManager(db, McpManager(db, openBrowser: (_) async {}), ask: (m, {json = false, model}) => ask(m, json: json, model0: model), visionModel: () async => model, log: (_) async {});
    final id = await apps.createFromTemplate(appTemplates.first, ava: false, name: 'La Piccola Cucina');
    final sw = Stopwatch()..start();
    final rows = await apps.rowsFromPicture(id, 'menu_items', base64Encode(File(photo!).readAsBytesSync()));
    print('${rows.length} rows in ${sw.elapsed.inSeconds}s');
    for (final r in rows) {
      print(jsonEncode(r));
    }
    print('added ${await apps.addRows(id, 'menu_items', rows)}');
    await apps.stopAll();
  }, skip: model == null || photo == null ? 'set LOCALAILINE_VISION_MODEL and LOCALAILINE_PHOTO' : null, timeout: const Timeout(Duration(minutes: 10)));
}
