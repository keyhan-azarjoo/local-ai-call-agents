import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:localailine/main.dart';
import 'package:localailine/services/auth.dart';
import 'package:localailine/state/app_state.dart';
import 'package:provider/provider.dart';
// ignore_for_file: avoid_print
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  /// Needs: python3 test/mcp_fixture/oauth_mcp_server.py running, and Ollama with qwen3:4b-instruct.
  testWidgets('expand tool note while answer is written', (t) async {
    final dir = await Directory.systemTemp.createTemp('ll_note');
    final state = AppState(dbPath: '${dir.path}/n.db')..openBrowser = (url) async {
      final c = HttpClient();
      final r1 = await (await c.getUrl(Uri.parse(url))..followRedirects = false).close();
      final loc = r1.headers.value('location')!; await r1.drain<void>();
      await (await (await c.getUrl(Uri.parse(loc))).close()).drain<void>(); c.close();
    };
    await state.init();
    final u = await state.auth.createUser(name: 'T', username: 'tester', password: 'password-123', role: Role.owner);
    await state.completeSetup(u);
    await state.host?.stop();
    await state.setLlmModel('qwen3:4b-instruct');
    await state.refreshEngine();
    final id = await state.db.insert('mcp_servers', {'name': 'Weighing', 'kind': 'http', 'target': 'http://127.0.0.1:8771/mcp', 'scope': 'me', 'enabled': 1, 'auth_mode': 'auto'});
    await state.mcp.connect(id, interactive: true);
    print('MCP ${state.mcp.status[id]}');
    state.go(PageId.chat);
    await t.binding.setSurfaceSize(const Size(1300, 900));
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: const LocalAILineApp()));
    for (var i = 0; i < 30; i++) { await t.pump(const Duration(milliseconds: 100)); }
    final errors = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) { errors.add(d.exceptionAsString()); };
    for (final q in ['What is the weight of lot-7? Then explain in three long paragraphs what that weight means.', 'And lot-9?']) {
      (find.byType(TextField).last.evaluate().first.widget as TextField).controller!.text = q;
      await t.tap(find.text('Send').last);
      var expanded = false;
      for (var i = 0; i < 1500; i++) {
        await t.pump(const Duration(milliseconds: 100));
        final notes = find.textContaining('Used Weighing');
        if (!expanded && notes.evaluate().isNotEmpty) {
          await t.tap(notes.last); expanded = true; // expand while still writing
        }
        if (i > 30 && find.text('Send').evaluate().isNotEmpty) break;
      }
      print('Q done expanded=$expanded errors=${errors.length}');
    }
    FlutterError.onError = prev;
    print('ERRORS ${errors.length}: ${errors.toSet().take(3).join(' || ')}');
    expect(errors, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
