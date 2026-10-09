import 'dart:convert';
import 'dart:io';

import 'package:localailine_core/data/db.dart';
import 'package:localailine_engine/engine.dart';
import 'package:localailine_model/llm.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake_openai.dart';

/// The engine without Flutter, on an OpenAI-compatible server (e.g. vLLM or LM Studio on a
/// home server): it starts and answers.
void main() {
  late Directory dir;
  late FakeOpenAi ai;
  late AppEngine engine;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ll-headless-');
    Db.supportDir = () async => dir;
    ai = FakeOpenAi();
    await ai.start();
    final path = p.join(dir.path, 'localailine.db');
    final db = await Db.open(path: path);
    await db.setSetting('llm.source', 'openai');
    await db.setSetting('llm.openai', jsonEncode(OpenAiServer(baseUrl: ai.base, apiKey: 'test-key', model: 'my-model').toJson()));
    await db.raw.close();
    engine = AppEngine(dbPath: path, loadAsset: (a) => File(p.join('..', '..', 'app', a)).readAsString());
    // (No owner and no sign-in: the desktop's host services — paired devices, Ollama — stay off.)
    await engine.init();
  });

  tearDown(() async {
    await engine.shutdown();
    await ai.server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('answers through the chosen OpenAI-compatible server', () async {
    expect(engine.llmSource, 'openai');
    final reply = await engine.agentReply([ChatMessage('user', 'Hi there')], scopes: {'all'}, approve: (_, _) async => false);
    expect(reply, isNotEmpty);
    expect(ai.chats.last['model'], 'my-model');
    expect(ai.auth.last, 'Bearer test-key');
  });
}
