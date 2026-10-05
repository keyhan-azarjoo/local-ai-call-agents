import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:localailine/data/db.dart';
import 'package:localailine/services/agent_loop.dart';
import 'package:localailine/services/mcp/mcp_auth.dart';
import 'package:localailine/services/mcp/mcp_manager.dart';
import 'package:localailine/services/ollama.dart';

/// Runs against test/mcp_fixture/oauth_mcp_server.py — an MCP server with the
/// same sign-in shape as a hosted one (401 → discovery → registration → PKCE).
void main() {
  Process? server;
  late Db db;
  late Directory tmp;
  var browserOpened = 0;

  // Stands in for the user's browser: follows the sign-in redirect to our loopback page.
  Future<void> fakeBrowser(String url) async {
    browserOpened++;
    final c = HttpClient();
    final r1 = await (await c.getUrl(Uri.parse(url))..followRedirects = false).close();
    final loc = r1.headers.value('location')!;
    await r1.drain<void>();
    final r2 = await (await c.getUrl(Uri.parse(loc))).close();
    await r2.drain<void>();
    c.close();
  }

  setUpAll(() async {
    final ok = await Process.run('python3', ['-c', 'import mcp']);
    if (ok.exitCode != 0) return;
    server = await Process.start('python3', ['test/mcp_fixture/oauth_mcp_server.py']);
    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      try {
        await http.get(Uri.parse('http://127.0.0.1:8771/.well-known/oauth-protected-resource'));
        break;
      } catch (_) {}
    }
  });
  tearDownAll(() => server?.kill());

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ll_mcp');
    db = await Db.open(path: '${tmp.path}/t.db');
  });
  tearDown(() async {
    await db.raw.close();
    await tmp.delete(recursive: true);
  });

  test('401 challenge is parsed', () {
    final (meta, scope) = McpOAuth.parseChallenge('Bearer resource_metadata="https://x/.well-known/oauth-protected-resource", scope="a b"');
    expect(meta, 'https://x/.well-known/oauth-protected-resource');
    expect(scope, 'a b');
  });

  test('sign in, list tools, call, refresh, and let the AI use them', () async {
    if (server == null) return markTestSkipped('python mcp package not installed');
    final m = McpManager(db, openBrowser: fakeBrowser);
    final id = await db.insert('mcp_servers', {
      'name': 'Weighing', 'kind': 'http', 'target': 'http://127.0.0.1:8771/mcp', 'scope': 'me', 'enabled': 1, 'auth_mode': 'auto',
    });

    // Quiet connect must not open a browser; it reports that sign-in is needed.
    await m.connect(id);
    expect(m.status[id], McpStatus.needsSignIn);
    expect(browserOpened, 0);

    // Sign in (browser opens once), then tools are listed.
    await m.connect(id, interactive: true);
    expect(m.status[id], McpStatus.connected, reason: m.errors[id]);
    expect(browserOpened, 1);
    final srv = (await m.servers()).single;
    expect(srv.tools.map((t) => t.name), containsAll(['get_weight', 'record_weight']));
    expect(srv.tools.firstWhere((t) => t.name == 'get_weight').readOnly, isTrue);
    expect(srv.tools.firstWhere((t) => t.name == 'record_weight').readOnly, isFalse);
    expect(srv.secret['refreshToken'], isNotNull);

    final r = await m.call(id, 'get_weight', {'lot': 'lot-7'});
    expect(r.text, contains('412.5'));

    // Expired token: refresh silently, no new browser window.
    final s = Map<String, dynamic>.from(srv.secret)..['expiresAt'] = 1;
    await db.update('mcp_servers', id, {'secret': jsonEncode(s)});
    await m.disconnect(id);
    await m.connect(id);
    expect(m.status[id], McpStatus.connected);
    expect(browserOpened, 1);

    // The AI uses the tools (live local model, skipped without Ollama).
    final o = Ollama();
    final models = (await o.version()) == null ? <OllamaModel>[] : await o.installed();
    final model = models.where((x) => x.name == 'qwen3:4b-instruct').firstOrNull ?? models.firstOrNull;
    if (model == null) return;
    final tools = [
      for (final t in (await m.servers()).single.tools)
        ToolBinding(serverId: id, serverName: 'Weighing', tool: t, fnName: ToolBinding.safeName('Weighing', t.name))
    ];
    final events = <ToolEvent>[];
    final loop = ToolLoop();
    final answer = await loop.run(
      target: LocalTarget(model.name),
      messages: [ChatMessage('system', 'Use tools for data questions.'), ChatMessage('user', 'What is the weight of lot-7?')],
      tools: tools,
      approve: (_, _) async => false,
      runTool: (b, a) => m.call(b.serverId, b.tool.name, a),
      onEvent: events.add,
    );
    expect(events.map((e) => e.binding.tool.name), contains('get_weight'));
    expect(answer, contains('412'));

    // A write action asks first; declining means it never runs.
    events.clear();
    await loop.run(
      target: LocalTarget(model.name),
      messages: [ChatMessage('user', 'Record 500 kg for lot-9 now.')],
      tools: tools,
      approve: (_, _) async => false,
      runTool: (b, a) => m.call(b.serverId, b.tool.name, a),
      onEvent: events.add,
    );
    final write = events.where((e) => e.binding.tool.name == 'record_weight');
    expect(write, isNotEmpty);
    expect(write.every((e) => e.denied), isTrue);
    expect((await m.call(id, 'get_weight', {'lot': 'lot-9'})).text, contains('0 kg'));
    await m.closeAll();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('API key mode: a wrong key is reported, no browser opens', () async {
    if (server == null) return markTestSkipped('python mcp package not installed');
    final m = McpManager(db, openBrowser: fakeBrowser);
    final id = await db.insert('mcp_servers', {
      'name': 'Keyed', 'kind': 'http', 'target': 'http://127.0.0.1:8771/mcp', 'scope': 'me', 'enabled': 1,
      'auth_mode': 'token', 'secret': jsonEncode({'header': 'Authorization', 'value': 'Bearer wrong'}),
    });
    await m.connect(id, interactive: true);
    expect(m.status[id], McpStatus.error);
    expect(m.errors[id], contains('rejected the API key'));
  });

  test('Gemini schema cleaning drops unsupported keys', () {
    final out = ToolLoop.geminiSchema({
      r'$schema': 'x', 'type': 'object', 'additionalProperties': false,
      'properties': {'a': {'type': ['string', 'null'], 'title': 'A'}},
    }) as Map;
    expect(out.containsKey(r'$schema'), isFalse);
    expect(out.containsKey('additionalProperties'), isFalse);
    expect(out['properties']['a'], {'type': 'string', 'nullable': true});
  });
}
